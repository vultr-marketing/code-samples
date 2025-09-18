locals {
  ansible_inventory_content = <<-EOT
---
all:
  vars:
    ansible_ssh_private_key_file: ../terraform/id_rsa
  children:
    headscale_servers:
      hosts:
        headscale:
          ansible_host: ${vultr_instance.headscale.main_ip}
          ansible_user: linuxuser
    tailscale_servers:
      hosts:
%{ for k, v in vultr_instance.vultr_peer ~}
        ${v.hostname}:
          ansible_host: ${v.main_ip}
          ansible_user: linuxuser
          region: ${v.region}
          subnet: ${vultr_vpc.tailscale[v.region].v4_subnet}/${vultr_vpc.tailscale[v.region].v4_subnet_mask}
%{ endfor ~}
%{ for k, v in var.aws_regions ~}
        aws-peer-${v.region}:
          ansible_host: ${aws_eip.gateway[k].public_ip}
          ansible_user: ubuntu
          region: ${v.region}
          subnet: ${data.aws_subnet.aws_gateway_subnet[k].cidr_block}
%{ endfor ~}
    client_servers:
      hosts:
%{ for k, v in vultr_instance.vultr_client ~}
        ${v.hostname}:
          ansible_host: ${v.main_ip}
          ansible_user: linuxuser
          region: ${v.region}
          subnet: ${vultr_vpc.tailscale[v.region].v4_subnet}/${vultr_vpc.tailscale[v.region].v4_subnet_mask}
%{ endfor ~}
%{ for k, v in var.aws_regions ~}
        aws-client-${v.region}:
          ansible_host: ${aws_eip.client[k].public_ip}
          ansible_user: ubuntu
          region: ${v.region}
          subnet: ${data.aws_subnet.aws_client_subnet[k].cidr_block}
%{ endfor ~}
EOT
}

locals {
  headscale_region = var.headscale_region

  vultr_vpcs = merge({}, {
    for region_key, region_config in var.vultr_regions : region_config.region => {
      region         = region_config.region
      v4_subnet      = region_config.v4_subnet
      v4_subnet_mask = region_config.v4_subnet_mask
    }
  })
}

# VPC for Vultr Tailscale instances
resource "vultr_vpc" "tailscale" {
  for_each = local.vultr_vpcs

  region         = each.value.region
  description    = "Vultr x AWS VPC Peering for region ${each.value.region}"
  v4_subnet      = each.value.v4_subnet
  v4_subnet_mask = each.value.v4_subnet_mask
}

resource "null_resource" "generate_ansible_inventory" {
  triggers = {
    headscale_ip    = vultr_instance.headscale.main_ip
    vultr_peer_ips  = join(",", [for _, v in vultr_instance.vultr_peer : v.main_ip])
    aws_peer_ips    = join(",", [for k, v in var.aws_regions : aws_instance.aws_gateway[k].public_ip])
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/../ansible
      cat > ${path.module}/../ansible/inventory.yml <<EOF
${local.ansible_inventory_content}
EOF
    EOT
  }

  depends_on = [
    vultr_instance.headscale,
    vultr_instance.vultr_peer,
    aws_instance.aws_gateway,
    aws_instance.aws_client
  ]
}

# AWS VPC Resources
locals {
  aws_subnet_cidr_requests = { for k, v in var.aws_regions : k => {
    region = v.region
    cidr   = try(v.subnet_cidr, null)
  } if try(v.subnet_cidr, null) != null }
}

data "aws_subnets" "by_cidr" {
  for_each = local.aws_subnet_cidr_requests
  region   = each.value.region

  filter {
    name   = "cidr-block"
    values = [each.value.cidr]
  }
}

data "aws_subnet" "aws_gateway_subnet" {
  for_each = var.aws_regions
  region   = each.value.region
  id       = aws_instance.aws_gateway[each.key].subnet_id
}

data "aws_subnet" "aws_client_subnet" {
  for_each = var.aws_regions
  region   = each.value.region
  id       = aws_instance.aws_client[each.key].subnet_id
}

resource "aws_key_pair" "region" {
  for_each   = var.aws_regions
  region     = each.value.region
  key_name   = "mesh-key-${each.value.region}-${random_id.key_suffix.hex}"
  public_key = tls_private_key.mesh_key.public_key_openssh
}

locals {
  aws_vpc_requests = { for k, v in var.aws_regions : k => v if try(v.vpc_cidr, null) != null && try(v.public_subnet, null) != null }
}

resource "aws_vpc" "custom" {
  for_each = local.aws_vpc_requests
  region   = each.value.region
  cidr_block           = each.value.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "Vultr x AWS VPC Peering for region ${each.value.region}" }
}

resource "aws_internet_gateway" "custom" {
  for_each = local.aws_vpc_requests
  region   = each.value.region
  vpc_id   = aws_vpc.custom[each.key].id

  tags = { Name = "mesh-igw-${each.value.region}" }
}

resource "aws_route_table" "public" {
  for_each = local.aws_vpc_requests
  region   = each.value.region
  vpc_id   = aws_vpc.custom[each.key].id

  # Default route to internet
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.custom[each.key].id
  }

  # Routes to other AWS VPCs via local gateway instance
  dynamic "route" {
    for_each = {
      for k, v in var.aws_regions : k => v
      if k != each.key  # Exclude self
    }
    content {
      cidr_block           = route.value.vpc_cidr
      network_interface_id = aws_instance.aws_gateway[each.key].primary_network_interface_id
    }
  }

  # Routes to Vultr VPCs via local gateway instance
  dynamic "route" {
    for_each = var.vultr_regions
    content {
      cidr_block           = "${route.value.v4_subnet}/${route.value.v4_subnet_mask}"
      network_interface_id = aws_instance.aws_gateway[each.key].primary_network_interface_id
    }
  }

  tags = { Name = "mesh-public-rt-${each.value.region}" }
}

resource "aws_subnet" "public" {
  for_each          = local.aws_vpc_requests
  region            = each.value.region
  vpc_id            = aws_vpc.custom[each.key].id
  cidr_block        = each.value.public_subnet
  map_public_ip_on_launch = true

  tags = { Name = "mesh-public-subnet-${each.value.region}" }
}

resource "aws_route_table_association" "public" {
  for_each       = local.aws_vpc_requests
  region         = each.value.region
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[each.key].id
}

# Vultr Firewall for Headscale server
resource "vultr_firewall_group" "headscale" {
  description = "Firewall for Headscale control server"
}

resource "vultr_firewall_rule" "headscale_ssh" {
  firewall_group_id = vultr_firewall_group.headscale.id
  protocol         = "tcp"
  ip_type          = "v4"
  subnet           = "0.0.0.0"
  subnet_size      = 0
  port             = "22"
  notes            = "Allow SSH access"
}

resource "vultr_firewall_rule" "headscale_http" {
  firewall_group_id = vultr_firewall_group.headscale.id
  protocol         = "tcp"
  ip_type          = "v4"
  subnet           = "0.0.0.0"
  subnet_size      = 0
  port             = "8080"
  notes            = "Allow Headscale HTTP"
}

resource "vultr_firewall_rule" "headscale_stun" {
  firewall_group_id = vultr_firewall_group.headscale.id
  protocol         = "udp"
  ip_type          = "v4"
  subnet           = "0.0.0.0"
  subnet_size      = 0
  port             = "3478"
  notes            = "Allow Headscale STUN"
}

# AWS Security Group for Tailscale peers
resource "aws_security_group" "mesh" {
  for_each    = var.aws_regions
  region      = each.value.region
  name_prefix = "mesh-sg-${each.value.region}-"
  description = "Allow SSH, Tailscale and iperf3"
  vpc_id      = try(aws_vpc.custom[each.key].id, null)

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5201
    to_port     = 5201
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5201
    to_port     = 5201
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "89"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SSH Key Pair for instances
resource "tls_private_key" "mesh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "vultr_ssh_key" "gateway_public_key" {
  name    = "mesh-ssh-key"
  ssh_key = tls_private_key.mesh_key.public_key_openssh
}

resource "random_id" "key_suffix" {
  byte_length = 4
}

resource "local_file" "ssh_private_key" {
  file_permission = 600
  filename        = "${path.module}/id_rsa"
  content         = tls_private_key.mesh_key.private_key_pem
}

# Vultr startup script for client nodes using mesh-init.sh
resource "vultr_startup_script" "clients" {
  name   = "vultr-x-aws-mesh-script"
  type   = "boot"
  script = base64encode(file("${path.module}/../scripts/mesh-init.sh"))
}
