vultr_api_key = "Your Vultr API Key"
# Instance configuration
instance_plan = "voc-c-2c-4gb-75s-amd"
user_scheme   = "limited"

# Headscale instance configuration
headscale_region = "ams"

# Tailscale instances configuration
tailscale_instances = [
  {
    region      = "atl"
    subnet      = "10.2.1.0"
    subnet_mask = 24
  },
  {
    region      = "mel"
    subnet      = "10.2.2.0"
    subnet_mask = 24
  },
  {
    region      = "blr"
    subnet      = "10.2.3.0"
    subnet_mask = 24
  },
  {
    region      = "ewr"
    subnet      = "10.2.4.0"
    subnet_mask = 24
  },
  {
    region      = "ams"
    subnet      = "10.2.5.0"
    subnet_mask = 24
  }
]
