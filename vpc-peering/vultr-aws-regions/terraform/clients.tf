# Vultr Client instances (Client nodes)
resource "vultr_instance" "vultr_client" {
  for_each = var.vultr_regions

  plan        = var.instance_plan
  region      = each.value.region
  os_id       = var.instance_os_id
  hostname    = "vultr-client-${each.value.region}"
  label       = "vultr-client-${each.value.region}"
  ssh_key_ids = [vultr_ssh_key.gateway_public_key.id]
  vpc_ids     = [vultr_vpc.tailscale[each.value.region].id]
  user_scheme = var.user_scheme
  script_id   = vultr_startup_script.clients.id

  tags = [
    "headscale-client",
    "application-node"
  ]
}

# AWS Client instances (Client nodes)
resource "aws_instance" "aws_client" {
  for_each               = var.aws_regions
  region                 = each.value.region
  ami                    = coalesce(try(each.value.ami_id, null), data.aws_ami.ubuntu[each.key].id)
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [aws_security_group.mesh[each.key].id]
  subnet_id              = try(aws_subnet.public[each.key].id, try(data.aws_subnets.by_cidr[each.key].ids[0], null))
  associate_public_ip_address = true
  key_name               = aws_key_pair.region[each.key].key_name

  tags = { Name = "aws-client-${each.value.region}-0", Role = "client" }
}

resource "aws_eip" "client" {
  for_each = var.aws_regions
  region   = each.value.region
  domain   = "vpc"

  tags = { Name = "mesh-client-eip-${each.value.region}" }
}

resource "aws_eip_association" "client" {
  for_each      = var.aws_regions
  region        = each.value.region
  allocation_id = aws_eip.client[each.key].id
  instance_id   = aws_instance.aws_client[each.key].id
}


# Client nodes summary (both Vultr and AWS)
output "client_summary" {
  description = "Summary of all client nodes across providers"
  value = merge(
    # Vultr clients
    {
      for k, v in vultr_instance.vultr_client : v.region => {
        provider    = "vultr"
        name        = v.hostname
        private_ip  = v.internal_ip
        public_ip   = v.main_ip
        subnet      = "${vultr_vpc.tailscale[v.region].v4_subnet}/${vultr_vpc.tailscale[v.region].v4_subnet_mask}"
      }
    },
    # AWS clients
    {
      for k, v in var.aws_regions : v.region => {
        provider    = "aws"
        name        = "aws-client-${v.region}"
        private_ip  = aws_instance.aws_client[k].private_ip
        public_ip   = aws_eip.client[k].public_ip
        subnet      = data.aws_subnet.aws_client_subnet[k].cidr_block
      }
    }
  )
}