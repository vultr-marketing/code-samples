terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.27.1"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.3.2"
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

provider "openstack" {
  auth_url                      = var.ovh_auth_url
  token                         = var.ovh_token != "" ? var.ovh_token : null
  tenant_id                     = var.ovh_project_id != "" ? var.ovh_project_id : null
  application_credential_id     = var.ovh_token == "" ? var.ovh_application_credential_id : null
  application_credential_secret = var.ovh_token == "" ? var.ovh_application_credential_secret : null
}
