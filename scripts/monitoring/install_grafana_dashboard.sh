#!/usr/bin/env bash
# Install the HodoopForge Grafana dashboard on the Ambari Metrics Grafana (h0).
#
#   bash scripts/monitoring/install_grafana_dashboard.sh
#
# What it does:
#   1. copies the dashboard JSON and the file provider into the container;
#   2. points Grafana provisioning at that directory (idempotent);
#   3. installs a systemd unit so Grafana survives a container restart (T-020);
#   4. restarts Grafana and verifies the dashboard row exists.
#
# The dashboard queries the Prometheus datasource named "Prometheus-Flink",
# which points at http://172.19.0.5:9090 (see MONITORING_PROMETHEUS.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/scripts/monitoring/grafana"
HOST=bigtop_hostname0
GRAFANA_CONF=/etc/ambari-metrics-grafana/conf/ams-grafana.ini
PROV=/etc/ambari-metrics-grafana/provisioning

[ -f "$SRC/dashboard-hodoopforge.json" ] || { echo "missing dashboard json" >&2; exit 1; }
[ -f "$SRC/provider.yml" ] || { echo "missing provider.yml" >&2; exit 1; }

echo "== copy provisioning files =="
docker exec "$HOST" mkdir -p "$PROV/dashboards" "$PROV/plugins" "$PROV/notifiers" "$PROV/alerting"
docker cp "$SRC/dashboard-hodoopforge.json" "$HOST:$PROV/dashboards/dashboard-hodoopforge.json"
docker cp "$SRC/provider.yml" "$HOST:$PROV/dashboards/provider.yml"

echo "== enable provisioning path =="
docker exec "$HOST" bash -c "
  if ! grep -q '^provisioning *= *$PROV' '$GRAFANA_CONF'; then
    sed -i '/^\[paths\]/a provisioning = $PROV' '$GRAFANA_CONF'
  fi
  grep -n '^provisioning' '$GRAFANA_CONF'
"

echo "== systemd unit =="
cat > /tmp/ambari-metrics-grafana.service <<'EOF'
[Unit]
Description=Ambari Metrics Grafana
After=network.target

[Service]
Type=simple
ExecStart=/usr/lib/ambari-metrics-grafana/bin/grafana-server \
  --pidfile=/var/run/ambari-metrics-grafana/grafana-server.pid \
  --config=/etc/ambari-metrics-grafana/conf/ams-grafana.ini \
  --homepath=/usr/lib/ambari-metrics-grafana \
  cfg:default.paths.data=/var/lib/ambari-metrics-grafana \
  cfg:default.paths.logs=/var/log/ambari-metrics-grafana
Restart=always
RestartSec=5
RuntimeDirectory=ambari-metrics-grafana

[Install]
WantedBy=multi-user.target
EOF
docker cp /tmp/ambari-metrics-grafana.service "$HOST:/etc/systemd/system/ambari-metrics-grafana.service"
docker exec "$HOST" systemctl daemon-reload
docker exec "$HOST" systemctl enable ambari-metrics-grafana >/dev/null 2>&1 || true

echo "== restart =="
# The original process was started by hand; stop it before systemd owns the port.
docker exec "$HOST" bash -c "pkill -f '[g]rafana-server --pidfile' || true"
sleep 2
docker exec "$HOST" systemctl restart ambari-metrics-grafana
sleep 8

echo "== verify =="
docker exec "$HOST" systemctl is-active ambari-metrics-grafana
curl -s -o /dev/null -w "  grafana /api/health: %{http_code}\n" --max-time 8 http://192.168.0.60:3000/api/health || true
docker exec -i "$HOST" python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/var/lib/ambari-metrics-grafana/grafana.db')
rows = con.execute("select uid,title from dashboard where uid='hodoopforge-overview'").fetchall()
print("  provisioned dashboard:", rows or "NOT FOUND")
con.close()
PY
