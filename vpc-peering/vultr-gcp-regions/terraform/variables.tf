variable "instance_plan" {
  description = "Default plan for Vultr instances (Headscale, peers, clients)"
  type        = string
}

variable "instance_os_id" {
  description = "Default OS ID for Vultr instances"
  type        = number
}

variable "vultr_api_key" {
  description = "Vultr API key used to authenticate with the Vultr provider."
  type        = string
  sensitive   = true
}

variable "gcp_project_id" {
  description = "GCP Project ID."
  type        = string
}

variable "gcp_credentials_file" {
  description = "Path to GCP service account key file."
  type        = string
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

variable "gcp_machine_type" {
  description = "GCP machine type to use for GCP instances"
  type        = string
  default     = "e2-micro"
}

variable "gcp_regions" {
  description = "Map of GCP regions with their configurations"
  type = map(object({
    region       = string
    zone         = string
    subnet_cidr  = string
    machine_type = optional(string)
    image        = optional(string)
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

variable "external_clients" {
  description = "List of non-Vultr/GCP Tailscale clients"
  type = list(object({
    name        = string
    region      = string
    public_ip   = string
    private_ip  = string
    subnet      = string
    subnet_mask = number
    provider    = string
  }))
  default = []
}

variable "headscale_region" {
  description = "Vultr region code for the Headscale control server"
  type        = string
}
