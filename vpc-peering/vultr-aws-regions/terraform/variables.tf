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

variable "aws_access_key" {
  description = "AWS Access Key ID."
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key."
  type        = string
  sensitive   = true
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

variable "aws_regions" {
  description = "Map of AWS regions with their configurations"
  type = map(object({
    region = string
    ami_id = optional(string)
    instance_type = string
    subnet_cidr = optional(string)
    vpc_cidr = optional(string)
    public_subnet = optional(string)
  }))
}

variable "vultr_regions" {
  description = "Map of Vultr regions with their configurations"
  type = map(object({
    region        = string
    v4_subnet     = string
    v4_subnet_mask = number
  }))
}

variable "external_clients" {
  description = "List of non-Vultr/AWS Tailscale clients"
  type = list(object({
    name         = string
    region       = string
    public_ip    = string
    private_ip   = string
    subnet       = string
    subnet_mask  = number
    provider     = string
  }))
  default = []
}

variable "headscale_region" {
  description = "Vultr region code for the Headscale control server"
  type        = string
}
