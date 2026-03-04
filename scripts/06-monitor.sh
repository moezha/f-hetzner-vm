#!/bin/bash
set -euo pipefail

echo "--- setting up monitoring & log rotation ---"

export DEBIAN_FRONTEND=noninteractive

# install node exporter and local prometheus server
apt-get install -y -q prometheus-node-exporter prometheus

# node exporter config
echo 'ARGS="--web.listen-address=127.0.0.1:9100"' > /etc/default/prometheus-node-exporter
systemctl restart prometheus-node-exporter
systemctl enable --now prometheus-node-exporter

# prometheus config
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF

systemctl restart prometheus
systemctl enable --now prometheus

# force stricter log rotation for nginx to prevent disk bloat
# keeps 14 days of logs, compresses them, and signals nginx to reload
cat > /etc/logrotate.d/nginx << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}
EOF

# test logrotate config for syntax errors
logrotate -d /etc/logrotate.d/nginx >/dev/null 2>&1 || true

# Install Grafana 
echo "Installing Grafana..."
apt-get install -y -q apt-transport-https software-properties-common wget
mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list > /dev/null

apt-get update -q
apt-get install -y -q grafana
systemctl enable --now grafana-server

# Run cAdvisor for Docker metrics 
echo "Starting cAdvisor container for Docker monitoring..."

docker run \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker/:/var/lib/docker:ro \
  --volume=/dev/disk/:/dev/disk:ro \
  --publish=127.0.0.1:8081:8080 \
  --detach=true \
  --name=cadvisor \
  --restart=always \
  gcr.io/cadvisor/cadvisor:latest

# Update Prometheus to scrape cAdvisor 
echo "Adding cAdvisor to Prometheus scrape configs..."
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['localhost:8081']
EOF

systemctl restart prometheus

echo "--- monitoring configured ---"