#!/bin/bash

echo "Plugin status: breeze"

nginx_vhost_dir="/etc/nginx/sites-available"

# Initialize counters
total_apps=0
active_count=0
inactive_count=0
not_installed_count=0
not_wp_count=0

# Read all root paths from Nginx vhosts
roots=($(grep -Po 'root\s+\K[^;]+' "$nginx_vhost_dir"/* | sort -u))

for root_path in "${roots[@]}"; do
    # Extract app directory (parent of public_html)
    app_dir=$(basename "$(dirname "$root_path")")
    app_root="/home/master/applications/$app_dir/public_html"

    # Skip if public_html does not exist
    if [ ! -d "$app_root" ]; then
        echo "$app_dir: SKIPPED (public_html not found at $app_root)"
        continue
    fi

    # Check if this is a WordPress installation
    if [ ! -f "$app_root/wp-config.php" ] || [ ! -d "$app_root/wp-admin" ] || [ ! -d "$app_root/wp-includes" ]; then
        echo "$app_dir: SKIPPED (not a WordPress install)"
        not_wp_count=$((not_wp_count + 1))
        continue
    fi

    total_apps=$((total_apps + 1))

    cd "$app_root" || { echo "$app_dir: ERROR (cannot cd)"; continue; }

    if timeout 60 wp plugin is-installed formvibes --allow-root >/dev/null 2>&1; then
        if timeout 60 wp plugin is-active formvibes --allow-root >/dev/null 2>&1; then
            status="ACTIVE"
            active_count=$((active_count + 1))
        else
            status="INACTIVE"
            inactive_count=$((inactive_count + 1))
        fi
    else
        status="NOT_INSTALLED"
        not_installed_count=$((not_installed_count + 1))
    fi

    echo "$app_dir: $status"
done

# Summary per host
echo
echo "Host Summary for $hostname:"
echo "---------------------------"
echo "Total apps checked (WP only): $total_apps"
echo "ACTIVE: $active_count"
echo "INACTIVE: $inactive_count"
echo "NOT_INSTALLED: $not_installed_count"
echo "Skipped (not WordPress): $not_wp_count"
