# fetching the IP address location
tail -f ../logs/backend_wordpress-420229-5229277.cloudwaysapps.com.access.log | awk '{print $1}' | while read ip; do
    geo=$(curl -s ipinfo.io/$ip | jq -r '.country')
    echo "$ip -> $geo"
done
