locals {
  ssh_key_dir          = "${path.module}/${var.ssh_key_dir}"
  ssh_private_key_path = "${local.ssh_key_dir}/${var.instance_label}_ed25519"
  ssh_public_key_path  = "${local.ssh_private_key_path}.pub"
}

resource "tls_private_key" "deploy" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "ssh_private_key" {
  filename        = local.ssh_private_key_path
  content         = tls_private_key.deploy.private_key_openssh
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  filename        = local.ssh_public_key_path
  content         = tls_private_key.deploy.public_key_openssh
  file_permission = "0644"
}

resource "vultr_ssh_key" "deploy" {
  name    = "${var.instance_label}-deploy"
  ssh_key = trimspace(tls_private_key.deploy.public_key_openssh)
}

resource "vultr_bare_metal_server" "suse_ai" {
  count = var.server_type == "bare-metal" ? 1 : 0

  label            = var.instance_label
  hostname         = var.instance_label
  region           = var.region
  plan             = var.plan
  os_id            = var.os_id
  ssh_key_ids      = [vultr_ssh_key.deploy.id]
  enable_ipv6      = false
  activation_email = false
  tags             = ["suse-ai", "rke2", "managed-by-terraform"]
}

resource "vultr_instance" "suse_ai" {
  count = var.server_type == "cloud" ? 1 : 0

  label            = var.instance_label
  hostname         = var.instance_label
  region           = var.region
  plan             = var.plan
  os_id            = var.os_id
  ssh_key_ids      = [vultr_ssh_key.deploy.id]
  enable_ipv6      = false
  activation_email = false
  tags             = ["suse-ai", "rke2", "managed-by-terraform"]
}

locals {
  instance_ip = var.server_type == "bare-metal" ? vultr_bare_metal_server.suse_ai[0].main_ip : vultr_instance.suse_ai[0].main_ip
  instance_id = var.server_type == "bare-metal" ? vultr_bare_metal_server.suse_ai[0].id : vultr_instance.suse_ai[0].id
}

# Render Ansible inventory with discovered IP + secrets passed through as vars.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0600"
  content = templatefile("${path.module}/templates/hosts.ini.tpl", {
    instance_ip                 = local.instance_ip
    ssh_private_key_path        = abspath(local.ssh_private_key_path)
    appco_username              = var.appco_username
    appco_user_token            = var.appco_user_token
    scc_reg_code                = var.scc_reg_code
    prime_artifacts_url         = var.prime_artifacts_url
    suse_observability_reg_code = var.suse_observability_reg_code
    hf_token                    = var.hf_token
    le_email                    = var.le_email
    deploy_observability        = var.deploy_observability
    deploy_gpu_operator         = var.deploy_gpu_operator
    deploy_vllm                 = var.deploy_vllm
    observability_profile       = var.observability_profile
  })
}
