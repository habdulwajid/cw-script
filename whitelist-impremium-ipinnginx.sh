#!/bin/bash

# Step 1: Ask user to enter IPs to whitelist
echo "Enter IP addresses to whitelist (space-separated):"
read -r -a whitelist_ips

# Step 2: Read server IPs from bin/ipslist
while IFS= read -r line; do
    serverips+=($(echo "$line" | awk '{print $1}'))
done < bin/ipslist

arraysize=${#serverips[@]}

# Step 3: Loop over servers
{
for (( i=0; i< arraysize; ++i)); do
    echo "==========================================================="
    echo "Whitelisting on server: ${serverips[$i]}"
    echo -e "\e[33m------------------------------------\e[0m"

    # Connect to remote server
    ssh -p22 -q -o StrictHostKeyChecking=no -t systeam@"${serverips[$i]}" "sudo -i bash -s" <<EOF

# Backup existing config
cp /etc/nginx/conf.d/ip_blocakge.conf /etc/nginx/conf.d/ip_blocakge.conf.bak_\$(date +%F_%T)

# Create the IP append block in a temp file
TMP_BLOCK="/tmp/ip_whitelist_block.txt"
> \$TMP_BLOCK

$(for ip in "${whitelist_ips[@]}"; do echo "echo '    $ip 1;   # BulkWhitelist' >> \$TMP_BLOCK"; done)
echo '    # BulkWhitelist' >> \$TMP_BLOCK

# Insert into config under the marker
awk '/#add IPs here/ {
    print;
    while ((getline line < "'"'"'\$TMP_BLOCK'"'"'") > 0) print line;
    next
} 1' /etc/nginx/conf.d/ip_blocakge.conf > /tmp/ip_blocakge.conf.tmp

# Replace original config
mv /tmp/ip_blocakge.conf.tmp /etc/nginx/conf.d/ip_blocakge.conf
rm -f \$TMP_BLOCK

# Validate and reload NGINX
nginx -t && systemctl restart nginx

EOF

    echo "Whitelisting complete on ${serverips[$i]}"
    echo "=============================================================="
done
} &> imperium-white-.log
