#!/bin/bash

# === Configuration ===
ipfile="$1"  # IP list file passed as first argument
user="systeam"
port=22
timestamp=$(date +%F_%H-%M-%S)
logfile="malware_cleanup_$timestamp.log"

# === Colors for output ===
_green="\e[32m"
_red="\e[31m"
_reset="\e[0m"

# === Logger functions ===
_note() {
    echo -e "${_green}[+] $1${_reset}" | tee -a "$logfile"
}

_error() {
    echo -e "${_red}[-] $1${_reset}" | tee -a "$logfile"
}

# === Check if IP list file exists ===
if [[ ! -s "$ipfile" ]]; then
    _error "IP file not found or empty: $ipfile"
    exit 1
fi

# === Main Loop ===
while read -r ip; do
    [[ -z "$ip" ]] && continue
    _note "Connecting to: $ip"

    ssh -p $port -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$user@$ip" 'bash -s' <<EOF | tee -a "$logfile" 2>&1

sudo bash <<'INNER'
echo "✅ Connected to \$(hostname)"
echo "---- Starting Malware Cleaner ----"
app_base="/home/master/applications"

cd "\$app_base" || exit 1

for app in \$(ls); do
    echo "--------------------"
    echo "Processing: \$app"
    site_path="\$app_base/\$app/public_html"

    if [[ -d "\$site_path" ]]; then
        cd "\$site_path" || continue

        echo "[+] Downloading WP core..."
        wp core download --force --version=\$(wp core version --allow-root) --allow-root || continue

        echo "[+] Verifying core checksums..."
        wp core verify-checksums --allow-root 2> stderr.txt
        if [[ -s stderr.txt ]]; then
            awk '{print \$6}' stderr.txt | while read -r file; do
                echo "Would remove suspicious file: \$file"
                # Uncomment to actually remove:
                # rm -f "\$file"
            done
            rm -f stderr.txt
        fi

        echo "[+] Refreshing salts..."
        curl -s https://api.wordpress.org/secret-key/1.1/salt > wp-salt.php
        sed -i '1s/^/<?php\\n/' wp-salt.php

 #       echo "[+] Moving suspicious plugins/themes (numeric)..."
#        find wp-content/{themes,plugins} -maxdepth 1 -regextype posix-extended -regex '.*/[^/]*[0-9][^/]*' -exec mv {} ../private_html/ \;
#
 #       echo "[+] Moving specific known plugins..."
  #      [[ -d wp-content/plugins/wp-file-manager ]] && mv wp-content/plugins/wp-file-manager ../private_html/
   #     [[ -d wp-content/plugins/PHP-Console_1.2-1 ]] && mv wp-content/plugins/PHP-Console_1.2-1 ../private_html/

        echo "[+] Resetting permissions..."
        chown "\$app":www-data -R *

        echo "[+] Plugin & Theme List:"
        wp plugin list --allow-root
        wp theme list --allow-root

#        echo "[+] private_html contents:"
#        ls -al ../private_html || echo "No private_html"
    fi
done

echo "---- Completed Malware Cleaner ----"
INNER
EOF

    if [[ $? -ne 0 ]]; then
        _error "Failed to complete tasks on $ip"
    else
        _note "Finished all tasks on $ip"
    fi
done < "$ipfile"
