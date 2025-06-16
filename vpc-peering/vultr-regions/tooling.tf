resource "vultr_startup_script" "clients" {
  name   = "headscale-mesh-init-script"
  type   = "boot"
  script = base64encode(templatefile("${path.module}/script/client.sh", {}))
}

locals {
  ansible_inventory_content = <<-EOT
---
all:
  children:
    headscale_servers:
      hosts:
        headscale:
          ansible_host: ${vultr_instance.headscale.main_ip}
    tailscale_servers:
      hosts:
%{ for region, instance in vultr_instance.tailscale ~}
        ${region}:
          ansible_host: ${instance.main_ip}
          region: ${region}
%{ endfor ~}
EOT
}

output "ansible_inventory" {
  value = local.ansible_inventory_content
}

resource "null_resource" "generate_ansible_inventory" {
  triggers = {
    headscale_ip = vultr_instance.headscale.main_ip
    tailscale_ips = jsonencode({
      for region, instance in vultr_instance.tailscale : region => {
        public_ip  = instance.main_ip
        private_ip = instance.internal_ip
        subnet     = vultr_vpc.tailscale[region].v4_subnet
        region     = region
      }
    })
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/ansible/inventory.yml <<EOF
${local.ansible_inventory_content}
EOF
    EOT
  }

  depends_on = [
    vultr_instance.headscale,
    vultr_instance.tailscale
  ]
}