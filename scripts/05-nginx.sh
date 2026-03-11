#!/bin/bash
set -euo pipefail

# fallback vars if not defined in config.env
DOMAIN="${DOMAIN:-$HOSTNAME}"
LE_EMAIL="${LE_EMAIL:-}"

echo "--- configuring nginx & ssl ---"

# install web server, ssl tooling, and apache2-utils for htpasswd
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q nginx certbot python3-certbot-nginx apache2-utils

# create basic auth credentials
htpasswd -bc /etc/nginx/.htpasswd admin "$MONITOR_PASSWORD"

# nuke the default monolith config
rm -f /etc/nginx/sites-enabled/default

# modular site config
cat > /etc/nginx/sites-available/app.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /health {
        access_log off;
        default_type text/plain;
        return 200 'OK';
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /grafana/ {
       auth_basic "Monitoring";
       auth_basic_user_file /etc/nginx/.htpasswd;
       proxy_pass http://127.0.0.1:3000/;
       proxy_set_header Host \$host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /prometheus/ {
       auth_basic "Monitoring";
       auth_basic_user_file /etc/nginx/.htpasswd;
       proxy_pass http://127.0.0.1:9090/;
       proxy_set_header Host \$host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /cadvisor/ {
       auth_basic "Monitoring";
       auth_basic_user_file /etc/nginx/.htpasswd;
       proxy_pass http://127.0.0.1:8081/;
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
if [[ -n "$LE_EMAIL" && "$DOMAIN" != "localhost" && "$DOMAIN" != *.local ]]; then
    echo "requesting ssl cert for $DOMAIN..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$LE_EMAIL" --redirect
    
    # ensure automatic renewal timer is active
    systemctl enable --now certbot.timer
else
    echo "skipping let's encrypt (local domain or missing LE_EMAIL)."
fi

echo "--- nginx configured ---"