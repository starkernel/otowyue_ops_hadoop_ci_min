#!/usr/bin/env bash
# Flink JobManager HA (T-065): JM1 on h0 (Ambari) + JM2 on h1 (systemd).
#
#   bash scripts/flink_jm_ha.sh install     # create/refresh JM2 on h1
#   bash scripts/flink_jm_ha.sh status      # both JMs + job + checkpoints
#   bash scripts/flink_jm_ha.sh sync-libs   # copy missing connector jars to h1
#
# Why a systemd unit: the Bigtop FLINK metainfo declares FLINK_JOBMANAGER
# cardinality=1, so Ambari refuses a second JobManager.  JM2 is therefore
# managed outside Ambari but uses the same /etc/flink/conf (HA settings) with a
# per-node copy that advertises bigtop-hostname1 instead of hostname0.
#
# HA settings (already pushed through Ambari -> flink-conf):
#   high-availability.type: zookeeper
#   high-availability.storageDir: hdfs://qixuandata/flink/ha
#   high-availability.zookeeper.quorum: h0,h1,h2:2181
#   high-availability.cluster-id: /hodoopforge
set -euo pipefail

JM1=bigtop_hostname0
JM2=bigtop_hostname1
JM1_IP=172.19.0.2
JM2_IP=172.19.0.5
JM2_HOST=bigtop-hostname1.bigtop.apache.org
FLINK_HOME=/usr/lib/flink
CONF=/etc/flink/conf
CONF2=/etc/flink/conf-jm2
UNIT=/etc/systemd/system/flink-jobmanager-2.service
JOB_ID="${FLINK_JOB_ID:-ff461d2418dcb6a5a6ad4c2504486fd1}"

log() { printf '%s\n' "$*"; }

sync_libs() {
  local missing
  missing=$(comm -23 \
    <(docker exec "$JM1" bash -c "ls $FLINK_HOME/lib | sort") \
    <(docker exec "$JM2" bash -c "ls $FLINK_HOME/lib | sort"))
  if [ -z "$missing" ]; then
    log "  libs: h1 already has every jar from h0"
    return 0
  fi
  while IFS= read -r jar; do
    [ -n "$jar" ] || continue
    docker cp "$JM1:$FLINK_HOME/lib/$jar" "/tmp/$jar"
    docker cp "/tmp/$jar" "$JM2:$FLINK_HOME/lib/$jar"
    docker exec "$JM2" chown flink:hadoop "$FLINK_HOME/lib/$jar"
    log "  copied $jar"
  done <<< "$missing"
}

install_jm2() {
  log "== sync connector jars =="
  sync_libs

  log "== per-node config $CONF2 =="
  docker exec "$JM2" bash -c "
    mkdir -p $CONF2
    for f in $CONF/*; do
      ln -sfn \"\$f\" $CONF2/\$(basename \$f)
    done
    rm -f $CONF2/flink-conf.yaml
    cp $CONF/flink-conf.yaml $CONF2/flink-conf.yaml
    sed -i 's|^jobmanager.rpc.address:.*|jobmanager.rpc.address: $JM2_HOST|' $CONF2/flink-conf.yaml
    sed -i 's|^rest.address:.*|rest.address: $JM2_HOST|' $CONF2/flink-conf.yaml
    grep -q '^high-availability.type: zookeeper' $CONF2/flink-conf.yaml || {
      echo 'ERROR: HA is not enabled in $CONF/flink-conf.yaml' >&2; exit 1; }
    grep -E '^(jobmanager.rpc.address|rest.address|high-availability.type)' $CONF2/flink-conf.yaml
  "

  log "== systemd unit =="
  cat > /tmp/flink-jobmanager-2.service <<EOF
[Unit]
Description=Flink JobManager (standby, JM2)
After=network.target

[Service]
Type=simple
User=flink
Group=hadoop
Environment=FLINK_CONF_DIR=$CONF2
Environment=HADOOP_CONF_DIR=/etc/hadoop/conf
Environment=FLINK_PID_DIR=/var/run/flink
Environment=HOME=/home/flink
ExecStart=/bin/bash -lc 'export HADOOP_CLASSPATH=\$(hadoop classpath); exec $FLINK_HOME/bin/jobmanager.sh start-foreground'
Restart=always
RestartSec=10
TimeoutStopSec=60
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF
  docker cp /tmp/flink-jobmanager-2.service "$JM2:$UNIT"
  docker exec "$JM2" systemctl daemon-reload
  docker exec "$JM2" systemctl enable flink-jobmanager-2 >/dev/null 2>&1 || true
  docker exec "$JM2" systemctl restart flink-jobmanager-2
  sleep 20
  log "  JM2: $(docker exec "$JM2" systemctl is-active flink-jobmanager-2)"
}

status() {
  local ip code
  for spec in "JM1 h0 $JM1_IP" "JM2 h1 $JM2_IP"; do
    set -- $spec
    printf '  %s (%s) REST: ' "$1" "$2"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "http://$3:8081/jobs/overview" || true)
    printf '%s\n' "${code:-000}"
  done
  echo "  JM2 unit: $(docker exec "$JM2" systemctl is-active flink-jobmanager-2 2>/dev/null || echo unknown)"
  echo "  HA config: $(docker exec "$JM1" grep -c '^high-availability' "$CONF/flink-conf.yaml" 2>/dev/null || echo 0) keys"
  for ip in "$JM1_IP" "$JM2_IP"; do
    curl -s --max-time 6 "http://$ip:8081/jobs/overview" 2>/dev/null \
      | python3 -c "import json,sys;js=json.load(sys.stdin).get('jobs',[]);print('  %s jobs: %s'%('$ip',[(j['jid'][:8],j['state']) for j in js]))" 2>/dev/null || true
  done
  curl -s --max-time 6 "http://$JM1_IP:8081/jobs/$JOB_ID/checkpoints" 2>/dev/null \
    | python3 -c "import json,sys;print('  checkpoints:',json.load(sys.stdin).get('counts'))" 2>/dev/null || true
}

case "${1:-status}" in
  install) install_jm2 ;;
  sync-libs) sync_libs ;;
  status) status ;;
  *) echo "usage: $0 {install|sync-libs|status}" >&2; exit 2 ;;
esac
