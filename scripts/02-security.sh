#!/bin/bash
set -euo pipefail

echo "--- [Security] Hardening Process ---"

# --- 1. User Setup ---
if id "$DEPLOY_USER" &>/dev/null; then
    echo "User $DEPLOY_USER exists, skipping."
else
    echo "Creating deploy user: $DEPLOY_USER"
    useradd -m -s /bin/bash "$DEPLOY_USER"
    usermod -aG sudo "$DEPLOY_USER"
fi

usermod -aG sudo "$DEPLOY_USER"

# --- 2. SSH Keys ---
USER_SSH_DIR="$(eval echo ~$DEPLOY_USER)/.ssh"
mkdir -p "$USER_SSH_DIR"
touch "$USER_SSH_DIR/authorized_keys"

KEYS_ADDED=false

if [ -s "keys.txt" ]; then
    echo "Injecting keys from GitHub Secrets..."
    cat keys.txt >> "$USER_SSH_DIR/authorized_keys"
    awk '!a[$0]++' "$USER_SSH_DIR/authorized_keys" > "$USER_SSH_DIR/authorized_keys.tmp"
    mv "$USER_SSH_DIR/authorized_keys.tmp" "$USER_SSH_DIR/authorized_keys"
    KEYS_ADDED=true
else
    echo "WARNING: keys.txt missing or empty. No keys added to $DEPLOY_USER."
fi

# Set perms
chmod 700 "$USER_SSH_DIR"
chmod 600 "$USER_SSH_DIR/authorized_keys"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$USER_SSH_DIR"

# --- 3. Firewall (UFW) ---
echo "Configuring UFW..."

ufw default deny incoming
ufw default allow outgoing

# Open standard ports
ufw allow ssh 
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable

# --- 4. Fail2ban ---
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q fail2ban
systemctl enable --now fail2ban

# --- 5. SSH Hardening ---
echo "Hardening sshd_config..."

SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

# Helper to swap or append config lines
update_ssh_conf() {
    local key=$1
    local val=$2
    if grep -q "^#\?${key}" "$SSHD_CONFIG"; then
        sed -i "s/^#\?${key}.*/${key} ${val}/" "$SSHD_CONFIG"
    else
        echo "${key} ${val}" >> "$SSHD_CONFIG"
    fi
}

# Apply lockdown rules
update_ssh_conf "PermitRootLogin" "no"
update_ssh_conf "PubkeyAuthentication" "yes"
update_ssh_conf "ChallengeResponseAuthentication" "no"
update_ssh_conf "UsePAM" "yes"

if [ "$KEYS_ADDED" = true ]; then
    update_ssh_conf "PasswordAuthentication" "no"
else
    echo "WARNING: No SSH keys added. Keeping PasswordAuthentication enabled to prevent lockout."
    update_ssh_conf "PasswordAuthentication" "yes"
fi

# Final syntax check before restart
if sshd -t; then
    systemctl restart ssh
    echo "SSH hardened successfully."
else
    echo "ERROR: Invalid SSH config detected. Reverting to backup."
    mv "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
    exit 1
fi

echo "--- [Security] Hardening Complete ---"