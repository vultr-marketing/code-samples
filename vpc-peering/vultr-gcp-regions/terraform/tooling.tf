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

resource "vultr_startup_script" "clients" {
  name   = "vultr-x-gcp-mesh-script"
  type   = "boot"
  script = base64encode(file("${path.module}/../scripts/mesh-init.sh"))
}

resource "google_compute_project_metadata_item" "ssh_keys" {
  key   = "ssh-keys"
  value = "ubuntu:${tls_private_key.mesh_key.public_key_openssh}"
}

locals {
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
  description    = "Vultr x GCP VPC Peering for region ${each.value.region}"
}

# GCP Network and Subnets
resource "google_compute_network" "vpc" {
  for_each                = var.gcp_regions
  name = "vultr-gcp-vpc-${each.value.region}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  for_each      = var.gcp_regions
  name          = "subnet-${each.value.region}"
  ip_cidr_range = each.value.subnet_cidr
  network       = google_compute_network.vpc[each.key].id
  region        = each.value.region
}

locals {
  routes_to_vultr = {
    for pair in flatten([
      for gk, gv in var.gcp_regions : [
        for vk, vv in local.vultr_vpcs : {
          key        = "${gk}-${vk}"
          gcp_key    = gk
          gcp_region = gv.region
          dest       = "${vv.v4_subnet}/${vv.v4_subnet_mask}"
        }
      ]
    ]) : pair.key => pair
  }

  routes_inter_gcp = {
    for pair in flatten([
      for gk, gv in var.gcp_regions : [
        for ok, ov in var.gcp_regions : {
          key        = "${gk}-${ok}"
          gcp_key    = gk
          gcp_region = gv.region
          dest       = google_compute_subnetwork.subnet[ok].ip_cidr_range
        } if gk != ok
      ]
    ]) : pair.key => pair
  }
}

resource "google_compute_route" "to_vultr" {
  for_each = local.routes_to_vultr

  name              = "to-vultr-${each.value.gcp_region}-${replace(replace(each.value.dest, "/", "-"), ".", "-")}"
  network           = google_compute_network.vpc[each.value.gcp_key].name
  dest_range        = each.value.dest
  next_hop_instance = google_compute_instance.gateway[each.value.gcp_key].self_link
  priority          = 1000
}

resource "google_compute_route" "to_gcp" {
  for_each = local.routes_inter_gcp

  name              = "to-gcp-${each.value.gcp_region}-${replace(replace(each.value.dest, "/", "-"), ".", "-")}"
  network           = google_compute_network.vpc[each.value.gcp_key].name
  dest_range        = each.value.dest
  next_hop_instance = google_compute_instance.gateway[each.value.gcp_key].self_link
  priority          = 1000
}

resource "google_compute_firewall" "mesh" {
  for_each = var.gcp_regions
  name     = "allow-mesh-${each.value.region}"
  network  = google_compute_network.vpc[each.key].name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  allow {
    protocol = "udp"
    ports    = ["41641"]
  }
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  allow {
    protocol = "udp"
    ports    = ["443"]
  }
  allow {
    protocol = "tcp"
    ports    = ["5201"]
  }
  allow {
    protocol = "udp"
    ports    = ["5201"]
  }
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "udp"
    ports    = ["3478"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gateway-node", "client-node", "tailscale-peer"]
}

# Vultr Firewall for Headscale
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

# Vultr Firewall for Peer instances
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

# STUN for NAT traversal
resource "vultr_firewall_rule" "peer_stun" {
  firewall_group_id = vultr_firewall_group.peer.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "3478"
  notes             = "Allow STUN UDP"
}

# Vultr Firewall for Client instances
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

# STUN for NAT traversal
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
%{for k, v in var.gcp_regions~}
        gcp-peer-${v.region}:
          ansible_host: ${google_compute_address.gateway_ip[k].address}
          ansible_user: ubuntu
          region: ${v.region}
          subnet: ${google_compute_subnetwork.subnet[k].ip_cidr_range}
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
%{for k, v in var.gcp_regions~}
        gcp-client-${v.region}:
          ansible_host: ${google_compute_instance.client[k].network_interface[0].access_config[0].nat_ip}
          ansible_user: ubuntu
          region: ${v.region}
          subnet: ${google_compute_subnetwork.subnet[k].ip_cidr_range}
%{endfor~}
EOT
}

resource "null_resource" "generate_ansible_inventory" {
  triggers = {
    headscale_ip   = vultr_instance.headscale.main_ip
    vultr_peer_ips = join(",", [for _, v in vultr_instance.vultr_peer : v.main_ip])
    gcp_peer_ips   = join(",", [for k, v in var.gcp_regions : google_compute_address.gateway_ip[k].address])
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
    google_compute_instance.gateway,
    google_compute_instance.client
  ]
}
