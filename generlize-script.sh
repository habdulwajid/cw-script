#!/bin/bash

# ===============================
# Cloudways Bulk Command Executor
# ===============================

# ---- Color and style setup ----
_bold=$(tput bold)
_underline=$(tput sgr 0 1)
_red=$(tput setaf 1)
_green=$(tput setaf 76)
_blue=$(tput setaf 38)
_reset=$(tput sgr0)

# ---- Output helpers ----
_success() { printf '%s✔ %s%s\n' "$_green" "$@" "$_reset"; }
_error()   { printf '%s✖ %s%s\n' "$_red" "$@" "$_reset"; }
_note()    { printf '%s%s%sNote:%s %s%s%s\n' "$_underline" "$_bold" "$_blue" "$_reset" "$_blue" "$@" "$_reset"; }

# ---- Read inputs ----
read -p "Enter customer email: " email
read -p "Enter Cloudways API key: " apikey
read -p "Enter SSH username [default: systeam]: " ssh_user
ssh_user=${ssh_user:-systeam}

# ---- Retrieve Access Token ----
_note "Requesting access token..."
accesstoken=$(curl -s -H "Accept: application/json" -H "Content-Type:application/json" \
  -X POST --data '{"email":"'$email'","api_key":"'$apikey'"}' \
  "https://api.cloudways.com/api/v1/oauth/access_token" | jq -r '.access_token')

if [[ -z "$accesstoken" || "$accesstoken" == "null" ]]; then
  _error "Failed to get access token. Please check your email/API key."
  exit 1
fi
_success "Access token retrieved."

# ---- Retrieve server labels and IPs ----
_note "Fetching list of servers..."
serverlist=$(curl -s -X GET \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $accesstoken" \
  "https://api.cloudways.com/api/v1/server" | jq -r '.servers[] | "\(.label)|\(.public_ip)"')

if [[ -z "$serverlist" ]]; then
  _error "No servers found or unable to retrieve IPs."
  exit 1
fi
_success "Server list fetched successfully."

# ---- Get command(s) to execute ----
_note "Enter the commands to execute on all servers (end with EOF):"
tmpfile=$(mktemp)
cat > "$tmpfile" <<'EOF'
# test script
ls -la 

EOF

# Ask user if they want to edit or replace commands
read -p "Do you want to edit the commands before execution? (y/n): " edit_choice
if [[ "$edit_choice" =~ ^[Yy]$ ]]; then
  ${EDITOR:-nano} "$tmpfile"
fi

# ---- Execute commands on all servers ----
_note "Executing commands on all servers..."
while read -r entry; do
  label=$(echo "$entry" | cut -d'|' -f1)
  ip=$(echo "$entry" | cut -d'|' -f2)

  echo "------------------------------------------------------------------"
  echo "Server Label     : $label"    "Server IP Address: $ip"
  echo "------------------------------------------------------------------"

  #ssh -p22 -o StrictHostKeyChecking=no "$ssh_user@$ip" "sudo bash -s" < "$tmpfile"
  timeout 15s ssh -p22 \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=8 \
  -o BatchMode=yes \
  -o ConnectionAttempts=1 \
  "$ssh_user@$ip" "sudo bash -s" < "$tmpfile"
  if [[ $? -eq 0 ]]; then
    _success "Commands executed successfully on $label ($ip)"
  else
    _error "Failed to run commands on $label ($ip)"
  fi
  echo "" # Add spacing between servers
done <<< "$serverlist"



# ================================
# WordPress Plugin Disable Add-on
# ================================

PLUGIN="wordfence"

echo "Scanning applications for active WordPress installations..."

# Loop through all app directories (Cloudways default location)
for app in /home/*; do
  if [[ -d "$app/public_html" ]]; then
    echo "--------------------------------------------------"
    echo "Checking app: $app"
    cd "$app/public_html" || continue

    # Check if WP-CLI exists
    if ! command -v wp &>/dev/null; then
      echo "WP-CLI not found on this server. Skipping..."
      continue
    fi

    # Verify it's a WordPress installation
    if wp core is-installed --quiet; then
      echo "WordPress detected. Checking plugin: $PLUGIN"

      # Check if plugin is active
      if wp plugin is-active "$PLUGIN" --quiet; then
        echo "Plugin '$PLUGIN' is ACTIVE. Disabling..."
        if wp plugin deactivate "$PLUGIN" --quiet; then
          echo "✔ Plugin '$PLUGIN' has been disabled successfully."
        else
          echo "✖ Failed to disable plugin '$PLUGIN'."
        fi
      else
        echo "Plugin '$PLUGIN' is not active. Skipping..."
      fi
    else
      echo "Not a WordPress application. Skipping..."
    fi

    echo ""
  fi
done

echo "Plugin scan & disable process completed."


rm -f "$tmpfile"
_success "All done!"
