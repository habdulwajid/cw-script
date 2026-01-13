# Checking pipeline migration process
if ps aux | grep -q "[w]ordpress_importer_daemon"; then
  echo "✅ WordPress migration process is running."
  cd /home/master/applications/neyqdfhyte/public_html/import-logs || exit
  if [[ -f completed-sites.json ]]; then
    completed=$(jq 'keys | length' completed-sites.json 2>/dev/null)
    echo "📊 Result: $completed apps completed."
  else
    echo "⚠️ completed-sites.json file not found in import-logs directory."
  fi
else
  echo "⚠️ WordPress migration process is not running. Skipping..."
fi


#-------------------------------------------

# Bandwidth calculation. 
for A in $(ls /etc/nginx/sites-available/ | awk '!/^default/ {print $1}'); do
    echo "" > total.txt
    echo "------------------------------------------------------------"
    echo "Application: $A"
    echo "------------------------------------------------------------"

    if [[ -f "/home/master/applications/$A/conf/server.nginx" ]]; then
        awk 'NR==1 {print substr($NF, 1, length($NF)-1)}' "/home/master/applications/$A/conf/server.nginx"
    else
        echo "⚠️  No server.nginx file found for $A"
        continue
    fi

    for i in {30..0}; do
        zcat -f "/home/master/applications/$A/logs/"*_*.access.log* 2>/dev/null \
        | awk -v day="$(date --date="$i days ago" '+%d/%b/%Y')" \
          '$4 ~ day {sum += $10} END {print sum >> "total.txt" ; printf("%s %.3f %s\n", day, sum/1024/1024, "MB")}'
    done

    awk '{total +=$1} END {printf ("%s %.3f %s\n", "Total:", total/1024/1024/1024, "GB")}' total.txt
done


# Plugin deactivation

#!/bin/bash

NGINX_SITES="/etc/nginx/sites-available"
APP_BASE="/home/master/applications"
PLUGIN="salt-shaker"

echo "Scanning Nginx app configs..."

for site in "$NGINX_SITES"/*; do
    APP=$(basename "$site")
    APP_PATH="$APP_BASE/$APP/public_html"

    echo "-------------------------------------------------"
    echo "Detected app: $APP"
    echo "Full path: $APP_PATH"
    echo ""

    if [[ -d "$APP_PATH" ]]; then
        echo "✔ Valid application directory found."

        cd "$APP_PATH" || { echo "Failed to enter directory, skipping..."; continue; }

        echo "→ Listing plugins (safe mode)..."

#PLUGIN="salt-shaker"

echo "→ Checking plugin status for: $PLUGIN"

# Check if plugin exists in the site
PLUGIN_STATUS=$(wp --skip-plugins --skip-themes plugin list --allow-root --name=$PLUGIN --format=json 2>/dev/null)

if [[ -z "$PLUGIN_STATUS" || "$PLUGIN_STATUS" == "[]" ]]; then
    echo "✖ Plugin '$PLUGIN' not found — skipping..."
    continue
fi

# Extract 'status' from JSON
STATUS=$(echo "$PLUGIN_STATUS" | jq -r '.[0].status')

if [[ "$STATUS" == "active" ]]; then
    echo "⚠ '$PLUGIN' is active — deactivating..."
    if wp --skip-plugins --skip-themes plugin deactivate "$PLUGIN" --allow-root --quiet; then
        echo "✔ Successfully deactivated $PLUGIN"
    else
        echo "✖ Failed to deactivate $PLUGIN"
    fi
else
    echo "✔ '$PLUGIN' is already inactive — no action needed."
fi

echo ""
#        wp --skip-plugins --skip-themes plugin list --format=table  --allow-root | grep salt
        # Example for deactivation (uncomment if needed):
        # wp --skip-plugins --skip-themes plugin deactivate wordfence --quiet
    else
        echo "✖ Directory does not exist, skipping..."
    fi

    echo ""
done

echo "Done scanning."



# Whitelist Countires from imunify
#!/bin/bash

# List of country codes to remove from blacklist
COUNTRIES=(
CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR
GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE
)

for COUNTRY in "${COUNTRIES[@]}"; do
    echo "Removing $COUNTRY from blacklist..."

    # Run the delete command
    imunify360-agent blacklist country delete "$COUNTRY"

    # Check the exit status
    if [ $? -eq 0 ]; then
        echo "$COUNTRY successfully removed from blacklist."
    else
        echo "Failed to remove $COUNTRY. Skipping..."
    fi
done

echo "Blacklist removal completed for all countries."


# Removing selected bots from Nginx 

#!/bin/bash

FILE="/etc/nginx/additional_server_conf"
BOTS="Slurp|AppleNewsBot|Pinterestbot|DuckAssistBot|OAI-SearchBot"

echo "Checking for target bots in $FILE ..."

if grep -Eq "$BOTS" "$FILE"; then
    echo "Bots found. Updating Nginx config..."

    sudo sed -i -E "s/\\|($BOTS)//g" "$FILE"

    echo "Testing Nginx configuration..."
    if sudo nginx -t; then
        echo "Nginx config OK. Reloading..."
        sudo systemctl reload nginx

        echo "Nginx status:"
        sudo systemctl --no-pager status nginx
    else
        echo "❌ Nginx config test failed. Changes NOT applied."
        exit 1
    fi
else
    echo "No matching bots found. Skipping changes."
fi

echo "Done. You can proceed to the next server."


# Fetch COuntry black list form imuinify
#!/bin/bash

# File to store blocked countries
BLOCKED_FILE="blocked_countries.txt"

# Clean the file if it exists
> "$BLOCKED_FILE"

# Pagination variables
offset=0
limit=25

echo "Fetching all blocked countries..."

# Fetch all blocked countries
while true; do
    countries=$(imunify360-agent blacklist country list --limit $limit --offset $offset | grep -v "COMMENT  COUNTRY" | awk '{print $2}')
    if [[ -z "$countries" ]]; then
        break
    fi
    echo "$countries" >> "$BLOCKED_FILE"
    offset=$((offset + limit))
done

echo "All blocked countries saved in $BLOCKED_FILE"
echo "Countries to unblock:"

cat "$BLOCKED_FILE"

# Loop through the file and delete each country from blacklist
while read -r country; do
    if [[ -n "$country" ]]; then
        echo "Deleting $country from blacklist..."
        imunify360-agent blacklist country delete "$country"
    fi
done < "$BLOCKED_FILE"

echo "All countries removed from blacklist."

