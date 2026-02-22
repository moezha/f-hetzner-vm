#!/bin/bash
set -euo pipefail

CONFIG_FILE="config.env"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

echo "--- deploying demo app ---"

APP_DIR="/opt/demo-app"
mkdir -p "$APP_DIR"

# write minimal compose file
cat > "$APP_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  web:
    image: hashicorp/http-echo:latest
    command: -text="demo app running successfully" -listen=:8080
    ports:
      # bind to localhost only; nginx will proxy external traffic
      - "127.0.0.1:8080:8080"
    restart: unless-stopped
EOF

# transfer ownership so CI/CD can deploy updates
if id "$DEPLOY_USER" &>/dev/null; then
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "$APP_DIR"
fi

# boot the container
cd "$APP_DIR"
docker compose up -d

echo "--- demo app deployed ---"