# fetching the IP address location
tail -f ../logs/backend_wordpress-420229-5229277.cloudwaysapps.com.access.log | awk '{print $1}' | while read ip; do
    geo=$(curl -s ipinfo.io/$ip | jq -r '.country')
    echo "$ip -> $geo"
done


# tail the php-access logs and show the  cpu and memory usage in human readable. 
tail -f ../logs/php-app.access.log | awk '
{
  ip=$1
  time=$4
  gsub("\\[","",time)
  url=$7
  status=$9
  exec=$12
  mem=$13/1024/1024
  cpu=$14
  memp=$15

  printf "%-10s | %-15s | %-40s | %3s | %6ss | %6.1fMB | CPU:%6s | MEM:%6s\n",
         time, ip, url, status, exec, mem, cpu, memp
}'

# requests taking over 20MB
tail -f ../logs/php-app.access.log | awk '
{
  cpu=$14+0
  mem=$13/1024/1024

  if(cpu > 15 || mem > 20) {
    ip=$1
    time=$4
    gsub("\\[","",time)
    url=$7
    status=$9
    exec=$12

    printf "🔥 %s | %s | %s | %s | %.2fs | %.1fMB | CPU:%s | MEM:%s\n",
           time, ip, url, status, exec, mem, $14, $15
  }
}'


# Filtring the logs basedon specific time from all apps
#!/bin/bash

# Directory containing all apps
BASE_DIR="/home/master/applications"
# Pattern to filter logs (can be date/time like "23/Feb/2026:01:5")
PATTERN="$1"

if [ -z "$PATTERN" ]; then
    echo "Usage: $0 <pattern>"
    exit 1
fi

# Loop through each item in the base directory
for app in "$BASE_DIR"/*; do
    # Only process directories (skip symlinks)
    if [ -d "$app" ] && [ ! -L "$app" ]; then
        LOG_DIR="$app/logs"
        if [ -d "$LOG_DIR" ]; then
            echo "=== Logs from $(basename "$app") ==="
            # Find and read the log files matching pattern
            for log_file in "$LOG_DIR"/backend_wordpress*.cloudwaysapps.com.access.log; do
                # Only process if file exists
                if [ -f "$log_file" ]; then
                    grep "$PATTERN" "$log_file"
                fi
            done
            echo ""
        fi
    fi
done


