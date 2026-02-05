#!/bin/bash

# ============================
# Configuration
# ============================
NGINX_SITES="/etc/nginx/sites-available"
APPS_BASE="/home/master/applications"
LOGFILE="/var/log/wp_admin_cleanup_$(date +%F_%H-%M-%S).log"

# The email of the user to keep
TARGET_USER_EMAIL="abdul.wajid@cloudways.com"

WP_CLI_FLAGS="--skip-plugins --skip-themes --allow-root"

# Redirect stdout/stderr to logfile
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo " WordPress Admin Cleanup Script Started "
echo " Date: $(date)"
echo "========================================"

# ============================
# Loop through Nginx apps
# ============================
for A in $(ls "$NGINX_SITES"); do
    APP_PATH="$APPS_BASE/$A/public_html"

    echo
    echo "----------------------------------------"
    echo "Processing application: $A"
    echo "Path: $APP_PATH"
    echo "----------------------------------------"

    # Validate WordPress
    if [ ! -f "$APP_PATH/wp-config.php" ]; then
        echo "❌ Not a WordPress site. Skipping."
        continue
    fi

    cd "$APP_PATH" || { echo "❌ Failed to access directory. Skipping."; continue; }

    # Check WP-CLI access
    if ! wp core is-installed $WP_CLI_FLAGS >/dev/null 2>&1; then
        echo "❌ WP-CLI failed. No changes made."
        continue
    fi

    echo "✅ WordPress detected."

    # Fetch target user ID from email
    TARGET_USER_ID=$(wp user get "$TARGET_USER_EMAIL" --field=ID $WP_CLI_FLAGS 2>/dev/null)
    if [ -z "$TARGET_USER_ID" ]; then
        echo "❌ Target user $TARGET_USER_EMAIL not found. Skipping deletion."
        continue
    fi
    echo "🎯 Target user ID for email $TARGET_USER_EMAIL: $TARGET_USER_ID"

    # Fetch all admin users with ID and email
    ADMIN_USERS=$(wp user list --role=administrator --fields=ID,user_email --format=csv $WP_CLI_FLAGS 2>/dev/null)
    if [ -z "$ADMIN_USERS" ]; then
        echo "ℹ️ No admin users found."
        continue
    fi

    echo "📋 Admin Users (ID | Email) found:"
    echo "$ADMIN_USERS"

    # Delete other admins and reassign content
    echo "$ADMIN_USERS" | tail -n +2 | while IFS=, read -r USER_ID USER_EMAIL; do
        if [ "$USER_EMAIL" == "$TARGET_USER_EMAIL" ]; then
            echo "⏭ Skipping target admin user $USER_EMAIL (ID $USER_ID)"
            continue
        fi

        echo "🗑 Deleting admin user $USER_EMAIL (ID $USER_ID) and reassigning content to $TARGET_USER_EMAIL"

        if wp user delete "$USER_ID" --reassign="$TARGET_USER_ID" --yes $WP_CLI_FLAGS; then
            echo "✅ User $USER_EMAIL (ID $USER_ID) deleted successfully."
        else
            echo "❌ Failed to delete user $USER_EMAIL (ID $USER_ID). Skipping further actions for safety."
            break
        fi
    done

    echo "✔ Completed processing for $A"
done

echo
echo "========================================"
echo " Script completed at $(date)"
echo " Logs saved to: $LOGFILE"
echo "========================================"
