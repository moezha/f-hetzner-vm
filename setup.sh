#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/setup_$(date +%F_%H-%M).log"
exec > >(tee -i "$LOG_FILE") 2>&1
log() { echo -e "[\e[32m$(date +'%H:%M:%S')\e[0m] $1"; }
error() { echo -e "[\e[31mERROR\e[0m] $1"; exit 1; }

trap 'echo -e "\n[\e[31mFATAL\e[0m] Script failed on line $LINENO. See log: $LOG_FILE"; exit 1' ERR

log "--- Setup Started: $(date) ---"
log "Logs saved to: $LOG_FILE"

ENV_FILE="config.env"
if [ -f "$ENV_FILE" ]; then
    log "Performing security check on $ENV_FILE..."
    
    # Extract file owner and permissions using stat
    ENV_OWNER=$(stat -c "%U" "$ENV_FILE")
    ENV_PERMS=$(stat -c "%a" "$ENV_FILE")

    # 1. Check Ownership
    if [ "$ENV_OWNER" != "root" ]; then
        error "SECURITY ALERT: $ENV_FILE is owned by '$ENV_OWNER', not 'root'. Run: sudo chown root:root $ENV_FILE"
    fi

    # 2. Check Permissions (Allow 600 read/write, or 400 read-only)
    if [[ "$ENV_PERMS" != "600" && "$ENV_PERMS" != "400" ]]; then
        error "SECURITY ALERT: $ENV_FILE permissions are too open ($ENV_PERMS). Run: sudo chmod 600 $ENV_FILE"
    fi

    log "Security checks passed. Loading configuration..."
    set -a
    source "$ENV_FILE"
    set +a
else
    log "No config.env file found. Relying on system environment variables."
fi

# --- Configuration Mapping ---
export HOSTNAME="${HOSTNAME:-}"
export TIMEZONE="${TIMEZONE:-}"
export DEPLOY_USER="${DEPLOY_USER:-}"
export DOMAIN="${DOMAIN:-}"
export LE_EMAIL="${LE_EMAIL:-}"
export MONITOR_PASSWORD="${MONITOR_PASSWORD:-}"

# Clean up "none" placeholders from GitHub
[[ "$DOMAIN" == "none" ]] && export DOMAIN=""
[[ "$LE_EMAIL" == "none" ]] && export LE_EMAIL=""

# --- Pre-flight Checks ---
# ... check root ...
# 2. Check for required variables
if [ -z "$HOSTNAME" ] || [ -z "$TIMEZONE" ] || [ -z "$DEPLOY_USER" ] || [ -z "$MONITOR_PASSWORD" ]; then
    error "Missing required environment variables (SERVER_HOSTNAME, TIMEZONE, or DEPLOY_USER, , or MONITOR_PASSWORD)."
fi

# 3. OS Version Guard
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        error "UNSUPPORTED OS: Detected '${ID:-unknown}'. This script is strictly for Ubuntu."
    fi
    case "$VERSION_ID" in
        "20.04"|"22.04"|"24.04")
            log "OS Check Passed: Ubuntu $VERSION_ID"
            ;;
        *)
            error "UNSUPPORTED VERSION: Ubuntu $VERSION_ID. Please use 20.04, 22.04, or 24.04."
            ;;
    esac
else
    error "CRITICAL: /etc/os-release not found. Cannot verify OS compatibility."
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