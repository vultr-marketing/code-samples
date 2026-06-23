output "instance_ip" {
  description = "Public IPv4 of the provisioned server"
  value       = local.instance_ip
}

output "instance_id" {
  value = local.instance_id
}

output "ssh_command" {
  value = "ssh -i ${local.ssh_private_key_path} root@${local.instance_ip}"
}

output "ssh_private_key_path" {
  value = abspath(local.ssh_private_key_path)
}

output "rancher_url" {
  value = "https://rancher-prime.${local.instance_ip}.sslip.io"
}

output "openwebui_url" {
  value = "https://webui.${local.instance_ip}.sslip.io"
}

output "observability_url" {
  value = "https://observability.${local.instance_ip}.sslip.io"
}
