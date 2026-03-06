#!/bin/bash
set -euo pipefail

echo "--- setting up monitoring & log rotation ---"

export DEBIAN_FRONTEND=noninteractive

# install node exporter on host
apt-get install -y -q prometheus-node-exporter

# node exporter config - bind to all interfaces
echo 'ARGS="--web.listen-address=0.0.0.0:9100"' > /etc/default/prometheus-node-exporter
systemctl restart prometheus-node-exporter
systemctl enable --now prometheus-node-exporter

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

# Setup Docker Compose for Monitoring stack
echo "Configuring monitoring services via Docker Compose..."
MONITOR_DIR="/opt/monitoring"
mkdir -p "$MONITOR_DIR"

# prometheus config
cat > "$MONITOR_DIR/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'node'
    static_configs:
      # Use host-gateway to reach node-exporter running on the host OS
      - targets: ['host.docker.internal:9100']
  - job_name: 'cadvisor'
    static_configs:
      # Reach cAdvisor directly via the internal Docker network
      - targets: ['cadvisor:8080']
EOF

# monitoring compose file with subpath routing
cat > "$MONITOR_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.external-url=/prometheus/'
      - '--web.route-prefix=/prometheus/'
    extra_hosts:
      - "host.docker.internal:host-gateway"
    ports:
      - "127.0.0.1:9090:9090"

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    command:
      - '--url_base_prefix=/cadvisor'
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "127.0.0.1:8081:8080"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s/grafana/
      - GF_SERVER_SERVE_FROM_SUB_PATH=true
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "127.0.0.1:3000:3000"

volumes:
  prometheus_data:
  grafana_data:
EOF

if id "${DEPLOY_USER:-}" &>/dev/null; then
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "$MONITOR_DIR"
fi

docker compose -f "$MONITOR_DIR/docker-compose.yml" up -d

echo "--- monitoring configured ---"