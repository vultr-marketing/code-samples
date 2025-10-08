#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..." >&2
  exec sudo REGION="${REGION:-onprem}" bash "$0" "$@"
fi

REGION="${REGION:-onprem}"

export DEBIAN_FRONTEND=noninteractive

wait_for_apt() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    echo "Waiting for other apt/dpkg processes to finish..."
    sleep 5
  done
}

wait_for_apt
apt-get update -y

wait_for_apt
apt-get install -y net-tools iperf3 wget curl gnupg lsb-release apt-transport-https ca-certificates jq ipcalc

systemctl enable --now iperf3 || true

if ! command -v tailscale >/dev/null 2>&1; then
  echo "Installing Tailscale..."
  wait_for_apt
  curl -fsSL https://tailscale.com/install.sh | sh || {
    echo "Retrying Tailscale installation..."
    sleep 10
    wait_for_apt
    curl -fsSL https://tailscale.com/install.sh | sh
  }
fi

if ! dpkg -s frr >/dev/null 2>&1; then
  echo "🦡 Installing FRR..."
  curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -sc) frr-stable" | tee /etc/apt/sources.list.d/frr.list
  wait_for_apt
  apt-get update -y
  wait_for_apt
  apt-get install -y frr frr-pythontools
fi

cat >/etc/sysctl.d/99-forwarding.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl --system >/dev/null 2>&1 || true

PRIVATE_INFO=$(ip -json addr show | jq -r '
  .[] | select(.addr_info != null) |
  . as $iface |
  .addr_info[] |
  select(.family == "inet") |
  select(.local | test("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)")) |
  "\(.local)/\(.prefixlen) \($iface.ifname)"' | head -1)

if [[ -n "$PRIVATE_INFO" ]]; then
  SUBNET_CIDR=$(awk '{print $1}' <<< "$PRIVATE_INFO")
  INTERFACE=$(awk '{print $2}' <<< "$PRIVATE_INFO")
else
  FALLBACK_INFO=$(ip -json addr show | jq -r '
    .[] | select(.addr_info != null and .ifname != "lo") |
    . as $iface |
    .addr_info[] |
    select(.family == "inet") |
    "\(.local)/\(.prefixlen) \($iface.ifname)"' | head -1)

  if [[ -n "$FALLBACK_INFO" ]]; then
    SUBNET_CIDR=$(awk '{print $1}' <<< "$FALLBACK_INFO")
    INTERFACE=$(awk '{print $2}' <<< "$FALLBACK_INFO")
  else
    echo "Could not detect any IPv4 interface with a valid address." >&2
    exit 1
  fi
fi

SUBNET=$(ipcalc -n "$SUBNET_CIDR" | awk '/Network:/ {print $2}')

echo "Detected interface: ${INTERFACE}"
echo "Detected subnet: ${SUBNET}"

sed -i 's/^zebra=.*/zebra=yes/' /etc/frr/daemons
sed -i 's/^ospfd=.*/ospfd=yes/' /etc/frr/daemons

cat >/etc/frr/frr.conf <<EOF
frr version 8.4
frr defaults traditional
hostname gateway-${REGION}
log syslog
interface ${INTERFACE}
 ip ospf area 0
router ospf
 network ${SUBNET} area 0
 redistribute kernel
 redistribute static
 redistribute connected metric 10 subnets
line vty
EOF

systemctl restart frr
systemctl enable frr

iptables -C INPUT -p ospf -j ACCEPT 2>/dev/null || iptables -A INPUT -p ospf -j ACCEPT
if command -v ufw >/dev/null 2>&1; then
  ufw allow 5201 || true
fi

cat >/usr/local/bin/set-ospf-rule.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
sleep 10
iptables -C INPUT -p ospf -j ACCEPT 2>/dev/null || iptables -A INPUT -p ospf -j ACCEPT
ip route show table 52 | while read -r ROUTE; do
  [[ -n "$ROUTE" ]] || continue
  ip route replace $ROUTE
done
EOS
chmod +x /usr/local/bin/set-ospf-rule.sh
(crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/set-ospf-rule.sh") | crontab -

echo
echo "Setup complete for region: ${REGION}"
echo "Detected Interface: ${INTERFACE}"
echo "Detected Subnet: ${SUBNET}"
echo
echo "Next, connect to Headscale and advertise your local subnet:"
echo "  sudo tailscale up --login-server http://<headscale_ip>:8080 --authkey <AUTHKEY> --accept-routes --advertise-routes ${SUBNET}"
echo
