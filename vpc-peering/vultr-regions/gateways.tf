# Virtual Private Network
resource "vultr_vpc" "tailscale" {
  for_each       = { for idx, instance in var.tailscale_instances : instance.region => instance }
  region         = each.value.region
  v4_subnet      = each.value.subnet
  v4_subnet_mask = each.value.subnet_mask
  description    = "${each.value.region} VPC - Headscale Mesh Network"
}

# Control Server
resource "vultr_instance" "headscale" {
  plan        = var.instance_plan
  region      = var.headscale_region
  os_id       = var.os_id
  hostname    = "headscale-${var.headscale_region}"
  label       = "headscale-${var.headscale_region}"
  ssh_key_ids = ["${vultr_ssh_key.gateway_public_key.id}"]
  user_scheme = var.user_scheme
  user_data = templatefile("${path.module}/cloud-init/headscale.yaml", {
    TAILSCALE_REGIONS = join(" ", [for instance in var.tailscale_instances : instance.region])
  })

  tags = [
    "control-server",
    "headscale-mesh"
  ]
}

# Tailscale Client a.k.a. tailnet Peer
resource "vultr_instance" "tailscale" {
  for_each    = { for idx, instance in var.tailscale_instances : instance.region => instance }
  plan        = var.instance_plan
  region      = each.value.region
  os_id       = var.os_id
  hostname    = "gateway-${each.value.region}"
  label       = "gateway-${each.value.region}"
  ssh_key_ids = ["${vultr_ssh_key.gateway_public_key.id}"]
  user_scheme = var.user_scheme
  vpc_ids     = [vultr_vpc.tailscale[each.value.region].id]
  user_data = templatefile("${path.module}/cloud-init/tailscale.yaml", {
    REGION = each.value.region
  })

  tags = [
    "gateway-node-${each.value.region}",
    "headscale-mesh"
  ]
}

resource "tls_private_key" "mesh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "vultr_ssh_key" "gateway_public_key" {
  name    = "mesh-ssh-key"
  ssh_key = tls_private_key.mesh_key.public_key_openssh
}

resource "local_file" "sshPrivateKey" {
  file_permission = 600
  filename        = "${path.module}/id_rsa"
  content         = tls_private_key.mesh_key.private_key_pem
}

output "headscale_ip" {
  description = "IP address of the Headscale instance"
  value       = vultr_instance.headscale.main_ip
}

output "tailscale_ips" {
  description = "Detailed IP information for Tailscale instances"
  value = {
    for k, v in vultr_instance.tailscale :
    k => {
      public_ip  = v.main_ip
      private_ip = v.internal_ip
      subnet = lookup({
        for region, vpc in vultr_vpc.tailscale :
        vpc.id => "${vpc.v4_subnet}/${vpc.v4_subnet_mask}"
      }, one(v.vpc_ids), null)
    }
  }
}
