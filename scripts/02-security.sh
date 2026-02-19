#!/bin/bash
set -euo pipefail
CONFIG_FILE="config.env"
if [ -f "$CONFIG_FILE" ]; then
    if [ "$(stat -c '%U' "$CONFIG_FILE")" != "root" ]; then
        echo "Error: $CONFIG_FILE must be owned by root." >&2; exit 1
    fi
    if [[ "$(stat -c '%A' "$CONFIG_FILE")" =~ ^....w.... ]] || [[ "$(stat -c '%A' "$CONFIG_FILE")" =~ ^.......w. ]]; then
        echo "Error: $CONFIG_FILE is writable by non-owner." >&2; exit 1
    fi
    source "$CONFIG_FILE"
fi

echo "--- [Security] Hardening Process ---"

# --- 1. User Setup ---
if id "$DEPLOY_USER" &>/dev/null; then
    echo "User $DEPLOY_USER exists, skipping."
else
    echo "Creating deploy user: $DEPLOY_USER"
    useradd -m -s /bin/bash "$DEPLOY_USER"
    usermod -aG sudo "$DEPLOY_USER"
fi

# Allow sudo without password only for service management
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *, /usr/bin/systemctl reload *" > "/etc/sudoers.d/90-$DEPLOY_USER"
chmod 0440 "/etc/sudoers.d/90-$DEPLOY_USER"

# --- 2. SSH Keys ---
if [ -z "$SSH_PUB_KEY" ]; then
    echo "ERROR: SSH_PUB_KEY not found in config.env. Aborting to prevent lockout."
    exit 1
fi

USER_SSH_DIR="/home/$DEPLOY_USER/.ssh"
mkdir -p "$USER_SSH_DIR"

touch "$USER_SSH_DIR/authorized_keys"

if ! grep -qF "$SSH_PUB_KEY" "$USER_SSH_DIR/authorized_keys"; then
    echo "$SSH_PUB_KEY" >> "$USER_SSH_DIR/authorized_keys"
    echo "SSH Key added."
else
    echo "SSH Key already present."
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
echo "Installing Fail2ban..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y fail2ban

# Basic SSH jail config
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

systemctl restart fail2ban

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
update_ssh_conf "PasswordAuthentication" "no"
update_ssh_conf "PubkeyAuthentication" "yes"
update_ssh_conf "ChallengeResponseAuthentication" "no"
update_ssh_conf "UsePAM" "no"

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