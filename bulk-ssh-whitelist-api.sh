#!/bin/bash
# =============================================================================
# Cloudways API - SSH/SFTP IP Whitelisting Script
#
# GET  https://api.cloudways.com/api/v2/security/whitelisted?server_id=X
# POST https://api.cloudways.com/api/v1/security/whitelisted
#
# GET response: { "data": { "ip_list": "[\"1.2.3.4\",\"5.6.7.8\"]", "policy": "allow_all" } }
# ip_list is a JSON-encoded STRING — must parse with jq twice
# POST replaces the entire list — always send existing IPs + new IP together
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Cloudways SSH/SFTP IP Whitelisting Script${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# ── Step 1: Credentials ──────────────────────────────────────────────────────
read -p "Enter client's Cloudways Email : " email
read -p "Enter client's API Key         : " api_key
echo ""

# ── Step 2: OAuth token ──────────────────────────────────────────────────────
echo -e "${YELLOW}[*] Obtaining access token...${NC}"

TOKEN_RESPONSE=$(curl --silent -X POST \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --header 'Accept: application/json' \
  -d "email=${email}&api_key=${api_key}" \
  'https://api.cloudways.com/api/v1/oauth/access_token')

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo -e "${RED}[!] Failed to get access token. Check credentials.${NC}"
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi
echo -e "${GREEN}[✓] Access token obtained.${NC}"
echo ""

# ── Step 3: Fetch servers ────────────────────────────────────────────────────
echo -e "${YELLOW}[*] Fetching server list...${NC}"

TEMP_JSON="/tmp/cw_servers_$$.json"
curl -s -X GET \
  --header 'Accept: application/json' \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  'https://api.cloudways.com/api/v2/server' > "$TEMP_JSON"

SERVER_COUNT=$(jq '.servers | length' "$TEMP_JSON" 2>/dev/null)

if [[ -z "$SERVER_COUNT" || "$SERVER_COUNT" == "null" || "$SERVER_COUNT" -eq 0 ]]; then
  echo -e "${RED}[!] No servers found or failed to fetch list.${NC}"
  cat "$TEMP_JSON"; rm -f "$TEMP_JSON"; exit 1
fi

echo -e "${GREEN}[✓] Found ${SERVER_COUNT} server(s):${NC}"
echo ""
printf "%-5s %-12s %-18s %-28s %-10s %-14s\n" "No." "Server ID" "Public IP" "Label" "Cloud" "Instance"
printf '%s\n' "$(printf '─%.0s' {1..92})"

SERVER_LIST=$(jq -r '.servers[] | [.id, .public_ip, .label, .cloud, .region, .instance_type] | @csv' "$TEMP_JSON")

INDEX=1
while IFS=',' read -r id public_ip label cloud region instance; do
  printf "%-5s %-12s %-18s %-28s %-10s %-14s\n" \
    "$INDEX" \
    "$(echo $id        | tr -d '"')" \
    "$(echo $public_ip | tr -d '"')" \
    "$(echo $label     | tr -d '"')" \
    "$(echo $cloud     | tr -d '"')" \
    "$(echo $instance  | tr -d '"')"
  INDEX=$((INDEX + 1))
done <<< "$SERVER_LIST"
echo ""

# ── Step 4: IP to whitelist ──────────────────────────────────────────────────
read -p "Enter IP address to whitelist (e.g. 203.0.113.10 or 1.2.3.0/24): " WHITELIST_IP
[[ -z "$WHITELIST_IP" ]] && echo -e "${RED}[!] No IP entered. Exiting.${NC}" && rm -f "$TEMP_JSON" && exit 1

echo ""
echo -e "${CYAN}Ready to whitelist [${WHITELIST_IP}] on ALL ${SERVER_COUNT} server(s).${NC}"
read -p "Proceed? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo -e "${YELLOW}[!] Aborted.${NC}"; rm -f "$TEMP_JSON"; exit 0
fi
echo ""

# ── Step 5: Loop — GET existing, merge, POST full list ───────────────────────
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

while IFS=',' read -r id public_ip label cloud region instance; do
  SERVER_ID=$(echo    "$id"        | tr -d '"')
  SERVER_LABEL=$(echo "$label"     | tr -d '"')
  SERVER_IP=$(echo    "$public_ip" | tr -d '"')

  echo -e "${YELLOW}[→] ${SERVER_LABEL} (ID: ${SERVER_ID} | IP: ${SERVER_IP})${NC}"

  # ── 5a. GET current whitelist via v2 ─────────────────────────────────────
  # Response: { "data": { "ip_list": "[\"1.2.3.4\"]", "policy": "allow_all" } }
  GET_RESPONSE=$(curl --silent -X GET \
    --header 'Accept: application/json' \
    --header "Authorization: Bearer $ACCESS_TOKEN" \
    "https://api.cloudways.com/api/v2/security/whitelisted?server_id=${SERVER_ID}")

  # ip_list is a JSON-encoded string — extract it then parse it as JSON
  IP_LIST_STR=$(echo "$GET_RESPONSE" | jq -r '.data.ip_list // "[]"')
  EXISTING_IPS=$(echo "$IP_LIST_STR" | jq -r '.[]?' 2>/dev/null)

  # Count non-blank entries
  if [[ -z "$(echo "$EXISTING_IPS" | tr -d '[:space:]')" ]]; then
    EXISTING_COUNT=0
  else
    EXISTING_COUNT=$(echo "$EXISTING_IPS" | grep -c '[^[:space:]]')
  fi

  echo -e "  ${CYAN}[i] Current whitelist: ${EXISTING_COUNT} IP(s)$([ $EXISTING_COUNT -gt 0 ] && echo " — $(echo "$EXISTING_IPS" | tr '\n' ' ')")${NC}"

  # ── 5b. Duplicate check ───────────────────────────────────────────────────
  if echo "$EXISTING_IPS" | grep -qxF "$WHITELIST_IP"; then
    echo -e "  ${CYAN}[i] Already whitelisted — skipping.${NC}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # ── 5c. Build ip[] POST params: all existing IPs + new IP ─────────────────
  IP_PARAMS=()
  while IFS= read -r existing_ip; do
    existing_ip="$(echo "$existing_ip" | tr -d '[:space:]')"
    [[ -z "$existing_ip" ]] && continue
    IP_PARAMS+=(-d "ip[]=${existing_ip}")
  done <<< "$EXISTING_IPS"
  IP_PARAMS+=(-d "ip[]=${WHITELIST_IP}")

  echo -e "  ${CYAN}[i] Posting merged list: $(echo "$EXISTING_IPS" | tr '\n' ' ')${WHITELIST_IP}${NC}"

  # ── 5d. POST merged list ──────────────────────────────────────────────────
  HTTP_RESPONSE=$(curl --silent -w "\n__HTTP_CODE__%{http_code}" -X POST \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --header 'Accept: application/json' \
    --header "Authorization: Bearer $ACCESS_TOKEN" \
    -d "server_id=${SERVER_ID}&tab=sftp&type=sftp&ipPolicy=allow_all" \
    "${IP_PARAMS[@]}" \
    'https://api.cloudways.com/api/v1/security/whitelisted')

  RESPONSE_BODY=$(echo "$HTTP_RESPONSE" | sed 's/__HTTP_CODE__[0-9]*$//')
  HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep -o '__HTTP_CODE__[0-9]*' | grep -o '[0-9]*')

  # Guard: non-JSON = HTML error page
  if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    echo -e "  ${RED}[✗] Non-JSON response (HTTP ${HTTP_CODE}):${NC}"
    echo "      $(echo "$RESPONSE_BODY" | sed 's/<[^>]*>//g' | tr -s ' \n' ' ' | cut -c1-200)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  # ── 5e. Verify by re-fetching the whitelist after POST ────────────────────
  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    HAS_ERROR=$(echo "$RESPONSE_BODY" | jq -r \
      'if type=="object" then (.error // .errors // .error_description // "") else "" end' 2>/dev/null)
    if [[ -z "$HAS_ERROR" ]]; then
      # Re-fetch to confirm the IP is actually there now
      VERIFY_RESPONSE=$(curl --silent -X GET \
        --header 'Accept: application/json' \
        --header "Authorization: Bearer $ACCESS_TOKEN" \
        "https://api.cloudways.com/api/v2/security/whitelisted?server_id=${SERVER_ID}")
      VERIFY_STR=$(echo "$VERIFY_RESPONSE" | jq -r '.data.ip_list // "[]"')
      VERIFY_IPS=$(echo "$VERIFY_STR" | jq -r '.[]?' 2>/dev/null)
      VERIFY_COUNT=$(echo "$VERIFY_IPS" | grep -c '[^[:space:]]' 2>/dev/null || echo 0)

      if echo "$VERIFY_IPS" | grep -qxF "$WHITELIST_IP"; then
        echo -e "  ${GREEN}[✓] Confirmed — whitelist now has ${VERIFY_COUNT} IP(s): $(echo "$VERIFY_IPS" | tr '\n' ' ')${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      else
        echo -e "  ${RED}[✗] POST succeeded but IP not found in re-fetch. Current list: $(echo "$VERIFY_IPS" | tr '\n' ' ')${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    else
      echo -e "  ${RED}[✗] API error: ${HAS_ERROR}${NC}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    MESSAGE=$(echo "$RESPONSE_BODY" | jq -r \
      '.message // .error // .error_description // "Unknown error"' 2>/dev/null)
    echo -e "  ${RED}[✗] Failed (HTTP ${HTTP_CODE}): ${MESSAGE}${NC}"
    echo -e "      Response: ${RESPONSE_BODY}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

done <<< "$SERVER_LIST"

# ── Step 6: Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Summary${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "  IP Whitelisted    : ${WHITELIST_IP}"
echo -e "  Total Servers     : ${SERVER_COUNT}"
echo -e "  ${GREEN}Succeeded         : ${SUCCESS_COUNT}${NC}"
[[ "$SKIP_COUNT" -gt 0 ]] && echo -e "  ${CYAN}Already present   : ${SKIP_COUNT}${NC}"
[[ "$FAIL_COUNT"  -gt 0 ]] && echo -e "  ${RED}Failed            : ${FAIL_COUNT}${NC}"
echo ""

rm -f "$TEMP_JSON"
