#!/bin/bash

set -euo pipefail

echo "======================================"
echo " NGINX SAFE WAF INSTALLER"
echo "======================================"

# --------------------------------------

# Ask domain

# --------------------------------------

read -p "Enter domain (e.g. example.com): " DOMAIN

VHOST="/etc/nginx/sites-available/$DOMAIN"
MAP_FILE="/etc/nginx/conf.d/waf-bot-map.conf"
BACKUP_DIR="/etc/nginx/backup-waf"

mkdir -p "$BACKUP_DIR"

if [ ! -f "$VHOST" ]; then
echo "[ERROR] Vhost not found: $VHOST"
exit 1
fi

echo "[INFO] Using: $VHOST"

# --------------------------------------

# BACKUP VHOST FIRST (CRITICAL SAFETY)

# --------------------------------------

BACKUP_FILE="$BACKUP_DIR/${DOMAIN}.$(date +%F-%H%M%S).bak"
cp "$VHOST" "$BACKUP_FILE"

echo "[OK] Backup created: $BACKUP_FILE"

# --------------------------------------

# CREATE MAP FILE (SAFE CLEAN VERSION)

# --------------------------------------

cat > "$MAP_FILE" << 'EOF'
map $http_user_agent $is_bad_bot {
default 0;

```
~*(curl|wget|python|aiohttp|httpx|scrapy|axios|node-fetch|go-http-client|okhttp|libwww|perl|ruby|java) 1;

~*(bot|crawl|spider|scrape|semrush|ahrefs|mj12bot|dotbot|majestic|serpstat|seokicks|linkdex|rogerbot) 1;

~*(nikto|nmap|masscan|sqlmap|zgrab|dirbuster|gobuster|wfuzz|fuzz|hydra|burp|zap|acunetix|nessus|openvas) 1;

~*(headless|phantomjs|selenium|puppeteer|playwright|webdriver|htmlunit|slimerjs|lighthouse) 1;

~*(gptbot|chatgpt|openai|claude|anthropic|cohere|ccbot|amazonbot|bytespider|diffbot|perplexity) 1;
```

}

map $request_uri $is_safe_path {
default 0;

```
~*^/wp-cron\.php 1;
~*^/wp-json/ 1;
~*^/wp-admin/admin-ajax\.php 1;
~*^/wp-load\.php 1;

~*/feed/? 1;
~*/rss/? 1;
~*/atom/? 1;

~*meta\.json 1;
```

}

map "$is_bad_bot$is_safe_path" $block_request {
default 0;
"10" 1;
}
EOF

echo "[OK] Map file written safely"

# --------------------------------------

# TEST NGINX BEFORE APPLYING

# --------------------------------------

echo "[INFO] Testing nginx config..."
if ! nginx -t; then
echo "[ERROR] Nginx test failed. Aborting."
exit 1
fi

echo "[OK] Nginx config valid"

# --------------------------------------

# SAFE INSERT INTO VHOST (NO FILE CORRUPTION)

# --------------------------------------

TMP_FILE=$(mktemp)

awk '
BEGIN { inserted=0 }
{
print $0

```
if ($0 ~ /location[[:space:]]*\// && inserted==0) {
    print "    # WAF_BOT_BLOCK"
    print "    if ($block_request = 1) { return 444; }"
    print "    if ($http_user_agent = \"\") { return 444; }"
    inserted=1
}
```

}
END {
if (inserted==0) {
print "    # WAF_BOT_BLOCK"
print "    if ($block_request = 1) { return 444; }"
print "    if ($http_user_agent = "") { return 444; }"
}
}
' "$VHOST" > "$TMP_FILE"

# --------------------------------------

# FINAL VALIDATION BEFORE REPLACE

# --------------------------------------

cp "$TMP_FILE" "$VHOST"

rm -f "$TMP_FILE"

echo "[INFO] Re-testing nginx after changes..."

if nginx -t; then
systemctl reload nginx
echo "[SUCCESS] WAF applied safely"
else
echo "[CRITICAL] Rollback triggered!"

```
cp "$BACKUP_FILE" "$VHOST"
systemctl reload nginx

echo "[ROLLBACK DONE] Original config restored"
exit 1
```

fi
