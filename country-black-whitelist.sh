#!/bin/bash

# Step 0: Define new countries to block (space-separated)
NEW_COUNTRIES="US IE NL BE DE FR GB SG JP CA AU SE FI IN CH AT ES IT PL"

# Temporary file to store currently blocked countries
CURRENT_BLOCKED_FILE="current_blocked_countries.txt"

# Step 1: Fetch currently blocked countries
> "$CURRENT_BLOCKED_FILE"
offset=0
limit=25

echo "Fetching currently blocked countries..."

while true; do
    countries=$(imunify360-agent blacklist country list --limit $limit --offset $offset | grep -v "COMMENT  COUNTRY" | awk '{print $2}')
    if [[ -z "$countries" ]]; then
        break
    fi
    echo "$countries" >> "$CURRENT_BLOCKED_FILE"
    offset=$((offset + limit))
done

echo "Currently blocked countries:"
cat "$CURRENT_BLOCKED_FILE"

# Step 2: Delete currently blocked countries
echo "Deleting currently blocked countries..."
while read -r country; do
    if [[ -n "$country" ]]; then
        echo "Deleting $country from blacklist..."
        imunify360-agent blacklist country delete "$country"
    fi
done < "$CURRENT_BLOCKED_FILE"

# Step 3: Add new countries from variable
echo "Adding new countries to blacklist..."
for country in $NEW_COUNTRIES; do
    echo "Adding $country to blacklist..."
    imunify360-agent blacklist country add "$country"
done

echo "Blacklist update completed!"
