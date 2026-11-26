#!/usr/bin/env bash
# Install a two-node MIT KDC for HodoopForge (Kerberos prerequisite).
#
#   sudo bash scripts/kerberos_setup_kdc.sh
#
# Realm: HODOOPFORGE.LOCAL
#   h0 172.19.0.2  primary KDC + kadmind
#   h3 172.19.0.4  replica KDC (initial DB + stash copy)
#
# This script only builds the KDC and krb5.conf.  It does NOT flip Ambari to
# security_type=KERBEROS; that is the maintenance-window step in
# docs/KERBEROS_ENABLEMENT.md.
set -euo pipefail

REALM="${KRB_REALM:-HODOOPFORGE.LOCAL}"
PRIMARY=bigtop_hostname0
REPLICA=bigtop_hostname3
NODES=(bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3)
ENV_FILE=/etc/hodoopforge/kerberos.env
KDC_CONF=/var/kerberos/krb5kdc/kdc.conf
ACL=/var/kerberos/krb5kdc/kadm5.acl

log() { printf '%s\n' "$*"; }

if docker exec "$PRIMARY" test -f "$ENV_FILE"; then
  MASTER_PW=$(docker exec "$PRIMARY" bash -c "grep '^KRB_MASTER_PASSWORD=' $ENV_FILE | cut -d= -f2")
  ADMIN_PW=$(docker exec "$PRIMARY" bash -c "grep '^KRB_ADMIN_PASSWORD=' $ENV_FILE | cut -d= -f2")
else
  MASTER_PW=$(openssl rand -hex 16)
  ADMIN_PW=$(openssl rand -hex 16)
  docker exec "$PRIMARY" bash -c "mkdir -p /etc/hodoopforge; cat > $ENV_FILE <<EOF
KRB_REALM=$REALM
KRB_MASTER_PASSWORD=$MASTER_PW
KRB_ADMIN_PASSWORD=$ADMIN_PW
EOF
chmod 600 $ENV_FILE"
fi

log "== krb5.conf on all nodes (must exist before krb5kdc starts) =="
for h in "${NODES[@]}"; do
  docker exec "$h" bash -c "cat > /etc/krb5.conf <<EOF
includedir /etc/krb5.conf.d/

[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    default_ccache_name = FILE:/tmp/krb5cc_%{uid}

[realms]
    $REALM = {
        kdc = bigtop-hostname0.bigtop.apache.org
        kdc = bigtop-hostname3.bigtop.apache.org
        admin_server = bigtop-hostname0.bigtop.apache.org
    }

[domain_realm]
    .bigtop.apache.org = $REALM
    bigtop.apache.org = $REALM
EOF
"
done

log "== kdc.conf + kadm5.acl =="
for h in "$PRIMARY" "$REPLICA"; do
  docker exec "$h" bash -c "cat > $KDC_CONF <<EOF
[libdefaults]
    dns_lookup_realm = false
    dns_lookup_kdc = false

[kdcdefaults]
    kdc_ports = 88
    kdc_tcp_ports = 88

[realms]
    $REALM = {
        acl_file = $ACL
        dict_file = /usr/share/dict/words
        admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
        supported_enctypes = aes256-cts:normal aes128-cts:normal
    }
EOF
cat > $ACL <<EOF
*/admin@$REALM *
EOF
"
done

log "== create realm on $PRIMARY =="
docker exec "$PRIMARY" bash -c "
  if [ ! -f /var/kerberos/krb5kdc/principal ]; then
    kdb5_util create -s -r $REALM -P '$MASTER_PW'
  fi
  kadmin.local -r $REALM -q 'addprinc -pw $ADMIN_PW admin/admin' 2>/dev/null || true
  kadmin.local -r $REALM -q 'addprinc -randkey kadmin/admin' 2>/dev/null || true
  kadmin.local -r $REALM -q 'addprinc -randkey kadmin/changepw' 2>/dev/null || true
  for h in bigtop-hostname0.bigtop.apache.org bigtop-hostname3.bigtop.apache.org; do
    kadmin.local -r $REALM -q \"addprinc -randkey host/\$h\" 2>/dev/null || true
  done
  systemctl enable krb5kdc >/dev/null 2>&1 || true
  systemctl restart krb5kdc || true
  systemctl enable kadmin >/dev/null 2>&1 || true
  systemctl restart kadmin || true
"

log "== seed $REPLICA (DB + master stash) =="
docker exec "$PRIMARY" bash -c "kdb5_util dump /tmp/${REALM}.dump"
docker cp "$PRIMARY:/tmp/${REALM}.dump" "/tmp/${REALM}.dump"
docker cp "/tmp/${REALM}.dump" "$REPLICA:/tmp/${REALM}.dump"
docker cp "$PRIMARY:/var/kerberos/krb5kdc/.k5.${REALM}" "/tmp/.k5.${REALM}"
docker cp "/tmp/.k5.${REALM}" "$REPLICA:/var/kerberos/krb5kdc/.k5.${REALM}"
docker exec "$REPLICA" bash -c "
  chmod 600 /var/kerberos/krb5kdc/.k5.${REALM}
  if [ ! -f /var/kerberos/krb5kdc/principal ]; then
    kdb5_util load -r $REALM /tmp/${REALM}.dump
  fi
  systemctl enable krb5kdc >/dev/null 2>&1 || true
  systemctl restart krb5kdc || true
"

log "== verify =="
for h in "$PRIMARY" "$REPLICA"; do
  printf '  %-18s ' "$h"
  docker exec "$h" bash -c "printf '%s\n' '$ADMIN_PW' | kinit admin/admin >/dev/null 2>&1 && echo kinit-ok && kdestroy || echo kinit-FAILED"
done
log "KDC ready: realm=$REALM primary=$PRIMARY replica=$REPLICA"
log "credentials: $ENV_FILE (root 0600)"
