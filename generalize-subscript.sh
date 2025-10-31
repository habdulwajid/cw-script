# Checking pipeline migration process
if ps aux | grep -q "[w]ordpress"; then
  echo "WordPress migration process is running:"
  ps aux | grep "[w]ordpress"
else
  echo "WordPress migration process is not running."
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
