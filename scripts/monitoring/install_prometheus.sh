#!/usr/bin/env bash
# Install Prometheus + Alertmanager + exporters into the HodoopForge containers.
#
#   DIST=/tmp/opencode/dist bash scripts/monitoring/install_prometheus.sh
#
# Layout:
#   h0-h3 : node_exporter :9100
#   h1    : prometheus :9090, alertmanager :9093, kafka_exporter :9308,
#           hdfs_jmx_exporter :9401, ambari_exporter :9402, flink_exporter :9403
#
# No Hadoop/Kafka/Flink service is restarted by this script.
set -euo pipefail

DIST="${DIST:-/tmp/opencode/dist}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MON="$ROOT/scripts/monitoring"
NODES=(bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3)
CORE=bigtop_hostname1

for f in \
  "$DIST/node_exporter/node_exporter" \
  "$DIST/prometheus/prometheus" \
  "$DIST/alertmanager/alertmanager" \
  "$DIST/kafka_exporter/kafka_exporter"; do
  [ -f "$f" ] || { echo "missing binary: $f" >&2; exit 1; }
done
for f in "$MON/prometheus.yml" "$MON/rules.yml" "$MON/alertmanager.yml" \
         "$MON/hdfs_jmx_exporter.py" "$MON/ambari_exporter.py" "$MON/flink_exporter.py"; do
  [ -f "$f" ] || { echo "missing config: $f" >&2; exit 1; }
done

echo "== node_exporter =="
cat > /tmp/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus node_exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100 \
  --collector.filesystem.fs-types-exclude="^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|erofs|sysfs|tracefs)$"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
for h in "${NODES[@]}"; do
  docker cp "$DIST/node_exporter/node_exporter" "$h:/usr/local/bin/node_exporter"
  docker exec "$h" chmod +x /usr/local/bin/node_exporter
  docker cp /tmp/node_exporter.service "$h:/etc/systemd/system/node_exporter.service"
  docker exec "$h" systemctl daemon-reload
  docker exec "$h" systemctl enable --now node_exporter >/dev/null 2>&1 || true
  docker exec "$h" systemctl restart node_exporter
  echo "  $h: $(docker exec "$h" systemctl is-active node_exporter)"
done

echo "== core exporters on $CORE =="
docker cp "$DIST/prometheus/prometheus" "$CORE:/usr/local/bin/prometheus"
docker cp "$DIST/alertmanager/alertmanager" "$CORE:/usr/local/bin/alertmanager"
docker cp "$DIST/kafka_exporter/kafka_exporter" "$CORE:/usr/local/bin/kafka_exporter"
for f in hdfs_jmx_exporter.py ambari_exporter.py flink_exporter.py alert_webhook.py; do
  docker cp "$MON/$f" "$CORE:/usr/local/bin/$f"
done
docker exec "$CORE" chmod +x /usr/local/bin/prometheus /usr/local/bin/alertmanager \
  /usr/local/bin/kafka_exporter /usr/local/bin/hdfs_jmx_exporter.py \
  /usr/local/bin/ambari_exporter.py /usr/local/bin/flink_exporter.py /usr/local/bin/alert_webhook.py

docker exec "$CORE" mkdir -p /etc/prometheus /etc/alertmanager /var/lib/prometheus /var/lib/alertmanager /etc/hodoopforge
docker cp "$MON/prometheus.yml" "$CORE:/etc/prometheus/prometheus.yml"
docker cp "$MON/rules.yml" "$CORE:/etc/prometheus/rules.yml"
docker cp "$MON/alertmanager.yml" "$CORE:/etc/alertmanager/alertmanager.yml"

# Ambari credentials: copy the root-only host file into the core container.
if docker run --rm -v /:/host:ro busybox test -r /host/etc/hodoopforge/ambari.env; then
  docker run --rm -v /:/host:ro busybox cat /host/etc/hodoopforge/ambari.env > /tmp/ambari.env
  docker cp /tmp/ambari.env "$CORE:/etc/hodoopforge/ambari.env"
  docker exec "$CORE" chmod 600 /etc/hodoopforge/ambari.env
  rm -f /tmp/ambari.env
  echo "  copied Ambari credentials"
else
  echo "  WARN: /etc/hodoopforge/ambari.env unreadable; ambari_exporter will use defaults" >&2
fi

cat > /tmp/prometheus.service <<'EOF'
[Unit]
Description=Prometheus server
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

cat > /tmp/alertmanager.service <<'EOF'
[Unit]
Description=Alertmanager
After=network.target

[Service]
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=0.0.0.0:9093 \
  --cluster.listen-address=0.0.0.0:9094 \
  --cluster.peer=172.19.0.3:9094
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /tmp/kafka_exporter.service <<'EOF'
[Unit]
Description=Kafka exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/kafka_exporter \
  --kafka.server=192.168.0.60:9092 \
  --web.listen-address=:9308
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

for name in hdfs_jmx_exporter ambari_exporter flink_exporter alert_webhook; do
  cat > "/tmp/$name.service" <<EOF
[Unit]
Description=HodoopForge $name
After=network.target

[Service]
EnvironmentFile=-/etc/hodoopforge/ambari.env
Environment=AMBARI_URL=http://172.19.0.2:8080
ExecStart=/usr/bin/python3 /usr/local/bin/$name.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
done

for unit in prometheus alertmanager kafka_exporter hdfs_jmx_exporter ambari_exporter flink_exporter alert_webhook; do
  docker cp "/tmp/$unit.service" "$CORE:/etc/systemd/system/$unit.service"
  docker exec "$CORE" systemctl daemon-reload
  docker exec "$CORE" systemctl enable --now "$unit" >/dev/null 2>&1 || true
  docker exec "$CORE" systemctl restart "$unit"
  echo "  $unit: $(docker exec "$CORE" systemctl is-active "$unit")"
done

echo "== verify =="
sleep 5
curl -s -o /dev/null -w "  prometheus /-/ready: %{http_code}\n" --max-time 8 http://172.19.0.5:9090/-/ready || true
curl -s -o /dev/null -w "  alertmanager /-/ready: %{http_code}\n" --max-time 8 http://172.19.0.5:9093/-/ready || true
for port in 9100 9308 9401 9402 9403 9500; do
  echo -n "  :$port -> "
  curl -s --max-time 8 "http://172.19.0.5:$port/metrics" 2>/dev/null | head -1 || echo "no response"
done
