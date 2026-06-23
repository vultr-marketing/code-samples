terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "vultr" {
  api_key     = var.vultr_api_key
  rate_limit  = 100
  retry_limit = 3
}
