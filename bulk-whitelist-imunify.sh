#!/bin/bash

# Usage: ./whitelist_ips.sh ip_list.txt

# Check if file path is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <ip_list_file>"
    exit 1
fi

IP_FILE="$1"

# Check if file exists
if [ ! -f "$IP_FILE" ]; then
    echo "Error: File '$IP_FILE' not found."
    exit 1
fi

# Loop through each IP in the file
while IFS= read -r ip; do
    # Skip empty lines or comments
    [[ -z "$ip" || "$ip" =~ ^# ]] && continue
    
    echo "➡️  Attempting to whitelist: $ip ..."
    
    # Run the whitelist command
    if imunify360-agent ip-list local add --purpose white "$ip" --comment "Uptime-Robot"; then
        echo "✅ Successfully whitelisted: $ip"
    else
        echo "❌ Failed to whitelist: $ip"
    fi
    
    # Wait 1 second before processing the next IP
    sleep 1
done < "$IP_FILE"

echo "🎯 All IPs processed."
