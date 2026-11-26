#!/usr/bin/env bash
# Install the standby Prometheus/Alertmanager pair on h2.
#
#   DIST=/tmp/opencode/dist bash scripts/monitoring/install_prometheus_standby.sh
#
# h1 (primary) : prometheus 9090, alertmanager 9093 (cluster peer h2)
# h2 (standby) : prometheus 9090, alertmanager 9093 (cluster peer h1),
#                alert_webhook 9500, prom_proxy 9099 (stable query endpoint)
#
# Both Alertmanagers gossip on 9094 and deduplicate notifications.  Prometheus
# instances scrape independently; use scripts/monitoring/failover.sh to switch
# the LAN NAT endpoint between h1 and h2.
set -euo pipefail

DIST="${DIST:-/tmp/opencode/dist}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MON="$ROOT/scripts/monitoring"
H2=bigtop_hostname2

for f in "$DIST/prometheus/prometheus" "$DIST/alertmanager/alertmanager"; do
  [ -f "$f" ] || { echo "missing binary: $f" >&2; exit 1; }
done
for f in "$MON/prometheus-standby.yml" "$MON/rules.yml" "$MON/alertmanager-standby.yml" \
         "$MON/alert_webhook.py" "$MON/prom_proxy.py"; do
  [ -f "$f" ] || { echo "missing config: $f" >&2; exit 1; }
done

echo "== binaries =="
docker cp "$DIST/prometheus/prometheus" "$H2:/usr/local/bin/prometheus"
docker cp "$DIST/alertmanager/alertmanager" "$H2:/usr/local/bin/alertmanager"
docker cp "$MON/alert_webhook.py" "$H2:/usr/local/bin/alert_webhook.py"
docker cp "$MON/prom_proxy.py" "$H2:/usr/local/bin/prom_proxy.py"
docker exec "$H2" chmod +x /usr/local/bin/prometheus /usr/local/bin/alertmanager /usr/local/bin/alert_webhook.py /usr/local/bin/prom_proxy.py

echo "== configs =="
docker exec "$H2" mkdir -p /etc/prometheus /etc/alertmanager /var/lib/prometheus /var/lib/alertmanager
docker cp "$MON/prometheus-standby.yml" "$H2:/etc/prometheus/prometheus.yml"
docker cp "$MON/rules.yml" "$H2:/etc/prometheus/rules.yml"
docker cp "$MON/alertmanager-standby.yml" "$H2:/etc/alertmanager/alertmanager.yml"

cat > /tmp/prometheus-standby.service <<'EOF'
[Unit]
Description=Prometheus server (standby)
After=network.target

[Service]
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /tmp/alertmanager-standby.service <<'EOF'
[Unit]
Description=Alertmanager (standby, cluster peer h1)
After=network.target

[Service]
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=0.0.0.0:9093 \
  --cluster.listen-address=0.0.0.0:9094 \
  --cluster.peer=172.19.0.5:9094
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /tmp/alert_webhook-standby.service <<'EOF'
[Unit]
Description=HodoopForge alert webhook receiver (standby)
After=network.target

[Service]
Environment=ALERT_LOG=/var/log/hodoopforge-alerts.jsonl
ExecStart=/usr/bin/python3 /usr/local/bin/alert_webhook.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /tmp/prom_proxy-standby.service <<'EOF'
[Unit]
Description=Prometheus failover proxy
After=network.target

[Service]
Environment=PROM_PROXY_PORT=9099
Environment=PROM_PROXY_UPSTREAMS=http://172.19.0.5:9090,http://172.19.0.3:9090
ExecStart=/usr/bin/python3 /usr/local/bin/prom_proxy.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

for unit in prometheus alertmanager alert_webhook prom_proxy; do
  docker cp "/tmp/${unit}-standby.service" "$H2:/etc/systemd/system/${unit}.service"
  docker exec "$H2" systemctl daemon-reload
  docker exec "$H2" systemctl enable --now "$unit" >/dev/null 2>&1 || true
  docker exec "$H2" systemctl restart "$unit"
  echo "  $unit: $(docker exec "$H2" systemctl is-active "$unit")"
done

echo "== verify =="
sleep 5
curl -s -o /dev/null -w "  h2 prometheus /-/ready: %{http_code}\n" --max-time 8 http://172.19.0.3:9090/-/ready || true
curl -s -o /dev/null -w "  h2 alertmanager /-/ready: %{http_code}\n" --max-time 8 http://172.19.0.3:9093/-/ready || true
curl -s -o /dev/null -w "  h2 webhook /-/healthy: %{http_code}\n" --max-time 8 http://172.19.0.3:9500/-/healthy || true
curl -s -o /dev/null -w "  h2 prom_proxy /-/ready: %{http_code}\n" --max-time 8 http://172.19.0.3:9099/-/ready || true
