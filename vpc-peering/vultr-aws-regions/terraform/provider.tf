terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.27.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.13"
    }
    tls = {
      source  = "hashicorp/tls"
    }
    local = {
      source  = "hashicorp/local"
    }
    random = {
      source  = "hashicorp/random"
    }
    null = {
      source  = "hashicorp/null"
    }
  }
}

provider "vultr" {
  api_key = var.vultr_api_key
}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

