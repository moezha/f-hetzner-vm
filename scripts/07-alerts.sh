#!/bin/bash
set -euo pipefail

# We'll use LE_EMAIL from our secrets as the recipient
ALERT_EMAIL="${LE_EMAIL:-none}"

echo "--- Configuring SSH Email Alerts ---"

# 1. Install mail utilities if not present
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q mailutils postfix

# 2. Create the notification script
cat > /usr/local/bin/ssh-login-notify.sh << 'EOF'
#!/bin/bash
set -euo pipefail
if [ "$PAM_TYPE" != "close_session" ]; then
    RECIPIENT_EMAIL=$(printenv ALERT_EMAIL)
    
    # Only send if an email is actually configured
    if [[ "$RECIPIENT_EMAIL" != "none" && -n "$RECIPIENT_EMAIL" ]]; then
        SUBJECT="SSH Login Alert: $PAM_USER on $(hostname)"
        MESSAGE="⚠️ SSH Login Detected
        ----------------        
        User: $PAM_USER
        IP:   $PAM_RHOST
        Host: $(hostname)
        Date: $(date)"

        echo "$MESSAGE" | mail -s "$SUBJECT" "$RECIPIENT_EMAIL"
    fi
fi
EOF

chmod +x /usr/local/bin/ssh-login-notify.sh

# 3. Register with PAM
if ! grep -q "/usr/local/bin/ssh-login-notify.sh" /etc/pam.d/sshd; then
    echo "--- Registering Notification Script with PAM ---"
    echo "session optional pam_exec.so /usr/local/bin/ssh-login-notify.sh" >> /etc/pam.d/sshd
else
    echo "--- PAM Registration already exists, skipping ---"
fi

echo "--- SSH Email Alerts Configured ---"