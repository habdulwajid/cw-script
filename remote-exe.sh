#!/bin/bash

# === Configuration ===
ipfile="$1"  # Input file with list of IPs
user="systeam"
port=22
logfile="script_log_$(date +%F_%H-%M-%S).log"

# === Colors for output ===
_green="\e[32m"
_red="\e[31m"
_reset="\e[0m"

# === Logger functions ===
_note() {
    echo -e "${_green}[+] $1${_reset}"
    echo "[+] $1" >> "$logfile"
}

_error() {
    echo -e "${_red}[-] $1${_reset}"
    echo "[-] $1" >> "$logfile"
}

# === Validate input ===
if [[ ! -s "$ipfile" ]]; then
    _error "IP file not found or is empty: $ipfile"
    exit 1
fi

# === Main Loop ===
while read -r ip; do
    [[ -z "$ip" ]] && continue  # Skip blank lines

    _note "Connecting to: $ip"

    ssh -T -p "$port" -o ConnectTimeout=10 -o LogLevel=ERROR -o StrictHostKeyChecking=no "$user@$ip" 'sudo bash -s' << 'EOSCRIPT'
echo "✅ Connected as root to $(hostname)"

# === Place your root-level remote commands below ===


# === End of commands ===
EOSCRIPT

    if [[ $? -ne 0 ]]; then
        _error "Failed to connect or execute on: $ip"
    else
        _note "Finished running on: $ip"
    fi

done < "$ipfile"
