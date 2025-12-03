#!/bin/bash

# ===============================
# Node Exporter, Promtail & Shorewall Config Installer
# ===============================

# ---- User Inputs ----
read -p "Enter server name (e.g., harvestmoonca): " SERVER_NAME
read -p "Enter server IP/instance (e.g., 34.152.21.195): " INSTANCE

# ---- Variables ----
NODE_EXPORTER_VERSION="1.5.0"
PROMTAIL_VERSION="v2.7.2"
SHOREWALL_RULES_FILE="/etc/shorewall/rules"

# ---- Functions ----
function install_node_exporter() {
    echo "Installing Node Exporter..."

    sudo useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null

    curl -LO "https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz"
    tar xvfz "node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz"
    sudo mv "node_exporter-$NODE_EXPORTER_VERSION.linux-amd64/node_exporter" /usr/local/bin/
    sudo chmod +x /usr/local/bin/node_exporter

    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address="0.0.0.0:9100"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter

    echo "Node Exporter installed and running on port 9100."
}

function install_promtail() {
    echo "Installing Promtail..."

    sudo mkdir -p /etc/promtail /var/lib/promtail

    curl -LO "https://github.com/grafana/loki/releases/download/$PROMTAIL_VERSION/promtail-linux-amd64.zip"
    unzip promtail-linux-amd64.zip
    sudo mv promtail-linux-amd64 /usr/local/bin/promtail
    sudo chmod +x /usr/local/bin/promtail

    sudo useradd -rs /bin/false promtail 2>/dev/null
    sudo usermod -aG adm promtail

    # Full Promtail configuration with all scrape_configs
    sudo tee /etc/promtail/promtail-config.yml > /dev/null <<EOF
server:
  http_listen_port: 9080  # Unified instance running on port 9080
  grpc_listen_port: 0     # Disable gRPC if not needed
positions:
  filename: /var/lib/promtail/positions.yaml # Path for storing log positions
clients:
  - url: https://loki.breadstackcrm.com/loki/api/v1/push  # Loki server's URL

scrape_configs:
  #== System Logs ==#
  - job_name: system_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: system_logs
          server: $SERVER_NAME
          log_type: syslog
          __path__: /var/log/syslog
      - targets: [localhost]
        labels:
          job: system_logs
          server: $SERVER_NAME
          log_type: authlog
          __path__: /var/log/auth.log
      - targets: [localhost]
        labels:
          job: system_logs
          server: $SERVER_NAME
          log_type: kernlog
          __path__: /var/log/kern.log
  #== Apache Logs ==#
  - job_name: apache_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: apache_logs
          server: $SERVER_NAME
          log_type: access
          __path__: /var/log/apache2/access.log
      - targets: [localhost]
        labels:
          job: apache_logs
          server: $SERVER_NAME
          log_type: error
          __path__: /var/log/apache2/error.log
  #== Nginx Logs ==#
  - job_name: nginx_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx_logs
          server: $SERVER_NAME
          log_type: access
          __path__: /var/log/nginx/access.log
      - targets: [localhost]
        labels:
          job: nginx_logs
          server: $SERVER_NAME
          log_type: error
          __path__: /var/log/nginx/error.log
  #== MySQL Logs ==#
  - job_name: mysql_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: mysql_logs
          server: $SERVER_NAME
          log_type: error
          __path__: /var/log/mysql/error.log
      - targets: [localhost]
        labels:
          job: mysql_logs
          server: $SERVER_NAME
          log_type: slow_query
          __path__: /var/log/mysql/slow-query.log
  #== PHP Logs ==#
  - job_name: php_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: php_logs
          server: $SERVER_NAME
          log_type: fpm7.4
          __path__: /var/log/php7.4-fpm.log
      - targets: [localhost]
        labels:
          job: php_logs
          server: $SERVER_NAME
          log_type: fpm8.0
          __path__: /var/log/php8.0-fpm.log
      - targets: [localhost]
        labels:
          job: php_logs
          server: $SERVER_NAME
          log_type: fpm8.1
          __path__: /var/log/php8.1-fpm.log
      - targets: [localhost]
        labels:
          job: php_logs
          server: $SERVER_NAME
          log_type: fpm8.2
          __path__: /var/log/php8.2-fpm.log
  #== Redis Logs ==#
  - job_name: redis_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: redis_logs
          server: $SERVER_NAME
          log_type: redis
          __path__: /var/log/redis/redis-server.log
  #== Fail2Ban Logs ==#
  - job_name: fail2ban_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: fail2ban_logs
          server: $SERVER_NAME
          log_type: fail2ban
          __path__: /var/log/fail2ban.log
  #== Backup and Miscellaneous Logs ==#
  - job_name: backup_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: backup_logs
          server: $SERVER_NAME
          log_type: backup
          __path__: /var/log/backup.log
      - targets: [localhost]
        labels:
          job: backup_logs
          server: $SERVER_NAME
          log_type: backup_error
          __path__: /var/log/backup_error_dump
      - targets: [localhost]
        labels:
          job: backup_logs
          server: $SERVER_NAME
          log_type: cloudlinux_backup
          __path__: /var/log/cloudlinux-backup-utils*.log
  #== Application Logs ==#
  - job_name: application_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: app_logs
          server: $SERVER_NAME
          application: application_logs
          log_type: application
          __path__: /mnt/data/home/master/applications/*/logs/*.log
  #== Application Error Logs ==#
  - job_name: app_error_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: app_logs
          server: $SERVER_NAME
          log_type: error
          application: error_logs
          __path__: /mnt/data/home/master/applications/*/logs/*error*.log
  #== Application Access Logs ==#
  - job_name: app_access_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: app_logs
          server: $SERVER_NAME
          log_type: access
          application: access_logs
          __path__: /mnt/data/home/master/applications/*/logs/*access*.log
  #== Application Slow Logs ==#
  - job_name: app_slow_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: app_logs
          server: $SERVER_NAME
          log_type: slow
          application: slow_logs
          __path__: /mnt/data/home/master/applications/*/logs/*slow*.log
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable promtail
    sudo systemctl start promtail

    echo "Promtail installed and running on port 9080 with full config."
}


    sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit]
Description=Promtail service
After=network.target

[Service]
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable promtail
    sudo systemctl start promtail

    echo "Promtail installed and running on port 9080."


function configure_shorewall() {
    echo "Updating Shorewall rules..."

    # Check if ports already exist
    if ! grep -q "tcp\s\+9080" "$SHOREWALL_RULES_FILE"; then
        echo "ACCEPT          net       fw      tcp     9080   #Loki" | sudo tee -a "$SHOREWALL_RULES_FILE"
    fi

    if ! grep -q "tcp\s\+9100" "$SHOREWALL_RULES_FILE"; then
        echo "ACCEPT          net       fw      tcp     9100   #Node Exporter" | sudo tee -a "$SHOREWALL_RULES_FILE"
    fi

    echo "Shorewall rules updated. Reloading Shorewall..."
    sudo shorewall check
    sudo systemctl reload shorewall

    echo "Shorewall reloaded."
}

# ---- Run installations ----
install_node_exporter
install_promtail
configure_shorewall

# ---- Verification ----
echo "================ Verification ================"
systemctl status node_exporter --no-pager
systemctl status promtail --no-pager
systemctl status shorewall --no-pager
systemctl is-enabled node_exporter
systemctl is-enabled promtail
systemctl is-enabled shorewall
echo "Ports 9100 (Node Exporter) and 9080 (Promtail) should now be open and allowed by Shorewall."
echo "Ensure outbound HTTPS (443) is allowed to prometheus.breadstackcrm.com."
