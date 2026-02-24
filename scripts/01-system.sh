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

# Check if the exact line already exists (Idempotent check)
if ! grep -qxF "127.0.1.1 $HOSTNAME" /etc/hosts; then
    echo "Updating 127.0.1.1 entry in hosts file..."
    
    # Use grep -v to safely filter out any old 127.0.1.1 lines to a temp file
    grep -v "^127\.0\.1\.1" /etc/hosts > /etc/hosts.tmp
    
    # Append the perfect new line
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts.tmp
    
    # Overwrite using cat to preserve the original file's inode and permissions
    cat /etc/hosts.tmp > /etc/hosts
    rm -f /etc/hosts.tmp
else
    echo "Hosts file is already perfectly configured."
fi

# --- 4. Timezone ---
echo "Setting timezone: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

echo "--- [System] Base Configuration Complete ---"