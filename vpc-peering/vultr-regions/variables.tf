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