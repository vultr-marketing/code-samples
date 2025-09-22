# Headscale control server
resource "vultr_instance" "headscale" {
  plan              = var.instance_plan
  region            = var.headscale_region
  os_id             = var.instance_os_id
  label             = "headscale-${var.headscale_region}"
  hostname          = "headscale-${var.headscale_region}"
  user_scheme       = var.user_scheme
  user_data         = file("${path.module}/../cloud-init/headscale.yaml")
  firewall_group_id = vultr_firewall_group.headscale.id
  ssh_key_ids       = [vultr_ssh_key.gateway_public_key.id]

  tags = [
    "control-server",
    "headscale-mesh"
  ]
}

# Vultr peer instances
resource "vultr_instance" "vultr_peer" {
  for_each = var.vultr_regions

  plan              = var.instance_plan
  region            = each.value.region
  os_id             = var.instance_os_id
  label             = "vultr-peer-${each.value.region}"
  hostname          = "vultr-peer-${each.value.region}"
  user_scheme       = var.user_scheme
  user_data         = file("${path.module}/../cloud-init/tailscale.yaml")
  firewall_group_id = vultr_firewall_group.peer.id
  ssh_key_ids       = [vultr_ssh_key.gateway_public_key.id]
  vpc_ids           = [vultr_vpc.tailscale[each.value.region].id]
    tags = [
    "tailscale-peer",
    "gateway-node"
  ]
}

resource "google_compute_address" "gateway_ip" {
  for_each = var.gcp_regions
  name     = "gw-ip-${each.value.region}"
  region   = each.value.region
}

# GCP gateway instances
resource "google_compute_instance" "gateway" {
  for_each     = var.gcp_regions
  name         = "gcp-peer-${each.value.region}"
  machine_type = coalesce(try(each.value.machine_type, null), var.gcp_machine_type)
  zone         = each.value.zone
  can_ip_forward = true

  boot_disk {
    initialize_params {
      image = coalesce(try(each.value.image, null), "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts")
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet[each.key].id
    access_config {
      nat_ip = google_compute_address.gateway_ip[each.key].address
    }
  }

  metadata_startup_script = templatefile("${path.module}/../cloud-init/tailscale.yaml", {
    REGION = each.value.region
    INDEX  = 0
    TYPE   = "peer"
  })
  tags = ["tailscale-peer","gateway-node"]
}

output "headscale_control_server_ip" {
  description = "Public IP of the Headscale control server"
  value       = vultr_instance.headscale.main_ip
}

output "gateway_summary" {
  description = "Summary of all gateway nodes across providers"
  value = merge(
    {
      for k, v in vultr_instance.vultr_peer : v.region => {
        provider   = "vultr"
        name       = v.hostname
        private_ip = v.internal_ip
        public_ip  = v.main_ip
        subnet     = "${vultr_vpc.tailscale[v.region].v4_subnet}/${vultr_vpc.tailscale[v.region].v4_subnet_mask}"
      }
    },
    {
      for k, v in var.gcp_regions : v.region => {
        provider   = "gcp"
        name       = "gcp-peer-${v.region}"
        private_ip = google_compute_instance.gateway[k].network_interface[0].network_ip
        public_ip  = google_compute_address.gateway_ip[k].address
        subnet     = google_compute_subnetwork.subnet[k].ip_cidr_range
      }
    }
  )
}


