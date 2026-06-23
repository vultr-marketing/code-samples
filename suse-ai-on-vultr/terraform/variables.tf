variable "vultr_api_key" {
  description = "Vultr API key (set via TF_VAR_vultr_api_key or VULTR_API_KEY env)"
  type        = string
  sensitive   = true
}

variable "instance_label" {
  description = "Instance label / hostname"
  type        = string
  default     = "suse-ai"
}

variable "server_type" {
  description = "Server type to provision: \"bare-metal\" (vultr_bare_metal_server) or \"cloud\" (vultr_instance, Vultr Cloud GPU)"
  type        = string
  default     = "bare-metal"

  validation {
    condition     = contains(["bare-metal", "cloud"], var.server_type)
    error_message = "server_type must be either \"bare-metal\" or \"cloud\"."
  }
}

variable "region" {
  description = "Vultr region (e.g. ewr, lax, fra)"
  type        = string
  default     = "ewr"
}

variable "plan" {
  description = "Vultr plan ID — must support GPU for AI workloads. Use a vbm-* plan for server_type=bare-metal or a vcg-* plan for server_type=cloud"
  type        = string
  default     = "vbm-112c-2048gb-8-a100-gpu"
}

variable "os_id" {
  description = "Vultr OS ID. 2284 = Ubuntu 24.04 LTS x64"
  type        = number
  default     = 2284
}

variable "ssh_key_dir" {
  description = "Directory (relative to terraform/) where generated SSH keys are written"
  type        = string
  default     = ".ssh"
}

# No Vultr firewall groups on bare metal; manage via OS firewall in Ansible.

# --- SUSE credentials forwarded to Ansible inventory ---
variable "appco_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "appco_user_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "scc_reg_code" {
  type      = string
  sensitive = true
  default   = ""
}

variable "prime_artifacts_url" {
  type      = string
  sensitive = true
  default   = ""
}

variable "suse_observability_reg_code" {
  type      = string
  sensitive = true
  default   = ""
}

variable "hf_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "le_email" {
  description = "Email for Let's Encrypt registration"
  type        = string
  default     = ""
}

variable "deploy_observability" {
  type    = bool
  default = true
}

variable "deploy_gpu_operator" {
  type    = bool
  default = true
}

variable "deploy_vllm" {
  type    = bool
  default = true
}

variable "observability_profile" {
  type    = string
  default = "100-nonha"
}
