#!/bin/bash

# Script to upgrade IonCube Loader on Linux (x86_64)
# Run as root or with sudo

set -e  # Exit on error

# Variables
IONCUBE_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
DOWNLOAD_DIR="/tmp/ioncube_upgrade"
BACKUP_DIR="/usr/local/ioncube/backup_$(date +%Y%m%d_%H%M%S)"
INSTALL_DIR="/usr/local/ioncube"

echo "=== Step 1: Create working directories ==="
mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$BACKUP_DIR"

echo "=== Step 2: Download IonCube Loader ==="
wget -O "$DOWNLOAD_DIR/ioncube_loaders.tar.gz" "$IONCUBE_URL"

echo "=== Step 3: Extract the tar file ==="
tar -xzf "$DOWNLOAD_DIR/ioncube_loaders.tar.gz" -C "$DOWNLOAD_DIR"

echo "=== Step 4: Backup existing IonCube loaders ==="
cp -v "$INSTALL_DIR"/*.so "$BACKUP_DIR/"

echo "=== Step 5: Copy new IonCube loaders ==="
cp -v "$DOWNLOAD_DIR/ioncube"/*.so "$INSTALL_DIR/"

echo "=== Step 6: Detect active PHP version ==="
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_SERVICE="php${PHP_VERSION}-fpm"

echo "Detected PHP version: $PHP_VERSION"
echo "PHP-FPM service to restart: $PHP_SERVICE"

echo "=== Step 7: Restart PHP-FPM and Apache ==="
# Restart PHP-FPM
if systemctl list-units --full -all | grep -q "$PHP_SERVICE"; then
    echo "Restarting $PHP_SERVICE..."
    systemctl restart "$PHP_SERVICE"
else
    echo "Warning: $PHP_SERVICE service not found. Please restart PHP manually."
fi

# Restart Apache if installed
if systemctl list-units --full -all | grep -q apache2; then
    echo "Restarting Apache..."
    systemctl restart apache2
elif systemctl list-units --full -all | grep -q httpd; then
    echo "Restarting httpd..."
    systemctl restart httpd
fi

echo "=== Step 8: Cleanup ==="
rm -rf "$DOWNLOAD_DIR"

echo "=== IonCube Loader upgrade completed ==="
echo "Backup of old loaders saved at: $BACKUP_DIR"
