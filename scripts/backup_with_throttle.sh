#!/usr/bin/env bash
# Throttled nightly backup for HodoopForge (T-070).
#
#   sudo bash scripts/backup_with_throttle.sh              # respects the window
#   sudo bash scripts/backup_with_throttle.sh --force      # ignore the window
#   sudo bash scripts/backup_with_throttle.sh --with-fsimage
#
# Why the throttle: this host has seen NVMe I/O timeouts while a full backup
# competed with Kafka/HDFS.  Every read runs under `ionice -c3` (idle class)
# and `nice -n19`, so foreground services always win.  Copy phases (if rsync is
# used) additionally cap bandwidth with --bwlimit.
#
# What is captured (small, restorable control plane):
#   * Ambari + Hive + Ranger + Oozie databases (mysqldump)
#   * /etc config trees for Ambari, Hadoop, Hive, HBase, Kafka, Flink, Ranger
#   * optional HDFS fsimage (--with-fsimage)
#
# Destination: /var/backups/hodoopforge/<YYYYmmdd-HHMM>/
# Retention:  7 days (BACKUP_RETENTION_DAYS)
set -euo pipefail

DEST="${BACKUP_DEST:-/var/backups/hodoopforge}"
RETENTION="${BACKUP_RETENTION_DAYS:-7}"
WINDOW_START="${BACKUP_WINDOW_START:-1}"
WINDOW_END="${BACKUP_WINDOW_END:-5}"
PRIMARY=bigtop_hostname0
BWLIMIT="${BACKUP_BWLIMIT_KB:-40960}"   # 40 MB/s
FORCE=0
WITH_FSIMAGE=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --with-fsimage) WITH_FSIMAGE=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

hour=$(date +%H)
if [ "$FORCE" -ne 1 ]; then
  if [ "$WINDOW_START" -le "$WINDOW_END" ]; then
    in_window=$(( hour >= WINDOW_START && hour < WINDOW_END ))
  else
    in_window=$(( hour >= WINDOW_START || hour < WINDOW_END ))
  fi
  if [ "$in_window" -ne 1 ]; then
    log "outside backup window ${WINDOW_START}:00-${WINDOW_END}:00, skipping (use --force)"
    exit 0
  fi
fi

stamp=$(date +%Y%m%d-%H%M)
target="$DEST/$stamp"
mkdir -p "$target"
chmod 700 "$DEST" "$target"

# Low-priority wrappers.  -c3 = idle I/O class, only runs when the disk is idle.
low() { ionice -c3 nice -n19 "$@"; }

available_kb=$(df -Pk "$DEST" | awk 'NR==2 {print $4}')
if [ "${available_kb:-0}" -lt 5242880 ]; then
  log "ERROR: less than 5 GiB free under $DEST, aborting"
  exit 1
fi

log "backup start -> $target"

log "1/4 database dump (ambari, hive, ranger, rangerkms, oozie)"
if low docker exec "$PRIMARY" bash -c \
    'mysqldump --single-transaction --quick --routines --triggers \
       --databases ambari hive ranger rangerkms oozie' \
    | gzip -1 > "$target/databases.sql.gz"; then
  log "    $(du -h "$target/databases.sql.gz" | cut -f1)"
else
  log "ERROR: database dump failed"
  exit 1
fi

log "2/4 configuration trees"
low docker exec "$PRIMARY" bash -c '
  for d in /etc/ambari-server/conf /etc/hadoop/conf /etc/hive/conf /etc/hbase/conf \
           /etc/kafka/conf /etc/flink/conf /etc/ranger /etc/ambari-metrics-grafana/conf; do
    [ -d "$d" ] && printf "%s\n" "$d"
  done | tar czf - -T -' > "$target/configs.tar.gz"
log "    $(du -h "$target/configs.tar.gz" | cut -f1)"

log "3/4 ZooKeeper snapshots (h0/h1/h2)"
for zk in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2; do
  low docker exec "$zk" tar czf - -C /hadoop zookeeper > "$target/zk-$zk.tar.gz" 2>/dev/null \
    || rm -f "$target/zk-$zk.tar.gz"
done
log "    $(du -ch "$target"/zk-*.tar.gz 2>/dev/null | tail -1 | cut -f1)"

if [ "$WITH_FSIMAGE" -eq 1 ]; then
  log "4/4 HDFS fsimage (fetchImage + tar)"
  docker exec "$PRIMARY" bash -c \
    'rm -rf /tmp/hf-fsimage && mkdir -p /tmp/hf-fsimage && \
     hdfs dfsadmin -fetchImage /tmp/hf-fsimage' >/dev/null
  low docker exec "$PRIMARY" tar czf - -C /tmp/hf-fsimage . > "$target/fsimage.tar.gz"
  docker exec "$PRIMARY" rm -rf /tmp/hf-fsimage
  log "    $(du -h "$target/fsimage.tar.gz" | cut -f1)"
else
  log "4/4 HDFS fsimage skipped (use --with-fsimage)"
fi

# Manifest without secrets: sizes + checksums only.
( cd "$target" && sha256sum ./* > SHA256SUMS 2>/dev/null || true )
chmod -R go-rwx "$target"

log "retention: removing backups older than ${RETENTION} days"
find "$DEST" -mindepth 1 -maxdepth 1 -type d -mtime "+$RETENTION" -print -exec rm -rf {} + 2>/dev/null || true

# rsync hint for anyone extending this to bulk data:
#   low rsync -a --bwlimit="$BWLIMIT" /source/ /dest/
log "backup done: $(du -sh "$target" | cut -f1)"
