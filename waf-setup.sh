#!/bin/bash

set -euo pipefail

echo "======================================"
echo " NGINX SAFE WAF DEPLOYMENT TOOL"
echo "======================================"

# --------------------------------------
# CONFIG PATHS
# --------------------------------------
VHOST_DIR="/etc/nginx/sites-available"
MAP_FILE="/etc/nginx/conf.d/waf-bot-map.conf"
BACKUP_DIR="/etc/nginx/backup-waf"

mkdir -p "$BACKUP_DIR"

# --------------------------------------
# DOMAIN INPUT
# --------------------------------------
echo ""
echo "Choose mode:"
echo "1) Apply to ALL vhosts"
echo "2) Select specific vhosts"
read -p "Enter choice (1/2): " MODE

# --------------------------------------
# CREATE GLOBAL MAP (SAFE)
# --------------------------------------
echo "[INFO] Creating global WAF map..."

cat > "$MAP_FILE" << 'EOF'
map $http_user_agent $is_bad_bot {
    default 0;

    ~*(curl|wget|python|aiohttp|httpx|scrapy|axios|node-fetch|go-http-client|okhttp|libwww|perl|ruby|java) 1;
    ~*(bot|crawl|spider|scrape|semrush|SemrushBot||ahrefs|mj12bot|dotbot|majestic|serpstat|seokicks) 1;
    ~*(nikto|nmap|masscan|sqlmap|gobuster|wfuzz|burp|zap|acunetix|nessus|openvas) 1;
    ~*(headless|selenium|puppeteer|playwright|webdriver|lighthouse) 1;
    ~*(gptbot|chatgpt|openai|claude|anthropic|perplexity|bytespider|diffbot) 1;
}

map $request_uri $is_safe_path {
    default 0;

    ~*^/wp-cron\.php 1;
    ~*^/wp-json/ 1;
    ~*^/wp-admin/admin-ajax\.php 1;
    ~*^/wp-load\.php 1;

    ~*/feed/? 1;
    ~*/rss/? 1;
    ~*/atom/? 1;

    ~*meta\.json 1;
}

map "$is_bad_bot$is_safe_path" $block_request {
    default 0;
    "10" 1;
}
EOF

echo "[OK] Map file updated"

# --------------------------------------
# SELECT VHOSTS
# --------------------------------------
if [ "$MODE" == "1" ]; then
    VHOSTS=$(ls "$VHOST_DIR")
else
    echo ""
    echo "Available vhosts:"
    ls "$VHOST_DIR"
    echo ""
    read -p "Enter space-separated vhosts: " VHOSTS
fi

# --------------------------------------
# PROCESS EACH VHOST
# --------------------------------------
for VHOST_NAME in $VHOSTS; do

    VHOST_PATH="$VHOST_DIR/$VHOST_NAME"

    if [ ! -f "$VHOST_PATH" ]; then
        echo "[SKIP] Not found: $VHOST_PATH"
        continue
    fi

    echo ""
    echo "======================================"
    echo "[PROCESSING] $VHOST_NAME"
    echo "======================================"

    # --------------------------------------
    # BACKUP (CRITICAL SAFETY)
    # --------------------------------------
    BACKUP_FILE="$BACKUP_DIR/${VHOST_NAME}.$(date +%F-%H%M%S).bak"
    cp "$VHOST_PATH" "$BACKUP_FILE"

    echo "[OK] Backup created"

    # Skip if already installed
    if grep -q "WAF_BOT_BLOCK" "$VHOST_PATH"; then
        echo "[SKIP] Already has WAF"
        continue
    fi

    TMP_FILE=$(mktemp)

    # --------------------------------------
    # SAFE INSERTION LOGIC
    # --------------------------------------
    awk '
    BEGIN { inserted=0 }
    {
        print $0

        if ($0 ~ /location[[:space:]]/ && inserted==0) {
            print "    if ($http_user_agent ~* \"UptimeRobot|Pingdom|StatusCake\") { return 200; } "
            print "    # WAF_BOT_BLOCK"
            print "    if ($block_request = 1) { return 444; }"
            print "    if ($http_user_agent = \"\") { return 444; }"
            inserted=1
        }
    }

    END {
        if (inserted==0) {
            print "    if ($http_user_agent ~* \"UptimeRobot|Pingdom|StatusCake\") { return 200; } "
            print "    # WAF_BOT_BLOCK"
            print "    if ($block_request = 1) { return 444; }"
            print "    if ($http_user_agent = \"\") { return 444; }"
        }
    }
    ' "$VHOST_PATH" > "$TMP_FILE"

    # --------------------------------------
    # VALIDATE OUTPUT BEFORE APPLY
    # --------------------------------------
    if [ ! -s "$TMP_FILE" ]; then
        echo "[ERROR] Empty config generated. Aborting."
        rm -f "$TMP_FILE"
        continue
    fi

    cp "$TMP_FILE" "$VHOST_PATH"
    rm -f "$TMP_FILE"

done

# --------------------------------------
# FINAL VALIDATION
# --------------------------------------
echo ""
echo "[INFO] Testing Nginx configuration..."

if nginx -t; then
    echo "[OK] Nginx config valid"
    systemctl reload nginx
    echo "[SUCCESS] WAF deployed safely"
else
    echo "[ERROR] Nginx failed — rolling back..."

    for file in "$BACKUP_DIR"/*.bak; do
        [ -e "$file" ] || continue
        cp "$file" "$VHOST_DIR/$(basename "$file" | cut -d'.' -f1)"
    done

    systemctl reload nginx
    echo "[ROLLBACK COMPLETE]"
    exit 1
fi
