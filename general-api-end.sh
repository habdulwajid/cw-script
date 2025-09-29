#!/bin/bash
echo "Cloudways Generic API Fetch Script"

#usage ./cf-details.sh
#Enter Cloudways API endpoint (e.g., /app/cloudflareCdn/appSetting or /app/cloudflareCdn): /app/cloudflareCdn


# Prompt for API credentials
read -p "Enter client email: " email
read -p "Enter client API key: " api_key

# Get access token
get_token=$(curl --silent -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H 'Accept: application/json' \
    -d "email=$email&api_key=$api_key" \
    'https://api.cloudways.com/api/v1/oauth/access_token' | jq -r '.access_token')

if [ -z "$get_token" ] || [ "$get_token" == "null" ]; then
    echo "Failed to get access token"
    exit 1
fi

# Temp JSON file
temp_json=/tmp/$api_key.json

# Fetch all servers
curl -s -X GET -H "Authorization: Bearer $get_token" 'https://api.cloudways.com/api/v1/server' > $temp_json

# Prompt for API endpoint to query for each app
read -p "Enter Cloudways API endpoint (e.g., /app/cloudflareCdn/appSetting or /app/cloudflareCdn): " endpoint

echo "---------------------------------"
cat $temp_json | jq -r '.servers[] | [.id, .label] | @csv' | while read server; do
    server_id=$(echo $server | cut -d "\"" -f 2)
    server_label=$(echo $server | cut -d "\"" -f 4)
    echo "Server: $server_label (ID: $server_id)"

    # Loop through apps on this server
    cat $temp_json | jq -r '.servers[] | select(.id=="'$server_id'") | .apps[] | [.id, .label, .app_fqdn] | @csv' | while read app; do
        app_id=$(echo $app | cut -d "\"" -f 2)
        app_label=$(echo $app | cut -d "\"" -f 4)
        app_domain=$(echo $app | cut -d "\"" -f 6)

        echo "  App: $app_label (ID: $app_id) Domain: $app_domain"

        # Fetch API dynamically for this app
        response=$(curl -s -X GET -H "Authorization: Bearer $get_token" \
            "https://api.cloudways.com/api/v1$endpoint?server_id=$server_id&app_id=$app_id")

        # Pretty print JSON output for logging
        echo "$response" | jq .

        echo "---------------------------------"
    done
done

rm $temp_json
