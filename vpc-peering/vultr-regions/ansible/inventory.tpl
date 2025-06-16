---
all:
  children:
    headscale_servers:
      hosts:
        headscale:
          ansible_host: ${headscale_ip}
    tailscale_servers:
      hosts:
        %{ for region, info in tailscale_ips ~}
        ${region}:
          ansible_host: ${info.public_ip}
          region: ${region}
        %{ endfor ~} 