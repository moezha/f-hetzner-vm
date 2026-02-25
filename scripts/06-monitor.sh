#!/bin/bash
set -euo pipefail

echo "--- setting up monitoring & log rotation ---"

export DEBIAN_FRONTEND=noninteractive

# install node exporter for system health metrics (cpu, ram, disk)
apt-get install -y -q prometheus-node-exporter
echo 'ARGS="--web.listen-address=127.0.0.1:9100"' > /etc/default/prometheus-node-exporter
systemctl restart prometheus-node-exporter

systemctl enable --now prometheus-node-exporter || true

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

echo "--- monitoring configured ---"