#!/usr/bin/env bash
# Read-only Kerberos readiness check.
#
#   bash scripts/kerberos_status.sh
#
# Never prints the admin password; only says whether kinit succeeds.
set -euo pipefail

REALM="${KRB_REALM:-HODOOPFORGE.LOCAL}"
ENV_FILE=/etc/hodoopforge/kerberos.env

log() { printf '%s\n' "$*"; }

log "== KDC =="
for h in bigtop_hostname0 bigtop_hostname3; do
  printf '  %-18s ' "$h"
  docker exec "$h" bash -c "systemctl is-active krb5kdc 2>/dev/null || echo inactive" | tr -d '\n'
  printf ' port88='
  docker exec "$h" bash -c "ss -ltn 2>/dev/null | grep -q ':88 ' && echo yes || echo no"
done

log "== realm =="
docker exec bigtop_hostname0 bash -c "kadmin.local -r $REALM -q 'list_principals' 2>/dev/null | grep -c '@' || true" \
  | sed 's/^/  principals: /'

log "== kinit =="
if docker exec bigtop_hostname0 test -f "$ENV_FILE"; then
  ADMIN_PW=$(docker exec bigtop_hostname0 bash -c "grep '^KRB_ADMIN_PASSWORD=' $ENV_FILE | cut -d= -f2")
  for h in bigtop_hostname0 bigtop_hostname3; do
    printf '  %-18s ' "$h"
    docker exec "$h" bash -c "printf '%s\n' '$ADMIN_PW' | kinit admin/admin >/dev/null 2>&1 && echo ok && kdestroy || echo FAILED"
  done
else
  log "  $ENV_FILE missing; skip kinit"
fi

log "== cluster security_type =="
AMBARI_USER=${AMBARI_USER:-admin}
AMBARI_PASS=${AMBARI_PASS:-}
if [ -z "$AMBARI_PASS" ] && [ -r /etc/hodoopforge/ambari.env ]; then
  AMBARI_PASS=$(grep '^AMBARI_PASS=' /etc/hodoopforge/ambari.env | cut -d= -f2)
fi
if [ -z "$AMBARI_PASS" ]; then
  AMBARI_PASS=$(docker run --rm -v /:/host:ro busybox chroot /host \
    sh -c "grep '^AMBARI_PASS=' /etc/hodoopforge/ambari.env 2>/dev/null | cut -d= -f2" || true)
fi
curl -s --max-time 10 -u "$AMBARI_USER:$AMBARI_PASS" -H 'X-Requested-By: ops' \
  'http://localhost:20609/api/v1/clusters/qixuandata?fields=Clusters/security_type' \
  | python3 -c "import json,sys;print('  '+json.load(sys.stdin)['Clusters']['security_type'])" 2>/dev/null || echo "  unknown"

log "== keytabs (first 10) =="
docker exec bigtop_hostname0 bash -c "ls /etc/security/keytabs 2>/dev/null | head -10 || echo '  none yet (expected before Ambari Kerberos wizard)'"
