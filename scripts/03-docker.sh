#!/bin/bash
set -euo pipefail

echo "--- setting up docker ---"

if ! command -v docker &> /dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "docker already installed. skipping."
fi

# enable on boot
systemctl enable --now docker

# grant deploy user access via sudoers
if id "$DEPLOY_USER" &>/dev/null; then
    echo "$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/docker compose -f /opt/demo-app/docker-compose.yml *" > "/etc/sudoers.d/90-${DEPLOY_USER}-deploy"
    chmod 0440 "/etc/sudoers.d/90-${DEPLOY_USER}-deploy"
fi

# set global log limits to prevent disk exhaustion
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker