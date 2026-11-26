#!/usr/bin/env bash
# Promote the h3 MySQL replica when the h0 primary is lost.
#
#   bash scripts/mysql_failover.sh status
#   CONFIRM=yes bash scripts/mysql_failover.sh promote
#
# Promotion itself is safe and reversible at the data level; repointing the
# applications is a separate maintenance step because Ambari, Hive and Ranger
# all hold JDBC URLs.  After `promote`:
#
#   1. point Ambari at h3:
#        /etc/ambari-server/conf/ambari.properties
#        server.jdbc.url=jdbc:mysql://bigtop-hostname3.bigtop.apache.org/ambari
#        ambari-server restart
#   2. update Hive's javax.jdo.option.ConnectionURL and Ranger's
#        ranger.jpa.jdbc.url to h3 (Ambari config API), then restart HIVE/RANGER;
#   3. run `mysql_failover.sh status` to confirm the new primary is writable.
#
# When h0 comes back, rebuild it as a replica of h3; do NOT start it as a second
# primary (split brain).
set -euo pipefail

PRIMARY=bigtop_hostname0
REPLICA=bigtop_hostname3

log() { printf '%s\n' "$*"; }

status() {
  log "== h0 primary =="
  docker exec "$PRIMARY" bash -c "mysql -N -e 'select @@server_id,@@read_only; show master status;'" 2>/dev/null | head -3 || log "  h0 mysql unreachable"
  log "== h3 replica =="
  docker exec "$REPLICA" bash -c "mysql -N -e 'select @@server_id,@@read_only,@@super_read_only;'" 2>/dev/null || {
    log "  h3 mysql unreachable"; return 1; }
  docker exec "$REPLICA" mysql -e "SHOW REPLICA STATUS\G" 2>/dev/null \
    | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_Error" || true
}

promote() {
  if [ "${CONFIRM:-}" != "yes" ]; then
    echo "refusing to promote without CONFIRM=yes" >&2
    exit 2
  fi
  local lag io sql
  io=$(docker exec "$REPLICA" mysql -N -e "SHOW REPLICA STATUS\G" | awk -F': ' '/Replica_IO_Running:/{print $2}')
  sql=$(docker exec "$REPLICA" mysql -N -e "SHOW REPLICA STATUS\G" | awk -F': ' '/Replica_SQL_Running:/{print $2}')
  lag=$(docker exec "$REPLICA" mysql -N -e "SHOW REPLICA STATUS\G" | awk -F': ' '/Seconds_Behind_Source:/{print $2}')
  log "replica IO=$io SQL=$sql lag=${lag:-?}s"
  if [ "$io" != "Yes" ] || [ "$sql" != "Yes" ]; then
    echo "replica is not healthy; fix replication before promoting" >&2
    exit 3
  fi
  if [ "${lag:-0}" != "0" ] && [ "${lag:-0}" != "NULL" ]; then
    echo "replica lag is ${lag}s; wait for 0 before promoting" >&2
    exit 4
  fi
  docker exec "$REPLICA" bash -c "
    mysql -e 'STOP REPLICA; RESET REPLICA ALL;'
    mysql -e 'SET GLOBAL read_only=OFF; SET GLOBAL super_read_only=OFF;'
    mysql -N -e 'select @@server_id,@@read_only,@@super_read_only;'"
  log "h3 is now writable. Follow the repoint steps in the header."
}

case "${1:-status}" in
  status) status ;;
  promote) promote ;;
  *) echo "usage: $0 {status|promote}" >&2; exit 2 ;;
esac
