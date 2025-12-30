#!/bin/bash
echo "Please get API details from client's Dashboard first"

# Prompt for API credentials
read -p "Please enter client's Email: " email
read -p "Please enter client's API key: " api_key

# Get Cloudways access token
get_token=$(curl --silent -X POST \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --header 'Accept: application/json' \
    -d "email=$email&api_key=$api_key" \
    'https://api.cloudways.com/api/v1/oauth/access_token' | jq -r '.access_token')

# Temporary file to store JSON
temp_json=/tmp/$api_key.json

# Fetch servers
curl -s -X GET -H "Authorization: Bearer $get_token" 'https://api.cloudways.com/api/v1/server' > $temp_json

echo "Below you can see servers and apps for client email: $email"
echo "---------------------------------"

# Loop through each server
cat $temp_json | jq -r '.servers[] | [.id, .public_ip, .label, .cloud, .region, .instance_type] | @csv' | while read i; do
    server_id=$(echo $i | cut -d "\"" -f 2)
    server_ip=$(echo $i | cut -d "\"" -f 4)
    server_label=$(echo $i | cut -d "\"" -f 6)
    server_provider=$(echo $i | cut -d "\"" -f 8)
    server_region=$(echo $i | cut -d "\"" -f 10)
    server_specs=$(echo $i | cut -d "\"" -f 12)

    echo "Server: ID: $server_id IP: $server_ip Name: $server_label Provider: $server_provider - $server_region ($server_specs)"

    # Loop through each app for this server
    cat $temp_json | jq -r '.servers[] | select(.id == "'$server_id'") | .apps[] | [.id, .sys_user, .label, .app_fqdn, .cname] | @csv' | while read app; do
        app_id=$(echo $app | cut -d "\"" -f 2)
        app_user=$(echo $app | cut -d "\"" -f 4)
        app_label=$(echo $app | cut -d "\"" -f 6)
        app_domain=$(echo $app | cut -d "\"" -f 8)
                app_cname=$(echo $app | cut -d "\"" -f 10)

        echo "  App: ID: $app_id User: $app_user Label: $app_label App-FQDN: $app_domain   Domain: $app_cname"

        # Fetch Cloudflare add-on details for this app
        cloudflare=$(curl -s -X GET -H "Authorization: Bearer $get_token" \
            "https://api.cloudways.com/api/v1/app/cloudflareCdn/appSetting?server_id=$server_id&app_id=$app_id")

        # Extract all relevant Cloudflare settings
        min_tls=$(echo $cloudflare | jq -r '.data.setting.min_tls_version')
        early_hints=$(echo $cloudflare | jq -r '.data.setting.early_hints')
        tls13=$(echo $cloudflare | jq -r '.data.setting.tls_1_3')

        mirage=$(echo $cloudflare | jq -r '.data.custom_metadata.mirage')
        polish=$(echo $cloudflare | jq -r '.data.custom_metadata.polish')
        webp=$(echo $cloudflare | jq -r '.data.custom_metadata.webp')
        minify_js=$(echo $cloudflare | jq -r '.data.custom_metadata.minify_js')
        minify_css=$(echo $cloudflare | jq -r '.data.custom_metadata.minify_css')
        minify_html=$(echo $cloudflare | jq -r '.data.custom_metadata.minify_html')
        scrapeshield=$(echo $cloudflare | jq -r '.data.custom_metadata.scrapeshield')
        caching=$(echo $cloudflare | jq -r '.data.custom_metadata.caching')
        edgecaching=$(echo $cloudflare | jq -r '.data.custom_metadata.edgecaching')
        ua_mode=$(echo $cloudflare | jq -r '.data.custom_metadata.ua_mode')

        echo "    Cloudflare Settings:"
        echo "      min_tls=$min_tls tls_1_3=$tls13 early_hints=$early_hints"
        echo "      mirage=$mirage polish=$polish webp=$webp"
        echo "      minify_js=$minify_js minify_css=$minify_css minify_html=$minify_html"
        echo "      scrapeshield=$scrapeshield caching=$caching edgecaching=$edgecaching ua_mode=$ua_mode"



        # --- New API: Smart Cache Purge (FPC) status ---
    fpc_status=$(curl -s -X GET -H "Authorization: Bearer $get_token" \
            "https://api.cloudways.com/api/v1/app/cloudflareCdn/checkFPCStatus?server_id=$server_id&app_id=$app_id")
            # Extract deployed status
            fpc_deployed=$(echo $fpc_status | jq -r '.data.deployed')        
            echo "Smart Cache Purge (FPC) Deployed: $fpc_deployed"


          # --- New endpoint: Cloudflare DNS status ---
    cloudflare_dns=$(curl -s -X GET -H "Authorization: Bearer $get_token" \
        "https://api.cloudways.com/api/v1/app/cloudflareCdn?server_id=$server_id&app_id=$app_id")

        dns_count=$(echo "$cloudflare_dns" | jq '.dns | length')
                if [ "$dns_count" -eq 0 ]; then
                echo "      Cloudflare DNS not active"
                else
                echo "$cloudflare_dns" | jq -r '.dns[] | "      Hostname: \(.hostname) Status: \(.status) Bandwidth: \(.bandwidth)"'
                fi

    done
done

echo "---------------------------------"
rm $temp_json
