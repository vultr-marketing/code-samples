# Represents example service
resource "vultr_instance" "client" {
  for_each    = { for idx, instance in var.tailscale_instances : instance.region => instance }
  plan        = var.instance_plan
  region      = each.value.region
  os_id       = var.os_id
  hostname    = "client-${each.value.region}"
  label       = "client-${each.value.region}"
  ssh_key_ids = ["${vultr_ssh_key.gateway_public_key.id}"]
  user_scheme = var.user_scheme
  vpc_ids     = [vultr_vpc.tailscale[each.value.region].id]
  script_id   = vultr_startup_script.clients.id
  depends_on  = [vultr_instance.tailscale]

  tags = [
    "client-node-${each.value.region}",
    "headscale-mesh"
  ]
}

output "client_ips" {
  description = "IP information for client instances"
  value = {
    for k, v in vultr_instance.client :
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