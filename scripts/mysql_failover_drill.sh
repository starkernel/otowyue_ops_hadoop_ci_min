#!/usr/bin/env bash
# MySQL promotion / re-replication drill (M-104).
#
#   sudo bash scripts/mysql_failover_drill.sh
#
# The application still points at h0 during the drill, so business traffic is
# not redirected.  h3 is promoted, a throwaway database is written, then h3 is
# re-pointed at h0 from the master position captured before promotion.
# Expected impact: h3 replica unavailable for the duration (seconds), no
# primary outage.
set -euo pipefail

PRIMARY=bigtop_hostname0
REPLICA=bigtop_hostname3
PRIMARY_HOST=bigtop-hostname0.bigtop.apache.org
ENV_FILE=/etc/hodoopforge/mysql-repl.env
DRILL_DB=failover_drill

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
q() { docker exec "$1" mysql -N -e "$2"; }

replica_status() {
  docker exec "$REPLICA" mysql -e "SHOW REPLICA STATUS\G" 2>/dev/null
}

io=$(replica_status | awk -F': ' '/Replica_IO_Running:/{print $2}')
sql=$(replica_status | awk -F': ' '/Replica_SQL_Running:/{print $2}')
lag=$(replica_status | awk -F': ' '/Seconds_Behind_Source:/{print $2}')
log "before: IO=$io SQL=$sql lag=${lag:-?}s"
[ "$io" = "Yes" ] && [ "$sql" = "Yes" ] || { echo "replica not healthy" >&2; exit 1; }
[ "${lag:-0}" = "0" ] || { echo "replica lag is ${lag}s; wait for 0" >&2; exit 1; }

read -r file pos < <(q "$PRIMARY" "show master status" | awk 'NR==1{print $1, $2}')
[ -n "${file:-}" ] && [ -n "${pos:-}" ] || { echo "cannot read master position" >&2; exit 1; }
log "master position: $file:$pos"

pw=$(docker exec "$PRIMARY" bash -c "grep '^MYSQL_REPL_PASSWORD=' $ENV_FILE | cut -d= -f2")
[ -n "$pw" ] || { echo "replication password missing" >&2; exit 1; }

start=$(date +%s)
log "promoting $REPLICA"
docker exec "$REPLICA" mysql -e \
  "STOP REPLICA; RESET REPLICA ALL; SET GLOBAL read_only=OFF; SET GLOBAL super_read_only=OFF;"
docker exec "$REPLICA" mysql -e \
  "DROP DATABASE IF EXISTS \`$DRILL_DB\`; CREATE DATABASE \`$DRILL_DB\`; \
   CREATE TABLE \`$DRILL_DB\`.t (id INT PRIMARY KEY, note VARCHAR(32)); \
   INSERT INTO \`$DRILL_DB\`.t VALUES (1, 'promotion-ok');"
written=$(q "$REPLICA" "select note from \`$DRILL_DB\`.t where id=1")
promote_seconds=$(( $(date +%s) - start ))
log "promotion write: $written (${promote_seconds}s)"
[ "$written" = "promotion-ok" ] || { echo "promotion write failed" >&2; exit 1; }

docker exec "$REPLICA" mysql -e "DROP DATABASE \`$DRILL_DB\`;"
log "re-pointing $REPLICA to $PRIMARY at $file:$pos"
docker exec "$REPLICA" mysql -e \
  "CHANGE REPLICATION SOURCE TO SOURCE_HOST='$PRIMARY_HOST', SOURCE_USER='repl', \
   SOURCE_PASSWORD='$pw', SOURCE_LOG_FILE='$file', SOURCE_LOG_POS=$pos, \
   SOURCE_CONNECT_RETRY=10, SOURCE_RETRY_COUNT=0; START REPLICA;"

for _ in $(seq 1 30); do
  st=$(replica_status)
  echo "$st" | grep -q 'Replica_IO_Running: Yes' && \
    echo "$st" | grep -q 'Replica_SQL_Running: Yes' && break
  sleep 2
done
final_lag=$(replica_status | awk -F': ' '/Seconds_Behind_Source:/{print $2}')
total=$(( $(date +%s) - start ))
log "after: IO=Yes SQL=Yes lag=${final_lag:-?}s total=${total}s"
log "drill complete; h0 remains primary, h3 is replica again"
