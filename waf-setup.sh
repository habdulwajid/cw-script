#!/bin/bash

set -e

MAP_FILE="/etc/nginx/conf.d/waf-bot-map.conf"
SNIPPET="# WAF_BOT_BLOCK"

echo "----------------------------------------"
echo " NGINX WAF SETUP SCRIPT"
echo "----------------------------------------"

# Ask for domain / vhost file

read -p "Enter domain (e.g. southernindianapower.com): " DOMAIN

VHOST_FILE="/etc/nginx/sites-available/$DOMAIN"

if [ ! -f "$VHOST_FILE" ]; then
echo "❌ Vhost file not found: $VHOST_FILE"
exit 1
fi

echo "✔ Using vhost: $VHOST_FILE"

# ----------------------------------------

# Create / Update MAP FILE

# ----------------------------------------

echo "➡ Creating/updating map file..."

cat > "$MAP_FILE" << 'EOF'

# =====================================================

# GLOBAL WAF MAPS

# =====================================================

map $http_user_agent $is_bad_bot {
default 0;

```
~*(curl|wget|python|python-requests|python-urllib|aiohttp|httpx|scrapy|mechanize|axios|node-fetch|fetch|http-client|go-http-client|okhttp|libwww|lwp|perl|ruby|java|apache-httpclient) 1;

~*(bot|crawl|spider|scrape|semrush|ahrefs|mj12bot|dotbot|blexbot|majestic|serpstat|seokicks|linkdex|rogerbot|spbot|exabot|sistrix|dataforseo) 1;

~*(nikto|nmap|masscan|sqlmap|zgrab|dirbuster|gobuster|wfuzz|fuzz|hydra|burp|zap|acunetix|nessus|openvas|whatweb) 1;

~*(headless|phantomjs|selenium|puppeteer|playwright|webdriver|htmlunit|slimerjs|lighthouse) 1;

~*(gptbot|chatgpt|openai|claude|anthropic|cohere|ccbot|amazonbot|bytespider|diffbot|perplexity|google-extended) 1;
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

echo "✔ Map file updated: $MAP_FILE"

# ----------------------------------------

# Insert WAF block into vhost

# ----------------------------------------

if grep -q "$SNIPPET" "$VHOST_FILE"; then
echo "✔ WAF already exists in vhost, skipping insert"
else
echo "➡ Inserting WAF block into vhost..."

```
awk -v snippet="$SNIPPET" '
BEGIN { inserted=0 }
{
    if ($0 ~ /location[[:space:]]*\// && inserted==0) {
        print "    " snippet
        print "    if ($block_request = 1) { return 444; }"
        print "    if ($http_user_agent = \"\") { return 444; }"
        inserted=1
    }
    print
}
' "$VHOST_FILE" > "$VHOST_FILE.tmp" && mv "$VHOST_FILE.tmp" "$VHOST_FILE"

echo "✔ WAF block inserted"
```

fi

# ----------------------------------------

# Test & Reload Nginx

# ----------------------------------------

echo "➡ Testing Nginx config..."
if nginx -t; then
echo "✔ Nginx config OK"
echo "➡ Reloading Nginx..."
systemctl reload nginx
echo "✅ DONE"
else
echo "❌ Nginx config test failed. Rolling back not implemented."
exit 1
fi
