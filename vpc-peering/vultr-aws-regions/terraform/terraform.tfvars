# Vultr API Key
vultr_api_key = "YOUR_VULTR_API_KEY"

# AWS Access Keys
aws_access_key = "YOUR_AWS_ACCESS_KEY"
aws_secret_key = "YOUR_AWS_SECRET_KEY"

user_scheme  = "limited"

instance_plan    = "voc-c-2c-4gb-75s-amd"
instance_os_id   = 1743

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

aws_regions = {
  aws_1 = {
    region        = "eu-west-1"
    instance_type = "t3.micro"
    ami_id        = "ami-00f569d5adf6452bb"
    vpc_cidr      = "10.50.0.0/16"
    public_subnet = "10.50.1.0/24"

  }
  aws_2 = {
    region        = "us-west-1"
    instance_type = "t3.micro"
    ami_id        = "ami-0df6c351db809edbf"
    vpc_cidr      = "10.51.0.0/16"
    public_subnet = "10.51.1.0/24"
  }
}
