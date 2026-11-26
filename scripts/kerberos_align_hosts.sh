#!/usr/bin/env bash
# Align Kerberos principals/keytabs with both hostname forms used in this lab.
#
# Why: containers answer to two names:
#   bigtop-hostname1.bigtop.apache.org     (Ambari / FQDN)
#   bigtop_hostname1.ambari3_hodoopforge   (Docker DNS canonical name)
# Hadoop's _HOST substitution and GSS hostname canonicalization can pick either
# one.  Instead of fighting Ambari, create both principals and put both into the
# service keytab, and disable krb5 hostname canonicalization.
#
#   sudo bash scripts/kerberos_align_hosts.sh
#
# This script is safe while the cluster runs in SIMPLE mode: it only creates
# principals and keytab files; it does not restart services.
set -euo pipefail

REALM="${KRB_REALM:-HODOOPFORGE.LOCAL}"
PRIMARY=bigtop_hostname0
HOSTS=(bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3)
declare -A SERVICES=(
  [bigtop_hostname0]="nn jn HTTP"
  [bigtop_hostname1]="dn jn HTTP"
  [bigtop_hostname2]="dn HTTP"
  [bigtop_hostname3]="nn dn jn HTTP"
)
declare -A USERS=( [nn]=hdfs [dn]=hdfs [jn]=hdfs [HTTP]=hdfs )

log() { printf '%s\n' "$*"; }

log "== disable krb5 hostname canonicalization on all nodes =="
for h in "${HOSTS[@]}"; do
  docker exec "$h" bash -c "python3 - <<'PY'
p='/etc/krb5.conf'
s=open(p).read()
if 'dns_canonicalize_hostname' not in s:
    s=s.replace('    rdns = false', '    rdns = false\n    dns_canonicalize_hostname = false')
if 'dns_canonicalize_hostname' not in s:
    s=s.replace('[libdefaults]', '[libdefaults]\n    dns_canonicalize_hostname = false')
open(p,'w').write(s)
PY
grep -E 'dns_canonicalize_hostname|rdns' /etc/krb5.conf | head -3"
done

log "== create dual principals and keytabs =="
for h in "${HOSTS[@]}"; do
  fqdn="bigtop-hostname${h#bigtop_hostname}.bigtop.apache.org"
  alt="${h}.ambari3_hodoopforge"
  for svc in ${SERVICES[$h]}; do
    user="${USERS[$svc]}"
    tmp="/tmp/${svc}-${h}.keytab"
    docker exec "$PRIMARY" bash -c "
      set -e
      for name in '$svc/$fqdn' '$svc/$alt'; do
        kadmin.local -r $REALM -q \"addprinc -randkey \$name@$REALM\" 2>/dev/null || true
      done
      rm -f $tmp
      kadmin.local -r $REALM -q 'ktadd -k $tmp $svc/$fqdn@$REALM' >/dev/null
      kadmin.local -r $REALM -q 'ktadd -k $tmp $svc/$alt@$REALM' >/dev/null
      chmod 600 $tmp
    "
    docker cp "$PRIMARY:$tmp" "/tmp/${svc}-${h}.keytab"
    docker cp "/tmp/${svc}-${h}.keytab" "$h:/etc/security/keytabs/${svc}.service.keytab"
    docker exec "$h" bash -c "chown $user:hadoop /etc/security/keytabs/${svc}.service.keytab; chmod 400 /etc/security/keytabs/${svc}.service.keytab"
    log "  $h ${svc}: $fqdn + $alt"
  done
done

log "== verify =="
for h in "${HOSTS[@]}"; do
  log "  $h:"
  docker exec "$h" bash -c "for f in /etc/security/keytabs/{nn,dn,jn,HTTP}.service.keytab; do [ -f \$f ] && klist -kte \$f 2>/dev/null | grep '@' | awk '{print \"    \" \$5}'; done | sort -u"
done
log "done. Re-run this after Ambari rewrites keytabs; then test HDFS before other services."
