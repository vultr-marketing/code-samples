# Vultr client instances
resource "vultr_instance" "vultr_client" {
  for_each = var.vultr_regions

  plan              = var.instance_plan
  region            = each.value.region
  os_id             = var.instance_os_id
  label             = "vultr-client-${each.value.region}"
  hostname          = "vultr-client-${each.value.region}"
  user_scheme       = var.user_scheme
  script_id         = vultr_startup_script.clients.id
  firewall_group_id = vultr_firewall_group.client.id
  ssh_key_ids       = [vultr_ssh_key.gateway_public_key.id]
  vpc_ids           = [vultr_vpc.tailscale[each.value.region].id]

  tags = [
    "client-node"
  ]

}

# GCP client instances
resource "google_compute_instance" "client" {
  for_each     = var.gcp_regions
  name         = "gcp-client-${each.value.region}"
  machine_type = coalesce(try(each.value.machine_type, null), var.gcp_machine_type)
  zone         = each.value.zone

  boot_disk {
    initialize_params {
      image = coalesce(try(each.value.image, null), "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts")
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet[each.key].id
    access_config {}
  }

  tags = ["client-node"]
}

# Client nodes summary (both Vultr and GCP)
output "client_summary" {
  description = "Summary of all client nodes across providers"
  value = merge(
    {
      for k, v in vultr_instance.vultr_client : v.region => {
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
        name       = "gcp-client-${v.region}"
        private_ip = google_compute_instance.client[k].network_interface[0].network_ip
        public_ip  = google_compute_instance.client[k].network_interface[0].access_config[0].nat_ip
        subnet     = google_compute_subnetwork.subnet[k].ip_cidr_range
      }
    }
  )
}


