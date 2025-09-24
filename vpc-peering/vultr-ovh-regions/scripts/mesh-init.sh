#!/bin/bash
set -euo pipefail

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

# Detect OS type
OS=""
OS_LIKE=""
VERSION_ID=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_LIKE=$ID_LIKE
    VERSION_ID=$VERSION_ID
else
    echo "Unable to detect OS type. Exiting."
    exit 1
fi

install_packages() {
    if [[ "$OS" == "rhel" || "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS_LIKE" == *"rhel"* ]]; then
        # RHEL-based
        dnf makecache -y
        dnf install -y net-tools wget curl

        FRRVER="frr-stable"
        REPO_RPM=""
        if [[ "$VERSION_ID" == 8* ]]; then
            REPO_RPM="$FRRVER-repo-1-0.el8.noarch.rpm"
        elif [[ "$VERSION_ID" == 9* ]]; then
            REPO_RPM="$FRRVER-repo-1-0.el9.noarch.rpm"
        else
            echo "Version $VERSION_ID not recognized, defaulting to RHEL 9 repo"
            REPO_RPM="$FRRVER-repo-1-0.el9.noarch.rpm"
        fi

        curl -O "https://rpm.frrouting.org/repo/$REPO_RPM"
        dnf install -y "./$REPO_RPM"
        dnf install -y frr frr-pythontools

        # Disable SELinux enforcement temporarily (consider permanent config outside this script)
        setenforce 0 || true

        # Configure firewall if firewalld running
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-rich-rule='rule protocol value="89" accept'
            firewall-cmd --reload
        else
            echo "firewalld not running, skipping firewall configuration"
        fi

    else
        # Debian-based - Set non-interactive mode
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_MODE=a
        export NEEDRESTART_SUSPEND=1
        
        apt-get update -y
        apt-get install -y -qq net-tools wget curl gnupg lsb-release debconf-utils

        # Add FRR repository only if not added
        if ! grep -q "deb.frrouting.org" /etc/apt/sources.list.d/frr.list 2>/dev/null; then
            curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null
            echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -sc) frr-stable" | tee /etc/apt/sources.list.d/frr.list
        fi

        apt-get update -y
        # Pre-configure iptables-persistent to avoid prompts
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        apt-get install -y -qq frr frr-pythontools iptables-persistent

        # Add iptables rule immediately (check if exists first)
        if ! iptables -C INPUT -p ospf -j ACCEPT 2>/dev/null; then
            iptables -A INPUT -p ospf -j ACCEPT
        fi

        # Create script to ensure rule is applied on reboot
        cat << 'EOF' > /usr/local/bin/set-ospf-rule.sh
#!/bin/bash
if ! iptables -C INPUT -p ospf -j ACCEPT 2>/dev/null; then
    iptables -A INPUT -p ospf -j ACCEPT
fi
EOF
        chmod +x /usr/local/bin/set-ospf-rule.sh

        # Add cron @reboot if not present
        TMP_CRON=$(mktemp)
        crontab -l > "$TMP_CRON" 2>/dev/null || true
        if ! grep -q "@reboot /usr/local/bin/set-ospf-rule.sh" "$TMP_CRON"; then
            echo "@reboot /usr/local/bin/set-ospf-rule.sh" >> "$TMP_CRON"
            crontab "$TMP_CRON"
        fi
        rm -f "$TMP_CRON"
    fi
}

install_packages

# Detect interface and subnet dynamically
DEFAULT_IFACE=$(ip route | awk '/^default/{print $5; exit}')

# Prefer RFC1918 on-link subnet regardless of default interface
PRIVATE_SUBNET=$(ip -4 route | awk '/proto kernel/ && /scope link/ {print $1}' \
  | grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' | head -1)

if [[ -n "${PRIVATE_SUBNET:-}" ]]; then
  SUBNET="$PRIVATE_SUBNET"
  IF_LINE=$(ip -4 route show "$SUBNET" | head -1)
  if echo "$IF_LINE" | grep -q ' dev '; then
    DEFAULT_IFACE=$(echo "$IF_LINE" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
  fi
else
  SUBNET=$(ip -4 route | awk -v i="$DEFAULT_IFACE" '$0 !~ /default/ && $0 ~ i {print $1; exit}')
fi

if [[ -z "${DEFAULT_IFACE:-}" || -z "${SUBNET:-}" ]]; then
  echo "Failed to determine interface/subnet for OSPF" >&2
  exit 1
fi

# Enable FRR daemons
sed -i 's/^zebra=.*/zebra=yes/' /etc/frr/daemons
sed -i 's/^ospfd=.*/ospfd=yes/' /etc/frr/daemons

# Write FRR configuration
cat <<EOF > /etc/frr/frr.conf
frr version 8.4
frr defaults traditional
log syslog
log file /var/log/frr/frr.log debugging
hostname ${TS_HOSTNAME:-$(hostname)}
interface ${DEFAULT_IFACE}
 ip ospf area 0
router ospf
 network $SUBNET area 0
 redistribute kernel
 redistribute static
 redistribute connected metric 10 subnets
line vty
EOF

# Enable and start FRR
systemctl enable frr >/dev/null 2>&1 || true
systemctl restart frr || true

echo "All done. System upgraded and tools installed successfully."
