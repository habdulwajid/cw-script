#!/bin/bash

# === Configuration ===
ipfile="$1"  # File containing list of IPs
user="systeam"
port=22
logfile="wp_audit_log_$(date +%F_%H-%M-%S).log"

# === Output Colors ===
_green="\e[32m"
_red="\e[31m"
_reset="\e[0m"

# === Logger Functions ===
_note() {
    echo -e "${_green}[+] $1${_reset}"
    echo "[+] $1" >> "$logfile"
}

_error() {
    echo -e "${_red}[-] $1${_reset}"
    echo "[-] $1" >> "$logfile"
}

# === Input Validation ===
if [[ ! -s $ipfile ]]; then
    _error "IP file not found or empty: $ipfile"
    exit 1
fi

# === Start Processing ===
while read -r ip; do
    [[ -z "$ip" ]] && continue
    _note "Connecting to: $ip"

    ssh -p $port -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$user@$ip" << 'EOF'
echo "✅ Connected to $(hostname)"

# === WordPress Health ===

if command -v wp &> /dev/null && wp core is-installed --allow-root; then
    echo -e "\n[WP Core Version]"
    wp core version --allow-root

    echo -e "\n [WP Checksum Validation]"
    wp core verify-checksums --allow-root

    echo -e "\n [Active Plugins]"
    wp plugin list --status=active --format=table --allow-root

    echo -e "\n  [Inactive Plugins with Updates]"
    wp plugin list --status=inactive --update=available --allow-root

    echo -e "\n [Installed Themes]"
    wp theme list --allow-root

    echo -e "\n [Themes with Updates]"
    wp theme list --update=available --allow-root

    echo -e "\n [Suspicious PHP Files in wp-content]"
    find wp-content/ -type f -name "*.php" -exec grep -i "base64_decode" {} \; -print | head -n 5

else
    echo -e "\n⚠️ WP-CLI not installed or WordPress not found in /var/www/html"
fi

echo -e "\n✅ Completed execution on $(hostname)"
EOF

    if [[ $? -ne 0 ]]; then
        _error "Failed to connect or execute on: $ip"
    else
        _note "Audit complete on: $ip"
    fi
done < "$ipfile"
