#!/bin/bash
set -e

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
    source "$CONFIG_FILE"
else
    error "Configuration file $CONFIG_FILE not found."
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