#!/bin/bash

# === Configuration ===
ipfile="$1"  # Input file with list of IPs
user="systeam"
port=22
logfile="script_log_$(date +%F_%H-%M-%S).log"

# === Colors for terminal output ===
_green="\e[32m"
_red="\e[31m"
_yellow="\e[33m"
_reset="\e[0m"

# === Logger functions ===
_log() {
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${_yellow}[*] [$timestamp] $1${_reset}"
}

_note() {
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${_green}[+] [$timestamp] $1${_reset}"
}

_error() {
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${_red}[-] [$timestamp] $1${_reset}"
}

# === Validate input ===
if [[ ! -s "$ipfile" ]]; then
    _error "IP file not found or is empty: $ipfile" | tee -a "$logfile"
    exit 1
fi

# === Main Loop ===
while read -r ip; do
    [[ -z "$ip" ]] && continue  # Skip blank lines

    _note "Connecting to: $ip" | tee -a "$logfile"

    # SSH into the server and execute commands
    ssh -T -p "$port" \
        -o ConnectTimeout=15 \
        -o LogLevel=ERROR \
        -o StrictHostKeyChecking=no \
        "$user@$ip" 'bash -s' << 'EOSCRIPT'
echo "==== BEGIN $(hostname) ===="
echo "✅ Connected as root to $(hostname)"
echo "Checking WordPress core files across apps..."

# === Loop through Nginx vhosts ===
for vhost in /etc/nginx/sites-available/*; do
    A=$(basename "$vhost")
    echo "--------------------"
    echo "Processing app: $A"

    pub="/home/master/applications/$A/public_html"

    # Extract application type directly from vhost file
    APP_TYPE=$(grep -iEo "proxy_set_header\s+X-Application\s+[a-zA-Z0-9_-]+" "$vhost" | awk '{print $3}' | head -n1)

    # Detect PHP version
    PHP_VERSION=$(php -v | grep -oP "^PHP \K[\d\.]+" 2>/dev/null)

    if [[ -n "$APP_TYPE" ]]; then
        echo "App: $A => Application Type: $APP_TYPE"
    else
        echo "⚠️ App: $A => Application Type: Not Found"
    fi

    if [[ -n "$PHP_VERSION" ]]; then
        echo "PHP version is: $PHP_VERSION"
    else
        echo "⚠️ PHP version: Not detected"
    fi

    if [[ -d "$pub" ]]; then
        echo "✅ Found public_html for $A"
        cd "$pub" || continue

        echo "👉 Listing WordPress plugins..."
        wp plugin list --skip-plugins --skip-themes --allow-root

        echo "👉 Listing WordPress themes..."
        wp theme list --skip-plugins --skip-themes --allow-root
    else
        echo "❌ Skipping $A — public_html directory missing"
    fi
done

echo "✅ Finished processing all apps on $(hostname)"
echo "==== END $(hostname) ===="
# === End of remote commands ===
EOSCRIPT

    # Log result locally
    if [[ $? -ne 0 ]]; then
        _error "Failed to connect or execute on: $ip" | tee -a "$logfile"
    else
        _note "Finished running on: $ip" | tee -a "$logfile"
    fi

done < "$ipfile" | tee -a "$logfile"
