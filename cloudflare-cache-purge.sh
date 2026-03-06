#!/bin/bash

echo "Please get API details from client's Dashboard first"

read -p "Please enter client's Email: " email
read -p "Please enter client's API key: " api_key

customer_id=622917
purged=0

temp_json="/tmp/cloudways_$api_key.json"

echo "Getting Cloudways API token..."

get_token=$(curl -s -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  -d "email=$email&api_key=$api_key" \
  https://api.cloudways.com/api/v1/oauth/access_token | jq -r '.access_token')

if [ "$get_token" == "null" ] || [ -z "$get_token" ]; then
    echo "Failed to authenticate with Cloudways API"
    exit 1
fi

echo "Fetching servers and applications..."

curl -s -X GET \
-H "Authorization: Bearer $get_token" \
https://api.cloudways.com/api/v1/server > "$temp_json"

echo "---------------------------------"

jq -c '.servers[]' "$temp_json" | while read server; do

    server_id=$(echo "$server" | jq -r '.id')
    server_ip=$(echo "$server" | jq -r '.public_ip')
    server_label=$(echo "$server" | jq -r '.label')
    server_provider=$(echo "$server" | jq -r '.cloud')
    server_region=$(echo "$server" | jq -r '.region')
    server_specs=$(echo "$server" | jq -r '.instance_type')

    echo "Server: ID:$server_id IP:$server_ip Name:$server_label Provider:$server_provider-$server_region ($server_specs)"

    echo "$server" | jq -c '.apps[]' | while read app; do

        app_id=$(echo "$app" | jq -r '.id')
        app_user=$(echo "$app" | jq -r '.sys_user')
        app_label=$(echo "$app" | jq -r '.label')
        app_domain=$(echo "$app" | jq -r '.app_fqdn')
        app_cname=$(echo "$app" | jq -r '.cname')

        echo "  App: ID:$app_id User:$app_user Label:$app_label Domain:$app_domain"

        # Get Cloudflare DNS status
        cloudflare_dns=$(curl -s -X GET \
        -H "Authorization: Bearer $get_token" \
        "https://api.cloudways.com/api/v1/app/cloudflareCdn?server_id=$server_id&app_id=$app_id")

        dns_count=$(echo "$cloudflare_dns" | jq '.dns | length')

        if [ "$dns_count" -eq 0 ]; then
            echo "      Cloudflare not active"
        else

            echo "$cloudflare_dns" | jq -r '.dns[] | "      Hostname: \(.hostname) Status: \(.status) Bandwidth: \(.bandwidth)"'

            echo "      Triggering Cloudflare purge..."

            purge=$(curl -s -X POST \
            -H "Authorization: Bearer $get_token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "server_id=$server_id" \
            -d "app_id=$app_id" \
            -d "customer_id=$customer_id" \
            https://api.cloudways.com/api/v1/app/cloudflareCdn/purgeDomain)

            operation_id=$(echo "$purge" | jq -r '.operation_id')

            if [ "$operation_id" != "null" ]; then
                echo "      Purge successful (Operation ID: $operation_id)"
                purged=$((purged+1))
            else
                echo "      Purge failed"
                echo "      API Response: $purge"
            fi

            sleep 1
        fi

    done

done

echo "---------------------------------"
echo "Total Cloudflare domains purged: $purged"

rm -f "$temp_json"
