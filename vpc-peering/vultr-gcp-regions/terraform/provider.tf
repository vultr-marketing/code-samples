terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.27.1"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    tls = {
      source = "hashicorp/tls"
    }
    local = {
      source = "hashicorp/local"
    }
    random = {
      source = "hashicorp/random"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

provider "vultr" {
  api_key = var.vultr_api_key
}

provider "google" {
  project     = var.gcp_project_id
  credentials = file(var.gcp_credentials_file)
}
