#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/setup_$(date +%F_%H-%M).log"
exec > >(tee -i "$LOG_FILE") 2>&1

trap 'echo -e "\n[\e[31mFATAL\e[0m] Script failed on line $LINENO. See log: $LOG_FILE"; exit 1' ERR

log "--- Setup Started: $(date) ---"
log "Logs saved to: $LOG_FILE"

# Path to configuration
CONFIG_FILE="config.env"

# --- Helper Functions ---

log() {
    echo -e "[\e[32m$(date +'%H:%M:%S')\e[0m] $1"
}

error() {
    echo -e "[\e[31mERROR\e[0m] $1"
    exit 1
}

# --- Pre-flight Checks ---

# 1. Check if running as root
if [ "$EUID" -ne 0 ]; then
  error "Please run this script as root."
fi

# 2. Check for config file
if [ -f "$CONFIG_FILE" ]; then
    if [ "$(stat -c '%U' "$CONFIG_FILE")" != "root" ]; then
        error "Security Violation: $CONFIG_FILE must be owned by root."
    fi

    if [[ "$(stat -c '%A' "$CONFIG_FILE")" =~ ^....w.... ]] || [[ "$(stat -c '%A' "$CONFIG_FILE")" =~ ^.......w. ]]; then
         error "Security Violation: $CONFIG_FILE is writable by non-owner (Mode: $(stat -c '%a' "$CONFIG_FILE"))."
    fi

    source "$CONFIG_FILE"
else
    error "Configuration file $CONFIG_FILE not found."
fi

# 3. OS Version Guard
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        error "This script requires Ubuntu. Detected: $ID"
    fi
    if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
         log "WARNING: Tested on 22.04/24.04. Current: $VERSION_ID - Proceeding with caution."
    fi
else
    error "Cannot detect OS version."
fi

# --- Execution ---

log "Starting Setup for $HOSTNAME..."

# Function to run modular scripts
run_script() {
    local script_name=$1
    if [ -f "$script_name" ]; then
        log "Running module: $script_name"
        # Pass environment variables to the script
        bash "$script_name"
    else
        error "Script $script_name not found!"
    fi
}

run_script "scripts/01-system.sh"
run_script "scripts/02-security.sh"

log "Setup Complete!"