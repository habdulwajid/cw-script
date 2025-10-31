# Checking pipeline migration process
if ps aux | grep -q "[w]ordpress"; then
  echo "WordPress migration process is running:"
  ps aux | grep "[w]ordpress"
else
  echo "WordPress migration process is not running."
fi

#-------------------------------------------
