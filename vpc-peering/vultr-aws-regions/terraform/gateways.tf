# Headscale control server instance
resource "vultr_instance" "headscale" {
  plan              = var.instance_plan
  region            = local.headscale_region
  os_id             = var.instance_os_id
  hostname          = "headscale-${local.headscale_region}"
  label             = "headscale-${local.headscale_region}"
  ssh_key_ids       = [vultr_ssh_key.gateway_public_key.id]
  user_scheme       = var.user_scheme
  firewall_group_id = vultr_firewall_group.headscale.id

  user_data = file("${path.module}/../cloud-init/headscale.yaml")

  tags = [
    "control-server",
    "headscale-mesh"
  ]
}

# Vultr Tailscale peer instances (Gateway nodes)
resource "vultr_instance" "vultr_peer" {
  for_each = var.vultr_regions

  plan        = var.instance_plan
  region      = each.value.region
  os_id       = var.instance_os_id
  hostname    = "vultr-peer-${each.value.region}"
  label       = "vultr-peer-${each.value.region}"
  ssh_key_ids = [vultr_ssh_key.gateway_public_key.id]
  vpc_ids     = [vultr_vpc.tailscale[each.value.region].id]
  user_scheme = var.user_scheme

  user_data = templatefile("${path.module}/../cloud-init/tailscale.yaml", {
    REGION = each.value.region
    INDEX  = 0
    TYPE   = "peer"
  })

  tags = [
    "tailscale-peer",
    "headscale-mesh",
    "gateway-node"
  ]
}

# AMI data source for AWS instances
data "aws_availability_zones" "available" {
  for_each = var.aws_regions
  region   = each.value.region
  state    = "available"
}

data "aws_ami" "ubuntu" {
  for_each    = var.aws_regions
  region      = each.value.region
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# AWS Gateway Elastic IP
resource "aws_eip" "gateway" {
  for_each = var.aws_regions
  region   = each.value.region
  domain   = "vpc"

  tags = { Name = "mesh-gateway-eip-${each.value.region}" }
}

resource "aws_eip_association" "gateway" {
  for_each      = var.aws_regions
  region        = each.value.region
  allocation_id = aws_eip.gateway[each.key].id
  instance_id   = aws_instance.aws_gateway[each.key].id
}

# AWS Gateway instances (Tailscale peers)
resource "aws_instance" "aws_gateway" {
  for_each               = var.aws_regions
  region                 = each.value.region
  ami                    = coalesce(try(each.value.ami_id, null), data.aws_ami.ubuntu[each.key].id)
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [aws_security_group.mesh[each.key].id]
  subnet_id              = try(aws_subnet.public[each.key].id, try(data.aws_subnets.by_cidr[each.key].ids[0], null))
  associate_public_ip_address = true
  key_name               = aws_key_pair.region[each.key].key_name
  source_dest_check = false

  user_data = templatefile("${path.module}/../cloud-init/tailscale.yaml", {
    REGION = each.value.region
    INDEX  = 0
    TYPE   = "peer"
  })

  tags = { Name = "aws-peer-${each.value.region}", Role = "gateway" }
}

# Headscale control server IP
output "headscale_control_server_ip" {
  description = "Public IP of the Headscale control server"
  value       = vultr_instance.headscale.main_ip
}

# Gateway nodes summary (both Vultr and AWS)
output "gateway_summary" {
  description = "Summary of all gateway nodes across providers"
  value = merge(
    # Vultr gateways (peers)
    {
      for k, v in vultr_instance.vultr_peer : v.region => {
        provider    = "vultr"
        name        = v.hostname
        private_ip  = v.internal_ip
        public_ip   = v.main_ip
        subnet      = "${vultr_vpc.tailscale[v.region].v4_subnet}/${vultr_vpc.tailscale[v.region].v4_subnet_mask}"
      }
    },
    # AWS gateways (peers)
    {
      for k, v in var.aws_regions : v.region => {
        provider    = "aws"
        name        = "aws-peer-${v.region}"
        private_ip  = aws_instance.aws_gateway[k].private_ip
        public_ip   = aws_eip.gateway[k].public_ip
        subnet      = data.aws_subnet.aws_gateway_subnet[k].cidr_block
      }
    }
  )
}