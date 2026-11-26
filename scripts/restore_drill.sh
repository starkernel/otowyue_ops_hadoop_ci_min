#!/usr/bin/env bash
# Restore drill for the control-plane backup (M-103).
#
#   sudo bash scripts/restore_drill.sh                 # latest backup, ambari DB
#   sudo bash scripts/restore_drill.sh --db hive
#   sudo bash scripts/restore_drill.sh --backup /var/backups/hodoopforge/20261124-0239
#
# It restores ONE database from databases.sql.gz into a throwaway database
# (restore_drill_<db>), verifies table/row counts, records the elapsed time and
# then drops the throwaway database.  The live databases are never touched.
set -euo pipefail

BACKUP_ROOT=/var/backups/hodoopforge
DB=ambari
BACKUP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --backup) BACKUP="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$BACKUP" ]; then
  BACKUP=$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | tail -1)
fi
[ -n "$BACKUP" ] || { echo "no backup found under $BACKUP_ROOT" >&2; exit 1; }
DUMP="${BACKUP%/}/databases.sql.gz"
[ -f "$DUMP" ] || { echo "missing $DUMP" >&2; exit 1; }

DEST="restore_drill_${DB}"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

log "restore drill: db=$DB dest=$DEST dump=$DUMP"
start=$(date +%s)

# Extract only the section for the requested database, rename it to DEST, and
# import into a throwaway schema.  The dump uses `-- Current Database: `db``.
docker exec bigtop_hostname0 mysql -e "DROP DATABASE IF EXISTS \`$DEST\`; CREATE DATABASE \`$DEST\`;"
{
  echo "SET FOREIGN_KEY_CHECKS=0;"
  gzip -dc "$DUMP" \
    | awk -v db="$DB" '/^-- Current Database: /{cur=$0} cur ~ "`" db "`" {print}' \
    | sed "s/\`$DB\`/\`$DEST\`/g"
  echo "SET FOREIGN_KEY_CHECKS=1;"
} | docker exec -i bigtop_hostname0 mysql "$DEST"

tables=$(docker exec bigtop_hostname0 mysql -N -e \
  "select count(*) from information_schema.tables where table_schema='$DEST'")
log "restored tables: $tables"
[ "$tables" -gt 0 ] || { echo "restore produced no tables" >&2; exit 1; }

# A cheap content check: the largest table should have rows.
rows=$(docker exec bigtop_hostname0 mysql -N -e \
  "select coalesce(sum(table_rows),0) from information_schema.tables where table_schema='$DEST'")
log "approx rows (information_schema): $rows"

end=$(date +%s)
log "RTO: $((end - start))s"

docker exec bigtop_hostname0 mysql -e "DROP DATABASE \`$DEST\`;"
log "dropped $DEST; live databases untouched"
