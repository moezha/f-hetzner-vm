#!/bin/bash
set -euo pipefail

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
else
    echo "Hostname is already correct."
fi

sed -i '/^127.0.1.1/d' /etc/hosts
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
echo "Hosts file updated."

# --- 4. Timezone ---
echo "Setting timezone: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

echo "--- [System] Base Configuration Complete ---"