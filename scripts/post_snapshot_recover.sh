#!/usr/bin/env bash
# Post-snapshot health check + auto-recover for the HodoopForge cluster.
#
# Why: taking a host/VM snapshot briefly suspends the guest. Hadoop daemons can
# receive SIGTERM and stay down after the snapshot completes (NameNode,
# HBase Master, Flink TaskManagers...). This script checks Ambari and brings
# stopped services/components back, then reports HDFS HA / Flink / alerts.
#
# Usage:
#   bash scripts/post_snapshot_recover.sh            # check + auto-start
#   bash scripts/post_snapshot_recover.sh --check    # report only, no changes
#   bash scripts/post_snapshot_recover.sh --submit-flink
#                                                    # also resubmit Flink job
#                                                    # if none is RUNNING
#
# Env:
#   AMBARI_URL   default http://localhost:20609
#   AMBARI_USER  from /etc/hodoopforge/ambari.env (or env)
#   AMBARI_PASS  from /etc/hodoopforge/ambari.env (or env)
#   FLINK_URL    default http://172.19.0.2:8081
#
# Options:
#   --check          report only
#   --submit-flink   resubmit the Flink job when none is RUNNING
#   --fix-nat        ensure host DNAT + container hairpin for 9092/9093/9094
#   --fix-kafka      fix h2/h3 advertised.listeners (rolling restart)
#   --reset-wizard   reset stale Ambari HA wizard persist state
#   --all            --fix-nat --fix-kafka --reset-wizard
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

# Credentials: /etc/hodoopforge/ambari.env (root-only) > environment > legacy default.
if [ -r /etc/hodoopforge/ambari.env ]; then
  . /etc/hodoopforge/ambari.env
elif [ -e /etc/hodoopforge/ambari.env ]; then
  echo "WARN: cannot read /etc/hodoopforge/ambari.env; run as root or export AMBARI_PASS" >&2
fi
AMBARI_URL="${AMBARI_URL:-http://localhost:20609}"
AMBARI_USER="${AMBARI_USER:-admin}"
AMBARI_PASS="${AMBARI_PASS:-admin}"
FLINK_URL="${FLINK_URL:-http://172.19.0.2:8081}"
CLUSTER="${CLUSTER:-qixuandata}"
JAR="${FLINK_JAR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/datalake/pipelines/flink_sql_job/release/flink-sql-job-ha-20s-fixed.jar}"

CHECK_ONLY=0
SUBMIT_FLINK=0
FIX_NAT=0
FIX_KAFKA=0
RESET_WIZARD=0
for arg in "$@"; do
  case "$arg" in
    --check|-n) CHECK_ONLY=1 ;;
    --submit-flink) SUBMIT_FLINK=1 ;;
    --fix-nat) FIX_NAT=1 ;;
    --fix-kafka) FIX_KAFKA=1 ;;
    --reset-wizard) RESET_WIZARD=1 ;;
    --all) FIX_NAT=1; FIX_KAFKA=1; RESET_WIZARD=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { log "FAIL: $*"; RC=1; }

api() {
  curl -s -u "$AMBARI_USER:$AMBARI_PASS" -H 'X-Requested-By: ambari' "$@"
}

# Wait until Ambari REST is reachable.
wait_ambari() {
  for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
      -u "$AMBARI_USER:$AMBARI_PASS" -H 'X-Requested-By: ambari' \
      "$AMBARI_URL/api/v1/clusters/$CLUSTER" 2>/dev/null)
    [ "$code" = "200" ] && return 0
    sleep 2
  done
  return 1
}

get_service_state() {
  api "$AMBARI_URL/api/v1/clusters/$CLUSTER/services/$1?fields=ServiceInfo/state" 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["ServiceInfo"]["state"])' 2>/dev/null
}

wait_request() {
  local id="$1" timeout="${2:-600}" i st
  for ((i=0; i<timeout/5; i++)); do
    st=$(api "$AMBARI_URL/api/v1/clusters/$CLUSTER/requests/$id" 2>/dev/null \
      | python3 -c 'import sys,json;print(json.load(sys.stdin).get("Requests",{}).get("request_status",""))' 2>/dev/null)
    case "$st" in
      COMPLETED) return 0 ;;
      FAILED|ABORTED|TIMEDOUT) log "  request $id -> $st"; return 1 ;;
    esac
    sleep 5
  done
  log "  request $id -> timeout"
  return 1
}

start_service() {
  local svc="$1" resp id
  log "  starting $svc ..."
  resp=$(api -H 'Content-Type: application/json' -X PUT \
    "$AMBARI_URL/api/v1/clusters/$CLUSTER/services/$svc" \
    -d "{\"RequestInfo\":{\"context\":\"post-snapshot recover: start $svc\"},\"ServiceInfo\":{\"state\":\"STARTED\"}}")
  id=$(printf '%s' "$resp" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("Requests",{}).get("id",""))' 2>/dev/null)
  if [ -z "$id" ]; then
    log "  no request id for $svc (already started?)"
    return 0
  fi
  wait_request "$id" 600
}

ensure_service() {
  local svc="$1" st
  st=$(get_service_state "$svc")
  if [ "$st" = "STARTED" ]; then
    log "  $svc: STARTED"
  else
    log "  $svc: $st -> needs start"
    if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
    start_service "$svc"
    st=$(get_service_state "$svc")
    [ "$st" = "STARTED" ] && log "  $svc: STARTED" || fail "$svc is $st after start"
  fi
}

# Flink service STARTED does not always start TaskManagers that are INSTALLED.
# Prefer the Flink REST view: Ambari component state can stay INSTALLED even
# when the TM process is alive (seen after manual/Ambari starts).
ensure_flink_tms() {
  local tm_count rows
  tm_count=$(curl -s --max-time 5 "$FLINK_URL/taskmanagers" 2>/dev/null \
    | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get("taskmanagers",[])))' 2>/dev/null)
  if [ -n "$tm_count" ] && [ "$tm_count" -ge 1 ] 2>/dev/null; then
    log "  Flink TaskManagers: $tm_count registered (REST), skip Ambari state"
    return 0
  fi
  rows=$(api "$AMBARI_URL/api/v1/clusters/$CLUSTER/hosts?fields=Hosts/host_name,host_components/HostRoles/state,host_components/HostRoles/component_name,host_components/HostRoles/service_name&page_size=200" 2>/dev/null \
    | python3 -c '
import sys,json
for h in json.load(sys.stdin).get("items",[]):
    hn=h["Hosts"]["host_name"]
    for c in h.get("host_components",[]):
        r=c["HostRoles"]
        if r["service_name"]=="FLINK" and r["component_name"]=="FLINK_TASKMANAGER" and r["state"]!="STARTED":
            print(hn)
' 2>/dev/null)
  if [ -z "$rows" ]; then
    log "  Flink TaskManagers: all STARTED"
    return 0
  fi
  for hn in $rows; do
    log "  Flink TM on $hn not running"
    [ "$CHECK_ONLY" = "1" ] && continue
    local resp id
    resp=$(api -H 'Content-Type: application/json' -X PUT \
      "$AMBARI_URL/api/v1/clusters/$CLUSTER/hosts/$hn/host_components/FLINK_TASKMANAGER" \
      -d "{\"RequestInfo\":{\"context\":\"post-snapshot recover: start Flink TM on $hn\"},\"HostRoles\":{\"state\":\"STARTED\"}}")
    id=$(printf '%s' "$resp" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("Requests",{}).get("id",""))' 2>/dev/null)
    [ -n "$id" ] && wait_request "$id" 300
  done
}

check_hdfs_ha() {
  local out
  out=$(timeout 40 docker exec bigtop_hostname0 bash -c \
    "su -s /bin/bash hdfs -c 'hdfs haadmin -getAllServiceState'" 2>/dev/null)
  if printf '%s' "$out" | grep -q 'active'; then
    printf '%s\n' "$out" | grep -E 'active|standby' | sed 's/^/    /'
  else
    fail "HDFS HA not healthy: $(printf '%s' "$out" | tail -1)"
  fi
}

check_flink_job() {
  local overview running jid
  overview=$(curl -s --max-time 8 "$FLINK_URL/jobs/overview" 2>/dev/null) || { fail "Flink REST unreachable"; return; }
  running=$(printf '%s' "$overview" | python3 -c '
import sys,json
js=json.load(sys.stdin).get("jobs",[])
r=[j for j in js if j["state"]=="RUNNING"]
print(r[0]["jid"] if r else "")
' 2>/dev/null)
  if [ -n "$running" ]; then
    log "  Flink job RUNNING: $running"
    curl -s --max-time 8 "$FLINK_URL/jobs/$running/checkpoints" 2>/dev/null \
      | python3 -c 'import sys,json;c=json.load(sys.stdin).get("counts",{});print("    checkpoints completed=%s failed=%s"%(c.get("completed"),c.get("failed")))' 2>/dev/null
    return 0
  fi
  log "  no RUNNING Flink job"
  if [ "$SUBMIT_FLINK" = "1" ] && [ "$CHECK_ONLY" = "0" ]; then
    [ -f "$JAR" ] || { fail "Flink JAR not found: $JAR"; return; }
    log "  submitting $(basename "$JAR") ..."
    local up jarid resp jid
    up=$(curl -s --max-time 60 -F "jarfile=@$JAR" "$FLINK_URL/jars/upload")
    jarid=$(printf '%s' "$up" | python3 -c 'import sys,json;print(json.load(sys.stdin)["filename"].split("/")[-1])' 2>/dev/null)
    [ -n "$jarid" ] || { fail "Flink JAR upload failed"; return; }
    resp=$(curl -s --max-time 30 -X POST "$FLINK_URL/jars/$jarid/run" \
      -H 'Content-Type: application/json' -d '{"entryClass":"SqlJob","parallelism":2}')
    jid=$(printf '%s' "$resp" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("jobid",""))' 2>/dev/null)
    [ -n "$jid" ] && log "  submitted job: $jid" || fail "Flink job submit failed: $resp"
  else
    log "  (use --submit-flink to resubmit $JAR)"
  fi
}

report_alerts() {
  local counts
  counts=$(api "$AMBARI_URL/api/v1/clusters/$CLUSTER/alerts?fields=Alert/state,Alert/definition_name&page_size=500" 2>/dev/null \
    | python3 -c '
import sys,json,collections
its=json.load(sys.stdin).get("items",[])
c=collections.Counter(a["Alert"]["state"] for a in its)
print(" ".join("%s=%s"%(k,v) for k,v in sorted(c.items())))
for a in its:
    al=a["Alert"]
    if al["state"]=="CRITICAL": print("  CRITICAL:",al.get("definition_name"))
' 2>/dev/null)
  printf '%s\n' "$counts" | sed 's/^/    /'
}

# ── NAT / hairpin ─────────────────────────────────────────────
NAT_IMAGE="bigtop/puppet:trunk-rockylinux-8"

ensure_nat() {
  local cnt hp
  if ! command -v docker >/dev/null 2>&1; then
    fail "docker not found, cannot check NAT"
    return
  fi
  cnt=$(docker run --rm --privileged --net=host -v /:/host:ro "$NAT_IMAGE" \
    chroot /host /usr/sbin/iptables -t nat -S 2>/dev/null \
    | grep -cE 'dport (9092|9093|9094)')
  if [ "${cnt:-0}" -ge 6 ]; then
    log "  NAT kafka rules: ${cnt}/6 OK"
  else
    log "  NAT kafka rules: ${cnt}/6 -> refresh"
    [ "$CHECK_ONLY" = "1" ] && return
    docker run --rm --privileged --net=host -v /:/host:ro "$NAT_IMAGE" \
      chroot /host /bin/bash "$ROOT/ambari3/scripts/setup-nat-forward.sh" refresh \
      >/tmp/hodoopforge-nat-refresh.log 2>&1 || fail "NAT refresh failed (see /tmp/hodoopforge-nat-refresh.log)"
  fi

  hp=$(docker run --rm --privileged --net=container:bigtop_hostname0 -v /:/host:ro "$NAT_IMAGE" \
    chroot /host /usr/sbin/iptables -t nat -S OUTPUT 2>/dev/null \
    | grep -c '192.168.0.60')
  if [ "${hp:-0}" -ge 3 ]; then
    log "  container hairpin: ${hp}/3 OK"
  else
    log "  container hairpin: ${hp}/3 -> apply"
    [ "$CHECK_ONLY" = "1" ] && return
    bash "$ROOT/scripts/kafka_external_listener.sh" apply \
      >/tmp/hodoopforge-kafka-hairpin.log 2>&1 || fail "hairpin apply failed (see /tmp/hodoopforge-kafka-hairpin.log)"
  fi
}

# ── Kafka advertised.listeners ────────────────────────────────
kafka_adv() {
  docker exec "$1" bash -c \
    "grep -m1 '^advertised.listeners=' /etc/kafka/conf/server.properties 2>/dev/null | cut -d= -f2-" 2>/dev/null
}

ensure_kafka_adv() {
  local spec h port cur exp
  for spec in "bigtop_hostname0 9092" "bigtop_hostname2 9093" "bigtop_hostname3 9094"; do
    set -- $spec; h="$1"; port="$2"
    exp="PLAINTEXT://192.168.0.60:${port}"
    cur=$(kafka_adv "$h")
    if [ "$cur" = "$exp" ]; then
      log "  ${h}: $cur"
      continue
    fi
    log "  ${h}: '${cur:-<none>}' (expect $exp)"
    if [ "$h" = "bigtop_hostname0" ]; then
      log "    h0 is Ambari-managed; update kafka-broker config in Ambari and restart KAFKA_BROKER"
      continue
    fi
    [ "$FIX_KAFKA" = "1" ] && [ "$CHECK_ONLY" = "0" ] || continue
    log "    fixing ${h} and restarting kafka-broker ..."
    docker exec "$h" bash -c "
      cp -a /etc/kafka/conf/server.properties /etc/kafka/conf/server.properties.bak.\$(date +%s)
      if grep -q '^advertised.listeners=' /etc/kafka/conf/server.properties; then
        sed -i 's|^advertised.listeners=.*|advertised.listeners=${exp}|' /etc/kafka/conf/server.properties
      else
        echo 'advertised.listeners=${exp}' >> /etc/kafka/conf/server.properties
      fi
      systemctl restart kafka-broker" >/dev/null 2>&1 || { fail "restart $h failed"; continue; }
    for _ in $(seq 1 20); do
      docker exec "$h" bash -c "ss -ltn | grep -q ':9092 '" 2>/dev/null && break
      sleep 2
    done
    log "    ${h}: $(kafka_adv "$h")"
  done
}

# ── Ambari HA wizard persist ──────────────────────────────────
ensure_wizard() {
  [ "$RESET_WIZARD" = "1" ] || return
  if [ "$CHECK_ONLY" = "1" ]; then
    log "  reset requested (skipped in --check mode)"
    return
  fi
  bash "$ROOT/scripts/ambari_reset_ha_wizard.sh" >/tmp/hodoopforge-wizard-reset.log 2>&1 \
    && log "  wizard persist reset OK" \
    || fail "wizard reset failed (see /tmp/hodoopforge-wizard-reset.log)"
}

RC=0
log "post-snapshot recover (check_only=$CHECK_ONLY)"
if ! wait_ambari; then
  echo "Ambari is not reachable at $AMBARI_URL" >&2
  exit 1
fi

log "services:"
for svc in ZOOKEEPER HDFS YARN MAPREDUCE2 HIVE HBASE KAFKA SPARK FLINK RANGER; do
  ensure_service "$svc"
done

log "flink taskmanagers:"
ensure_flink_tms

log "NAT / hairpin:"
ensure_nat

log "Kafka advertised:"
ensure_kafka_adv

log "HDFS HA:"
check_hdfs_ha

log "Flink job:"
check_flink_job

log "alerts:"
report_alerts

log "Ambari wizard:"
ensure_wizard

log "done (rc=$RC)"
exit "$RC"
