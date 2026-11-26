#!/usr/bin/env bash
# MySQL primary/replica for the Hive metastore (T-064).
#
#   sudo bash scripts/mysql_replica_setup.sh            # install/refresh replica on h3
#   sudo bash scripts/mysql_replica_setup.sh status
#
# Topology:
#   h0  172.19.0.2  mysql 8.0 primary  (ambari/hive/ranger/oozie databases)
#   h3  172.19.0.4  mysql 8.0 replica  read_only, relay-log, server-id=2
#
# The replication password is generated once and stored root-only in
# /etc/hodoopforge/mysql-repl.env; it is never written to the repository.
#
# Promotion is deliberately manual: see scripts/mysql_failover.sh.  Repointing
# Ambari/Hive/Ranger at the promoted node requires a maintenance window.
set -euo pipefail

PRIMARY=bigtop_hostname0
REPLICA=bigtop_hostname3
PRIMARY_HOST=bigtop-hostname0.bigtop.apache.org
ENV_FILE=/etc/hodoopforge/mysql-repl.env
DUMP=/tmp/hodoopforge-replica.sql.gz

log() { printf '%s\n' "$*"; }

ensure_replica_packages() {
  if docker exec "$REPLICA" bash -c "command -v mysqld >/dev/null"; then
    log "  mysqld already installed on $REPLICA"
    return
  fi
  log "  installing mysql-server on $REPLICA"
  docker exec "$REPLICA" bash -c \
    "yum install -y mysql-server --disablerepo='*' --enablerepo=baseos --enablerepo=appstream >/dev/null 2>&1"
}

ensure_replica_config() {
  docker exec "$REPLICA" bash -c "cat > /etc/my.cnf.d/replica.cnf <<'EOF'
[mysqld]
server-id=2
relay-log=relay-bin
read_only=ON
super_read_only=ON
binlog-format=ROW
log-bin=replica-bin
EOF
systemctl enable mysqld >/dev/null 2>&1 || true
systemctl start mysqld
sleep 5
systemctl is-active mysqld"
}

ensure_repl_user() {
  if docker exec "$PRIMARY" test -f "$ENV_FILE"; then
    log "  replication credentials already present"
    return
  fi
  local pw
  pw=$(openssl rand -hex 16)
  docker exec "$PRIMARY" bash -c "mysql -e \"CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY '$pw'; GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%'; FLUSH PRIVILEGES;\""
  docker exec "$PRIMARY" bash -c "mkdir -p /etc/hodoopforge; printf 'MYSQL_REPL_USER=repl\nMYSQL_REPL_PASSWORD=%s\n' '$pw' > $ENV_FILE; chmod 600 $ENV_FILE"
  log "  created repl user and $ENV_FILE"
}

replica_running() {
  local out
  out=$(docker exec "$REPLICA" mysql -N -e "SHOW REPLICA STATUS\G" 2>/dev/null || true)
  printf '%s' "$out" | grep -q "Replica_IO_Running: Yes" && \
    printf '%s' "$out" | grep -q "Replica_SQL_Running: Yes"
}

seed_replica() {
  if docker exec "$REPLICA" bash -c \
      "mysql -N -e 'select count(*) from information_schema.tables where table_schema=\"ambari\"'" 2>/dev/null | grep -qv '^0$'; then
    log "  replica already seeded"
    return
  fi
  log "  dumping primary (single-transaction) and importing on $REPLICA"
  docker exec "$PRIMARY" bash -c \
    "mysqldump --single-transaction --quick --source-data=2 \
       --databases ambari hive ranger rangerkms oozie 2>/dev/null | gzip -1 > $DUMP"
  docker exec "$PRIMARY" bash -c \
    "zcat $DUMP | grep -m1 'CHANGE MASTER TO' | sed -E \"s/.*MASTER_LOG_FILE='([^']+)'.*MASTER_LOG_POS=([0-9]+).*/\\1 \\2/\" > /tmp/hodoopforge-replica.pos"
  docker cp "$PRIMARY:$DUMP" /tmp/hodoopforge-replica.sql.gz
  docker cp "$PRIMARY:/tmp/hodoopforge-replica.pos" /tmp/hodoopforge-replica.pos
  docker cp /tmp/hodoopforge-replica.sql.gz "$REPLICA:$DUMP"
  docker exec "$REPLICA" bash -c "
    mysql -e 'SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;'
    zcat $DUMP | mysql
    mysql -e 'SET GLOBAL read_only=ON; SET GLOBAL super_read_only=ON;'"
}

start_replication() {
  if replica_running; then
    log "  replication already running"
    return
  fi
  local file pos pw
  if [ -f /tmp/hodoopforge-replica.pos ]; then
    read -r file pos < /tmp/hodoopforge-replica.pos
  fi
  if [ -z "${file:-}" ] || [ -z "${pos:-}" ]; then
    file=$(docker exec "$PRIMARY" bash -c "mysql -N -e 'show master status'" | awk '{print $1}')
    pos=$(docker exec "$PRIMARY" bash -c "mysql -N -e 'show master status'" | awk '{print $2}')
  fi
  pw=$(docker exec "$PRIMARY" bash -c "grep '^MYSQL_REPL_PASSWORD=' $ENV_FILE | cut -d= -f2")
  docker exec "$REPLICA" bash -c "mysql -e \"STOP REPLICA; RESET REPLICA ALL; CHANGE REPLICATION SOURCE TO SOURCE_HOST='$PRIMARY_HOST', SOURCE_USER='repl', SOURCE_PASSWORD='$pw', SOURCE_LOG_FILE='$file', SOURCE_LOG_POS=$pos, SOURCE_CONNECT_RETRY=10, SOURCE_RETRY_COUNT=0; START REPLICA;\""
}

status() {
  log "== primary =="
  docker exec "$PRIMARY" bash -c "mysql -N -e 'select @@server_id,@@read_only,@@gtid_mode; show master status;'" | head -4
  log "== replica =="
  docker exec "$REPLICA" bash -c "mysql -N -e 'select @@server_id,@@read_only,@@super_read_only;'"
  docker exec "$REPLICA" mysql -e "SHOW REPLICA STATUS\G" 2>/dev/null \
    | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_Error" || true
}

case "${1:-install}" in
  install)
    ensure_replica_packages
    ensure_replica_config
    ensure_repl_user
    seed_replica
    start_replication
    status
    ;;
  status) status ;;
  *) echo "usage: $0 {install|status}" >&2; exit 2 ;;
esac
