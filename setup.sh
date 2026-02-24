#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/setup_$(date +%F_%H-%M).log"
exec > >(tee -i "$LOG_FILE") 2>&1
log() { echo -e "[\e[32m$(date +'%H:%M:%S')\e[0m] $1"; }
error() { echo -e "[\e[31mERROR\e[0m] $1"; exit 1; }

trap 'echo -e "\n[\e[31mFATAL\e[0m] Script failed on line $LINENO. See log: $LOG_FILE"; exit 1' ERR

log "--- Setup Started: $(date) ---"
log "Logs saved to: $LOG_FILE"

if [ -f "config.env" ]; then
    log "Loading configuration from config.env file..."
    # set -a automatically exports all variables defined until set +a
    set -a
    source config.env
    set +a
else
    log "No .env file found. Relying on system environment variables."
fi

# --- Configuration Mapping ---
export HOSTNAME="${HOSTNAME:-}"
export TIMEZONE="${TIMEZONE:-}"
export DEPLOY_USER="${DEPLOY_USER:-}"
export DOMAIN="${DOMAIN:-}"
export LE_EMAIL="${LE_EMAIL:-}"

# Clean up "none" placeholders from GitHub
[[ "$DOMAIN" == "none" ]] && export DOMAIN=""
[[ "$LE_EMAIL" == "none" ]] && export LE_EMAIL=""

# --- Pre-flight Checks ---
# ... check root ...
# 2. Check for required variables
if [ -z "$HOSTNAME" ] || [ -z "$TIMEZONE" ] || [ -z "$DEPLOY_USER" ]; then
    error "Missing required environment variables (SERVER_HOSTNAME, TIMEZONE, or DEPLOY_USER)."
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
        # Source the script so it inherits config variables
        source "$script_name"
    else
        error "Script $script_name not found!"
    fi
}

run_script "scripts/01-system.sh"
run_script "scripts/02-security.sh"
run_script "scripts/03-docker.sh"
run_script "scripts/04-app.sh"
run_script "scripts/05-nginx.sh"
run_script "scripts/06-monitor.sh"
run_script "scripts/07-alerts.sh"

log "Setup Complete!"