#!/bin/bash

NGINX_PATH="/etc/nginx/sites-available"

for app_dir in "$NGINX_PATH"/*; do
    conf_file="/home/master/applications/$(basename $app_dir)/conf/server.apache"

    if [ -f "$conf_file" ]; then
        # Extract ServerName line
        server_line=$(grep -i "ServerName" "$conf_file")

        # Extract Server ID and App ID using regex for any prefix
        # Pattern: <prefix>-<serverID>-<appID>.cloudwaysapps.com
        if [[ $server_line =~ [a-zA-Z0-9_-]+-([0-9]+)-([0-9]+)\.cloudwaysapps\.com ]]; then
            server_id="${BASH_REMATCH[1]}"
            app_id="${BASH_REMATCH[2]}"
            echo "App Directory: $(basename $app_dir) | Server ID: $server_id | App ID: $app_id"
        else
            echo "App Directory: $(basename $app_dir) | ServerName pattern not matched"
        fi
    else
        echo "App Directory: $(basename $app_dir) | conf/server.apache not found"
    fi
done
