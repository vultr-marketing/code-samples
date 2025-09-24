variable "vultr_api_key" {
  description = "Vultr API key used to authenticate with the Vultr provider."
  type        = string
  sensitive   = true
}

variable "ovh_auth_url" {
  description = "OpenStack authentication URL for OVH Public Cloud."
  type        = string
  default     = "https://auth.cloud.ovh.net/v3"
}

variable "ovh_project_id" {
  description = "OVH Public Cloud project (tenant) ID used when authenticating with a token."
  type        = string
  default     = ""
}

variable "ovh_token" {
  description = "Short-lived OpenStack token. Not recommended for long runs."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ovh_application_credential_id" {
  description = "OVH OpenStack application credential ID."
  type        = string
  sensitive   = true
}

variable "ovh_application_credential_secret" {
  description = "OVH OpenStack application credential secret."
  type        = string
  sensitive   = true
}

variable "instance_plan" {
  description = "Vultr instance plan ID for all Vultr instances."
  type        = string
  default     = "vc2-1c-1gb"
}

variable "instance_os_id" {
  description = "Vultr OS ID (e.g., Ubuntu 22.04)."
  type        = number
  default     = 1743
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

variable "ovh_instance_flavor" {
  description = "OVH Public Cloud flavor name for instances (e.g., d2-2, b2-7)."
  type        = string
  default     = "d2-2"
}

variable "ovh_image_name" {
  description = "OVH Public Cloud image name for Ubuntu 22.04."
  type        = string
  default     = "Ubuntu 22.04"
}

variable "ovh_regions" {
  description = "Map of OVH regions with their configurations"
  type = map(object({
    region         = string
    v4_subnet      = string
    v4_subnet_mask = number
    flavor_name    = optional(string)
    image_name     = optional(string)
  }))
}

variable "vultr_regions" {
  description = "Map of Vultr regions with their configurations"
  type = map(object({
    region         = string
    v4_subnet      = string
    v4_subnet_mask = number
  }))
}

variable "headscale_region" {
  type = string
}

variable "ovh_manage_security_rules" {
  description = "Whether to add ingress rules to the default security group in OVH. Disable to avoid quota issues."
  type        = bool
  default     = false
}
