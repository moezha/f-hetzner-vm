#!/bin/bash
set -euo pipefail

CONFIG_FILE="config.env"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# fallback vars if not defined in config.env
DOMAIN="${DOMAIN:-$HOSTNAME}"
LE_EMAIL="${LE_EMAIL:-}"

echo "--- configuring nginx & ssl ---"

# install web server and ssl tooling
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q nginx certbot python3-certbot-nginx

# nuke the default monolith config
rm -f /etc/nginx/sites-enabled/default

# modular site config
cat > /etc/nginx/sites-available/app.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;

    # health check endpoint (req 7)
    location /health {
        access_log off;
        default_type text/plain;
        return 200 'OK';
    }

    # proxy to local docker container (req 4)
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# enable site
ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/app.conf

# validate syntax and apply
nginx -t
systemctl restart nginx

# auto-ssl via certbot (req 5)
# skips issuance if no email is provided or if using a local/dummy domain
if [[ -n "$LE_EMAIL" && "$DOMAIN" =~ \.[a-z]+$ ]]; then
    echo "requesting ssl cert for $DOMAIN..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$LE_EMAIL" --redirect
    
    # ensure automatic renewal timer is active
    systemctl enable --