#!/bin/bash
set -euo pipefail

echo "--- [Security] Hardening Process ---"

# --- 1. User Setup ---
if id "$DEPLOY_USER" &>/dev/null; then
    echo "User $DEPLOY_USER exists, skipping."
else
    echo "Creating deploy user: $DEPLOY_USER"
    useradd -m -s /bin/bash "$DEPLOY_USER"
fi
# Remove from sudo group if they were previously added (for safety on existing VMs)
deluser "$DEPLOY_USER" sudo 2>/dev/null || true

# Grant granular, passwordless sudo access ONLY for required deployment commands
echo "Configuring strict sudoers rules for $DEPLOY_USER..."
SUDOERS_FILE="/etc/sudoers.d/90-${DEPLOY_USER}-deploy"

cat > "$SUDOERS_FILE" << EOF
# Strict deployment permissions for $DEPLOY_USER
$DEPLOY_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx, /bin/systemctl reload nginx
EOF

# Sudoers files MUST have strict permissions or sudo will break entirely
chmod 0440 "$SUDOERS_FILE"
# --- 2. SSH Keys ---
USER_SSH_DIR="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)/.ssh"
mkdir -p "$USER_SSH_DIR"
touch "$USER_SSH_DIR/authorized_keys"

KEYS_ADDED=false

if [ -n "${SSH_PUB_KEY:-}" ]; then
    echo "Injecting SSH key from environment variable..."
    # Strip Windows characters and store in a temporary variable
    CLEAN_KEY=$(echo "$SSH_PUB_KEY" | tr -d '\r')
    
    # Check if the exact key already exists in the file (idempotent check)
    if ! grep -qxF "$CLEAN_KEY" "$USER_SSH_DIR/authorized_keys"; then
        echo "$CLEAN_KEY" >> "$USER_SSH_DIR/authorized_keys"
    fi
    KEYS_ADDED=true
else
    echo "WARNING: SSH_PUB_KEY is empty or not set. No keys added to $DEPLOY_USER."
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
# Safely determine the current SSH port and allow it
CURRENT_SSH_PORT=$(sshd -T | grep -i '^port ' | awk '{print $2}')

if [ -n "$CURRENT_SSH_PORT" ]; then
    echo "Allowing SSH on detected port: $CURRENT_SSH_PORT"
    ufw allow "${CURRENT_SSH_PORT}/tcp"
else
    echo "WARNING: Could not detect SSH port. Falling back to port 22."
    ufw allow 22/tcp
fi

# Open other standard ports
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