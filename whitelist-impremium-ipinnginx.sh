#!/bin/bash

# 📌 CONFIGURABLE (via env vars or defaults)
SSH_USER="${SSH_USER:-systeam}"
SSH_PORT="${SSH_PORT:-22}"
LOG_FILE="imperium-white-$(date +%F_%H-%M-%S).log"

# Step 1: Ask user for IPs to whitelist
echo "Enter IP addresses to whitelist (space-separated):"
read -r -a whitelist_ips

# Step 2: Validate script argument (IP list file)
if [[ -z "$1" ]]; then
    echo "❌ Usage: $0 <server-ip-list-file>"
    exit 1
fi

ipfile="$1"
if [[ ! -f "$ipfile" ]]; then
    echo "❌ File not found: $ipfile"
    exit 1
fi

# Step 3: Read server IPs into array
serverips=()
while IFS= read -r line; do
    [[ -n "$line" ]] && serverips+=("$(echo "$line" | awk '{print $1}')")
done < "$ipfile"

arraysize=${#serverips[@]}
if [[ $arraysize -eq 0 ]]; then
    echo "❌ No valid server IPs found in file."
    exit 1
fi

# Step 4: Loop over each server
for (( i=0; i< arraysize; ++i )); do
    server="${serverips[$i]}"
    echo "===========================================================" | tee -a "$LOG_FILE"
    echo "Whitelisting on server: $server" | tee -a "$LOG_FILE"
    echo -e "\e[33m------------------------------------\e[0m" | tee -a "$LOG_FILE"

    # Test SSH connection
    if ! ssh -p"$SSH_PORT" -o ConnectTimeout=5 -q "$SSH_USER@$server" "exit"; then
        echo "❌ SSH connection failed to $server" | tee -a "$LOG_FILE"
        continue
    fi

    # Remote: backup config and prepare temp block file
    ssh -p"$SSH_PORT" -q "$SSH_USER@$server" "sudo -i bash -s" <<EOF
CONFIG_FILE="/etc/nginx/conf.d/ip_blocakge.conf"
BACKUP_FILE="\$CONFIG_FILE.bak_\$(date +%F_%T)"
cp "\$CONFIG_FILE" "\$BACKUP_FILE"
> /tmp/ip_whitelist_block.txt
EOF

    # Send whitelist IPs to remote
    for ip in "${whitelist_ips[@]}"; do
        if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "⚠️ Skipping invalid IP: $ip" | tee -a "$LOG_FILE"
            continue
        fi
        ssh -p"$SSH_PORT" -q "$SSH_USER@$server" \
        "echo '    $ip 1;   # BulkWhitelist' | sudo tee -a /tmp/ip_whitelist_block.txt > /dev/null"
    done

    # Final comment
    ssh -p"$SSH_PORT" -q "$SSH_USER@$server" \
    "echo '    # BulkWhitelist' | sudo tee -a /tmp/ip_whitelist_block.txt > /dev/null"

    # Remote: inject into config with validation and rollback
    ssh -p"$SSH_PORT" -q "$SSH_USER@$server" "sudo -i bash -s" <<'EOF'
CONFIG_FILE="/etc/nginx/conf.d/ip_blocakge.conf"
TMP_BLOCK="/tmp/ip_whitelist_block.txt"
TMP_CONF="/tmp/ip_blocakge.conf.tmp"
BACKUP_FILE="\${CONFIG_FILE}.bak_\$(date +%F_%T)"

# Validate input file
if [[ ! -s "$TMP_BLOCK" ]]; then
    echo "❌ Temp block file missing or empty. Skipping."
    exit 1
fi

# Ensure marker exists
if ! grep -q '#add IPs here' "$CONFIG_FILE"; then
    echo "❌ Marker '#add IPs here' not found in $CONFIG_FILE. Aborting."
    exit 1
fi

# Insert block under marker
awk -v blk="$TMP_BLOCK" '
/#add IPs here/ {
    print
    while ((getline line < blk) > 0) print line
    next
} 1' "$CONFIG_FILE" > "$TMP_CONF"

# Backup again and replace
cp "$CONFIG_FILE" "$BACKUP_FILE"
mv "$TMP_CONF" "$CONFIG_FILE"

# Validate and reload NGINX
if nginx -t; then
    systemctl restart nginx
    echo "✅ NGINX reloaded successfully."
else
    echo "❌ NGINX config error. Rolling back."
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    nginx -t && systemctl restart nginx
fi

rm -f "$TMP_BLOCK"
EOF

    echo "✅ Whitelisting complete on $server" | tee -a "$LOG_FILE"
    echo "===========================================================" | tee -a "$LOG_FILE"
done
