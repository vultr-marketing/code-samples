vultr_api_key = "YOUR_API_KEY"

headscale_region = "ams"
user_scheme   = "limited"
instance_plan = "voc-c-2c-4gb-75s-amd"

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
