# Vultr API Key
vultr_api_key = "YOUR_VULTR_API_KEY"

# GCP Project ID and Service Account Credentials
gcp_project_id       = "YOUR_GCP_PROJECT_ID"
gcp_credentials_file = "path/to/service_account.json"

user_scheme = "limited"

instance_plan  = "voc-c-2c-4gb-75s-amd"
instance_os_id = 1743

headscale_region = "ams"

vultr_regions = {
  vultr_1 = {
    region         = "blr"
    v4_subnet      = "10.30.0.0"
    v4_subnet_mask = 24
  }
  vultr_2 = {
    region         = "fra"
    v4_subnet      = "10.31.0.0"
    v4_subnet_mask = 24
  }
}

gcp_regions = {
  gcp_1 = {
    region       = "us-west1"
    zone         = "us-west1-a"
    subnet_cidr  = "10.40.0.0/24"
    machine_type = "e2-micro"
  }
  gcp_2 = {
    region       = "europe-west1"
    zone         = "europe-west1-b"
    subnet_cidr  = "10.41.0.0/24"
    machine_type = "e2-micro"
  }
}
