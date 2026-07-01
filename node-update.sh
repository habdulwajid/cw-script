#!/bin/bash

set -e

#=====================================================
# Node.js 22 Upgrade Utility
#=====================================================

NODE_VERSION="22.23.1"
NODE_PACKAGE="node-v${NODE_VERSION}-linux-x64"
NODE_TAR="${NODE_PACKAGE}.tar.gz"
NODE_URL="https://nodejs.org/dist/latest-v22.x/${NODE_TAR}"

DOWNLOAD_DIR="/var/cw/system/downloads"
BACKUP_DIR="/var/cw/system/backups/node"

clear

echo "=============================================="
echo "         Node.js Upgrade Utility"
echo "=============================================="
echo

echo "Current Installation"
echo "----------------------------------------------"

if command -v node >/dev/null 2>&1; then
    echo "Node Version : $(node -v)"
    echo "Node Binary  : $(which node)"
else
    echo "Node.js is not installed."
fi

echo

if command -v npm >/dev/null 2>&1; then
    echo "NPM Version  : $(npm -v)"
    echo "NPM Binary   : $(which npm)"
else
    echo "NPM is not installed."
fi

echo
echo "Node.js Version to Install : v${NODE_VERSION}"
echo

echo "Processes currently using Node:"
echo "----------------------------------------------"
lsof /usr/bin/node || true

echo
read -rp "Do you want to continue? (y/N): " CONFIRM

[[ "$CONFIRM" =~ ^[Yy]$ ]] || {
    echo
    echo "Operation cancelled."
    exit 0
}

mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${BACKUP_DIR}"

cd "${DOWNLOAD_DIR}"

echo
echo "Downloading Node.js..."

if [ ! -f "${NODE_TAR}" ]; then
    wget -O "${NODE_TAR}" "${NODE_URL}"
else
    echo "Archive already exists."
fi

echo
echo "Extracting package..."

if [ ! -d "${NODE_PACKAGE}" ]; then
    tar -xzf "${NODE_TAR}"
else
    echo "Extraction directory already exists."
fi

echo
echo "Creating backup..."

if [ -f /usr/bin/node ]; then
    BACKUP_FILE="${BACKUP_DIR}/node.$(date +%Y%m%d-%H%M%S)"
    cp -p /usr/bin/node "${BACKUP_FILE}"
    echo "Backup saved to:"
    echo "  ${BACKUP_FILE}"
fi

echo
echo "Installing Node.js..."

install -m 755 "${NODE_PACKAGE}/bin/node" /usr/bin/node.new
mv -f /usr/bin/node.new /usr/bin/node

echo
echo "----------------------------------------------"
echo "Installation Complete"
echo "----------------------------------------------"

echo "Node Version : $(node -v)"
echo "Node Binary  : $(which node)"

echo
echo "Downloaded Files:"
echo "  ${DOWNLOAD_DIR}/${NODE_PACKAGE}"

echo
echo "Backup Location:"
echo "  ${BACKUP_DIR}"

echo
echo "IMPORTANT:"
echo "Running Node.js processes (PM2, services, etc.)"
echo "will continue using the previous binary until"
echo "they are restarted."

echo
echo "Node.js update completed successfully."
