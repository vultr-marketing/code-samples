terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.23.1"
    }
  }
}

provider "vultr" {
  api_key = var.vultr_api_key
}
