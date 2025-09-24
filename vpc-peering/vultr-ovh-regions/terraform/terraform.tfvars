# Vultr
vultr_api_key = "YOUR_VULTR_API_KEY"

# OVH OpenStack
ovh_auth_url                      = "https://auth.cloud.ovh.net/v3"
ovh_project_id                    = "YOUR_OVH_PROJECT_ID"
ovh_application_credential_id     = "YOUR_APP_CRED_ID"
ovh_application_credential_secret = "YOUR_APP_CRED_SECRET"

user_scheme  = "limited"

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

ovh_regions = {
  ovh_1 = {
    region         = "GRA9"
    v4_subnet      = "10.40.0.0"
    v4_subnet_mask = 24
    flavor_name    = "d2-2"
  }
  ovh_2 = {
    region         = "UK1"
    v4_subnet      = "10.41.0.0"
    v4_subnet_mask = 24
    flavor_name    = "d2-2"
  }
}
