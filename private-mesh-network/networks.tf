# VPCs for tailscale instances
resource "vultr_vpc" "tailscale" {
  for_each       = { for idx, instance in var.tailscale_instances : instance.region => instance }
  region         = each.value.region
  description    = "VPC for tailscale instance in ${each.value.region}"
  v4_subnet      = each.value.subnet
  v4_subnet_mask = each.value.subnet_mask
}

## Variables

variable "vultr_api_key" {
  description = "Vultr API Key for authentication"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.vultr_api_key) > 0
    error_message = "Vultr API key must not be empty."
  }
}

variable "instance_plan" {
  description = "Instance plan/size to use for all instances"
  type        = string
  default     = "vc2-4c-8gb"
}

variable "user_scheme" {
  description = "User scheme for instance access"
  type        = string
  default     = "limited"
  validation {
    condition     = contains(["limited", "root"], var.user_scheme)
    error_message = "User scheme must be either 'limited' or 'root'."
  }
}

# Headscale instance variables
variable "headscale_region" {
  description = "Region for Headscale instance"
  type        = string
  validation {
    condition     = can(regex("^[a-z]{3}$", var.headscale_region))
    error_message = "Region must be a 3-letter code (e.g., ams, atl)."
  }
}

# Tailscale instances variables
variable "tailscale_instances" {
  description = "List of tailscale instance configurations"
  type = list(object({
    region      = string
    subnet      = string
    subnet_mask = number
  }))
  validation {
    condition     = alltrue([for instance in var.tailscale_instances : can(regex("^[a-z]{3}$", instance.region))])
    error_message = "All regions must be 3-letter codes (e.g., ams, atl)."
  }
  validation {
    condition     = alltrue([for instance in var.tailscale_instances : can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", instance.subnet))])
    error_message = "All subnets must be valid IPv4 addresses."
  }
  validation {
    condition     = alltrue([for instance in var.tailscale_instances : instance.subnet_mask >= 8 && instance.subnet_mask <= 32])
    error_message = "Subnet masks must be between 8 and 32."
  }
}

variable "ssh_key_path" {
  description = "Path to the SSH private key file"
  type        = string
  default     = "./id_rsa"
}

variable "os_id" {
  description = "OS ID for the instances"
  type        = number
  default     = 2284 # Ubuntu 24.04
}

## Startup scripts for clients
resource "vultr_startup_script" "clients" {
  name   = "mesh-network-clients-init-script"
  type   = "boot"
  script = base64encode(templatefile("${path.module}/script/client.sh", {}))
}

## Local variables for Ansible inventory
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

## Outputs for Ansible

output "ansible_inventory" {
  value = local.ansible_inventory_content
}

## Generate Ansible inventory file
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