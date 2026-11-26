#!/usr/bin/env bash
# HDFS NameNode HA cutover helper for the EduLake Iceberg warehouse.
#
# Actions:
#   plan      dry-run: list tables and target locations (safe, before window)
#   migrate   stop Flink, change table locations + rewrite files (keeps old snapshots)
#   submit    upload/run the rebuilt Flink JAR, wait for RUNNING + checkpoint
#   expire    validate then drop pre-migration snapshots (closes rollback window)
#   rollback  stop Flink, migrate locations back to old authority, submit old JAR
#
# Required env for submit/rollback:
#   NEW_JAR / OLD_JAR  path to the Flink job JARs
#
# Never run migrate/expire outside the agreed maintenance window.
set -euo pipefail
cd "$(dirname "$0")/.."

FLINK="${FLINK_REST_URL:-http://192.168.0.60:8081}"
OLD_BASE="${OLD_ICEBERG_BASE:-hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse}"
NEW_BASE="${NEW_ICEBERG_BASE:-hdfs://qixuandata/iceberg-warehouse-ha}"
NEW_JAR="${NEW_JAR:-$PWD/datalake/pipelines/flink_sql_job/release/flink-sql-job-ha-20s.jar}"
OLD_JAR="${OLD_JAR:-$PWD/datalake/pipelines/flink_sql_job/release/flink-sql-job-rollback.jar}"
PY="${PY:-python3}"

log() { echo "[$(date '+%F %T')] $*"; }

flink_jid() {
  curl -s --noproxy '*' --max-time 8 "$FLINK/jobs/overview" \
    | "$PY" -c "import sys,json;d=json.load(sys.stdin);print(next((j['jid'] for j in d.get('jobs',[]) if j.get('state')=='RUNNING' and 'edulake-realtime-ingest' in j.get('name','')),''))"
}

cancel_flink() {
  local jid; jid="$(flink_jid)"
  if [[ -z "$jid" ]]; then log "no RUNNING Flink job"; return; fi
  log "cancel Flink job $jid"
  curl -s --noproxy '*' -X PATCH "$FLINK/jobs/$jid?mode=cancel" >/dev/null || true
  for _ in $(seq 1 30); do
    state=$(curl -s --noproxy '*' --max-time 5 "$FLINK/jobs/$jid" | "$PY" -c "import sys,json;print(json.load(sys.stdin).get('state',''))" 2>/dev/null || true)
    [[ "$state" == "CANCELED" ]] && break
    sleep 2
  done
}

submit_jar() {
  local jar="$1"
  [[ -f "$jar" ]] || { log "JAR not found: $jar"; exit 1; }
  local up jarid jid
  up=$(curl -s --noproxy '*' -F "jarfile=@$jar" "$FLINK/jars/upload")
  jarid=$(basename "$(echo "$up" | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["filename"])')")
  jid=$(curl -s --noproxy '*' -X POST "$FLINK/jars/$jarid/run" \
    -H 'Content-Type: application/json' \
    -d '{"entryClass":"SqlJob","parallelism":2}' \
    | "$PY" -c 'import json,sys;print(json.load(sys.stdin).get("jobid",""))')
  [[ -n "$jid" ]] || { log "submit failed"; exit 1; }
  log "submitted job $jid"
  for _ in $(seq 1 30); do
    state=$(curl -s --noproxy '*' --max-time 5 "$FLINK/jobs/$jid" | "$PY" -c "import sys,json;print(json.load(sys.stdin).get('state',''))" 2>/dev/null || true)
    [[ "$state" == "RUNNING" ]] && break
    sleep 2
  done
  [[ "$state" == "RUNNING" ]] || { log "job not RUNNING: $state"; exit 1; }
  for _ in $(seq 1 90); do
    ok=$(curl -s --noproxy '*' --max-time 5 "$FLINK/jobs/$jid/checkpoints" | "$PY" -c "import sys,json;print(json.load(sys.stdin).get('counts',{}).get('completed',0))" 2>/dev/null || echo 0)
    [[ "$ok" -ge 1 ]] && { log "checkpoint completed=$ok"; return; }
    sleep 3
  done
  log "no checkpoint within timeout"; exit 1
}

case "${1:-plan}" in
  plan)
    "$PY" datalake/pipelines/migrate_iceberg_warehouse.py --dry-run
    ;;
  migrate)
    log "window: migrate $OLD_BASE -> $NEW_BASE (old snapshots retained)"
    cancel_flink
    "$PY" datalake/pipelines/migrate_iceberg_warehouse.py \
      --old-base "$OLD_BASE" --new-base "$NEW_BASE"
    ;;
  submit)
    log "submit new Flink job with nameservice warehouse"
    submit_jar "$NEW_JAR"
    ;;
  expire)
    log "old catalog/tables are retained for rollback; no automatic deletion"
    log "cleanup of old warehouse is a separate, confirmed operation"
    ;;
  rollback)
    log "ROLLBACK: cancel new Flink job and submit old JAR (old catalog intact)"
    cancel_flink
    submit_jar "$OLD_JAR"
    ;;
  *)
    echo "usage: $0 {plan|migrate|submit|expire|rollback}" >&2
    exit 2
    ;;
esac
