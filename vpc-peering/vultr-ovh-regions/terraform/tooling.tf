resource "tls_private_key" "mesh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "vultr_ssh_key" "gateway_public_key" {
  name    = "mesh-ssh-key"
  ssh_key = tls_private_key.mesh_key.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  file_permission = 600
  filename        = "${path.module}/id_rsa"
  content         = tls_private_key.mesh_key.private_key_pem
}

locals {
  ovh_selected = var.ovh_regions

  vultr_vpcs = merge({}, {
    for region_key, region_config in var.vultr_regions : region_config.region => {
      region         = region_config.region
      v4_subnet      = region_config.v4_subnet
      v4_subnet_mask = region_config.v4_subnet_mask
    }
  })
}

resource "vultr_vpc" "tailscale" {
  for_each = local.vultr_vpcs

  region         = each.value.region
  v4_subnet      = each.value.v4_subnet
  v4_subnet_mask = each.value.v4_subnet_mask
  description    = "Vultr x OVH VPC Peering for region ${each.value.region}"
}

data "openstack_networking_network_v2" "ext_net" {
  for_each = local.ovh_selected
  external = true
  region   = each.value.region
}

resource "openstack_networking_network_v2" "net" {
  for_each = local.ovh_selected
  name     = "net-${each.value.region}"
  region   = each.value.region
}

resource "openstack_networking_subnet_v2" "subnet" {
  for_each        = local.ovh_selected
  name            = "subnet-${each.value.region}"
  network_id      = openstack_networking_network_v2.net[each.key].id
  cidr            = "${each.value.v4_subnet}/${each.value.v4_subnet_mask}"
  ip_version      = 4
  enable_dhcp     = true
  dns_nameservers = ["1.1.1.1", "8.8.8.8"]
  region          = each.value.region
}

resource "openstack_networking_router_v2" "router" {
  for_each            = local.ovh_selected
  name                = "router-${each.value.region}"
  external_network_id = data.openstack_networking_network_v2.ext_net[each.key].id
  region              = each.value.region
}

resource "openstack_networking_router_interface_v2" "router_interface" {
  for_each  = local.ovh_selected
  router_id = openstack_networking_router_v2.router[each.key].id
  subnet_id = openstack_networking_subnet_v2.subnet[each.key].id
  region    = each.value.region
}

resource "openstack_networking_port_v2" "peer_port" {
  for_each              = local.ovh_selected
  name                  = "port-peer-${each.value.region}"
  network_id            = openstack_networking_network_v2.net[each.key].id
  admin_state_up        = true
  port_security_enabled = false
  region                = each.value.region
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet[each.key].id
  }
}

resource "openstack_networking_port_v2" "client_port" {
  for_each              = local.ovh_selected
  name                  = "port-client-${each.value.region}"
  network_id            = openstack_networking_network_v2.net[each.key].id
  admin_state_up        = true
  port_security_enabled = false
  region                = each.value.region
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet[each.key].id
  }
}

resource "openstack_compute_keypair_v2" "default" {
  for_each   = local.ovh_selected
  name       = "mesh-key-${each.value.region}"
  public_key = tls_private_key.mesh_key.public_key_openssh
  region     = each.value.region
}

data "openstack_networking_secgroup_v2" "default" {
  for_each = var.ovh_regions
  name     = "default"
  region   = each.value.region
}

resource "openstack_networking_secgroup_rule_v2" "default_rules" {
  for_each = var.ovh_manage_security_rules ? { for region_key, region_val in var.ovh_regions : region_key => region_val } : {}

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = data.openstack_networking_secgroup_v2.default[each.key].id
}

resource "vultr_firewall_group" "headscale" {
  description = "Firewall for Headscale control server"
}

resource "vultr_firewall_rule" "headscale_ssh" {
  firewall_group_id = vultr_firewall_group.headscale.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "22"
  notes             = "Allow SSH access"
}

resource "vultr_firewall_rule" "headscale_http" {
  firewall_group_id = vultr_firewall_group.headscale.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "8080"
  notes             = "Allow Headscale HTTP"
}

resource "vultr_firewall_rule" "headscale_stun" {
  firewall_group_id = vultr_firewall_group.headscale.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "3478"
  notes             = "Allow Headscale STUN"
}

resource "vultr_firewall_group" "peer" {
  description = "Firewall for Vultr peer instances"
}

resource "vultr_firewall_rule" "peer_ssh" {
  firewall_group_id = vultr_firewall_group.peer.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "22"
  notes             = "Allow SSH access"
}

resource "vultr_firewall_rule" "peer_tailscale" {
  firewall_group_id = vultr_firewall_group.peer.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "41641"
  notes             = "Allow Tailscale coordination"
}

resource "vultr_firewall_rule" "peer_https" {
  firewall_group_id = vultr_firewall_group.peer.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
  notes             = "Allow HTTPS/Tailscale"
}

resource "vultr_firewall_rule" "peer_iperf" {
  firewall_group_id = vultr_firewall_group.peer.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "5201"
  notes             = "Allow iperf3 TCP"
}

resource "vultr_firewall_rule" "peer_iperf_udp" {
  firewall_group_id = vultr_firewall_group.peer.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "5201"
  notes             = "Allow iperf3 UDP"
}

resource "vultr_firewall_rule" "peer_stun" {
  firewall_group_id = vultr_firewall_group.peer.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "3478"
  notes             = "Allow STUN UDP"
}

resource "vultr_firewall_group" "client" {
  description = "Firewall for Vultr client instances"
}

resource "vultr_firewall_rule" "client_ssh" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "22"
  notes             = "Allow SSH access"
}

resource "vultr_firewall_rule" "client_tailscale" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "41641"
  notes             = "Allow Tailscale coordination"
}

resource "vultr_firewall_rule" "client_https" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
  notes             = "Allow HTTPS/Tailscale"
}

resource "vultr_firewall_rule" "client_iperf" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "5201"
  notes             = "Allow iperf3 TCP"
}

resource "vultr_firewall_rule" "client_iperf_udp" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "5201"
  notes             = "Allow iperf3 UDP"
}

resource "vultr_firewall_rule" "client_stun" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "3478"
  notes             = "Allow STUN UDP"
}

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
%{for key, instance in vultr_instance.vultr_peer~}
        vultr-peer-${instance.region}:
          ansible_host: ${instance.main_ip}
          ansible_user: linuxuser
          region: ${instance.region}
          subnet: ${local.vultr_vpcs[instance.region].v4_subnet}/${local.vultr_vpcs[instance.region].v4_subnet_mask}
%{endfor~}
%{for k, v in local.ovh_selected~}
        ovh-peer-${v.region}:
          ansible_host: ${openstack_networking_floatingip_v2.fip_peer[k].address}
          ansible_user: ubuntu
          region: ${v.region}
          subnet: ${v.v4_subnet}/${v.v4_subnet_mask}
%{endfor~}
    client_servers:
      hosts:
%{for key, instance in vultr_instance.vultr_client~}
        vultr-client-${instance.region}:
          ansible_host: ${instance.main_ip}
          ansible_user: linuxuser
          region: ${instance.region}
          subnet: ${local.vultr_vpcs[instance.region].v4_subnet}/${local.vultr_vpcs[instance.region].v4_subnet_mask}
%{endfor~}
%{for k, v in local.ovh_selected~}
        ovh-client-${v.region}:
          ansible_host: ${openstack_networking_floatingip_v2.fip_client[k].address}
          ansible_user: ubuntu
          region: ${v.region}
          subnet: ${v.v4_subnet}/${v.v4_subnet_mask}
%{endfor~}
EOT
}

resource "null_resource" "generate_ansible_inventory" {
  triggers = {
    headscale_ip   = vultr_instance.headscale.main_ip
    vultr_peer_ips = join(",", [for _, v in vultr_instance.vultr_peer : v.main_ip])
    ovh_peer_ips   = join(",", [for k, v in openstack_networking_floatingip_v2.fip_peer : v.address])
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
    vultr_instance.vultr_client,
    openstack_compute_instance_v2.ovh_peer,
    openstack_compute_instance_v2.ovh_client
  ]
}

