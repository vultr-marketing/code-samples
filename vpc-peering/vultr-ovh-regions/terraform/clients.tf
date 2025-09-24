# Vultr client instances
resource "vultr_instance" "vultr_client" {
  for_each = var.vultr_regions

  plan              = var.instance_plan
  region            = each.value.region
  os_id             = var.instance_os_id
  label             = "vultr-client-${each.value.region}"
  hostname          = "vultr-client-${each.value.region}"
  user_scheme       = var.user_scheme
  firewall_group_id = vultr_firewall_group.client.id
  ssh_key_ids       = [vultr_ssh_key.gateway_public_key.id]
  vpc_ids           = [vultr_vpc.tailscale[each.value.region].id]

  tags = [
    "client-node"
  ]
}

# Lookup Ubuntu image per OVH region for clients
data "openstack_images_image_v2" "ubuntu_clients" {
  for_each    = local.ovh_selected
  name        = coalesce(try(each.value.image_name, null), var.ovh_image_name)
  most_recent = true
  region      = each.value.region
}

# OVH client instances
resource "openstack_compute_instance_v2" "ovh_client" {
  for_each    = local.ovh_selected
  name        = "ovh-client-${each.value.region}"
  flavor_name = coalesce(try(each.value.flavor_name, null), var.ovh_instance_flavor)
  image_id    = data.openstack_images_image_v2.ubuntu_clients[each.key].id

  key_pair = openstack_compute_keypair_v2.default[each.key].name

  network {
    port = openstack_networking_port_v2.client_port[each.key].id
  }
  region     = each.value.region
  depends_on = [openstack_networking_subnet_v2.subnet]
}

resource "openstack_networking_floatingip_v2" "fip_client" {
  for_each = local.ovh_selected
  pool     = data.openstack_networking_network_v2.ext_net[each.key].name
  region   = each.value.region
}

resource "openstack_networking_floatingip_associate_v2" "fip_assoc_client" {
  for_each    = local.ovh_selected
  floating_ip = openstack_networking_floatingip_v2.fip_client[each.key].address
  port_id     = openstack_compute_instance_v2.ovh_client[each.key].network[0].port
  depends_on  = [openstack_networking_router_interface_v2.router_interface]
  region      = each.value.region
}

# Client nodes summary
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
      for k, v in var.ovh_regions : v.region => {
        provider   = "ovh"
        name       = "ovh-client-${v.region}"
        private_ip = openstack_compute_instance_v2.ovh_client[k].network[0].fixed_ip_v4
        public_ip  = openstack_networking_floatingip_v2.fip_client[k].address
        subnet     = "${v.v4_subnet}/${v.v4_subnet_mask}"
      }
    }
  )
}
