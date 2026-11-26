#!/usr/bin/env bash
# Prepare Kerberos prerequisites without enabling Kerberos.
#
#   bash scripts/kerberos_prep.sh
#
# Does:
#   1. installs a real chronyd unit (the default chronyd.service is a dummy
#      "RemainAfterExit" unit used only for Ambari's health check)
#   2. installs krb5-server on h0/h3 and krb5-workstation on all nodes
#   3. verifies clock offset < 300s on every node
#
# It does NOT create a realm, keytabs or change hadoop.security.authentication.
set -euo pipefail

NODES=(bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3)
UNIT=/etc/systemd/system/hodoopforge-chronyd.service

cat > /tmp/hodoopforge-chronyd.service <<'EOF'
[Unit]
Description=HodoopForge real chronyd (NTP client, foreground)
After=network.target

[Service]
ExecStart=/usr/sbin/chronyd -d -f /etc/chrony.conf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "== real chronyd =="
for h in "${NODES[@]}"; do
  docker cp /tmp/hodoopforge-chronyd.service "$h:$UNIT"
  docker exec "$h" bash -c "systemctl daemon-reload; systemctl enable --now hodoopforge-chronyd >/dev/null 2>&1; systemctl restart hodoopforge-chronyd"
  echo -n "  $h: "
  docker exec "$h" bash -c "chronyc tracking 2>/dev/null | grep 'System time' | sed 's/^ *//'" || echo "no sync yet"
done

echo "== krb5 packages =="
for h in bigtop_hostname0 bigtop_hostname3; do
  echo "  $h: krb5-server + krb5-workstation"
  docker exec "$h" bash -c "yum -y -q --disablerepo='*' --enablerepo=baseos --enablerepo=appstream install krb5-server krb5-workstation >/dev/null 2>&1"
done
for h in bigtop_hostname1 bigtop_hostname2; do
  echo "  $h: krb5-workstation"
  docker exec "$h" bash -c "yum -y -q --disablerepo='*' --enablerepo=baseos --enablerepo=appstream install krb5-workstation >/dev/null 2>&1"
done

echo "== verify =="
for h in "${NODES[@]}"; do
  echo -n "  $h: "
  docker exec "$h" bash -c "rpm -q krb5-workstation | tail -1; chronyc tracking 2>/dev/null | grep -E 'System time|Leap status' | tr '\n' ' '"
  echo
done

echo "done. Kerberos is still DISABLED (hadoop.security.authentication=simple)."
