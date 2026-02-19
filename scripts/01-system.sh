#!/bin/bash
set -euo pipefail
# grab local vars for testing
[ -f config.env ] && source config.env

echo "--- [System] Starting Base Configuration ---"

# --- 1. System Update ---
echo "Updating package lists and upgrading system..."

# non-interactive to prevent script hanging on prompts
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

# --- 2. Dependencies ---
echo "Installing essential tools..."
apt-get install -y -q \
    curl \
    git \
    htop \
    unzip \
    software-properties-common \
    ca-certificates \
    gnupg

# --- 3. Hostname ---
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "$HOSTNAME" ]; then
    echo "Updating hostname to $HOSTNAME..."
    hostnamectl set-hostname "$HOSTNAME"
    
    # fix /etc/hosts to avoid sudo resolution lag
    sed -i "s/127.0.0.1 localhost/127.0.0.1 localhost $HOSTNAME/" /etc/hosts
else
    echo "Hostname is already correct."
fi

# --- 4. Timezone ---
echo "Setting timezone: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

echo "--- [System] Base Configuration Complete ---"