#!/usr/bin/env bash
# HDFS-only Kerberos enable/rollback (manual, Ambari security_type stays NONE).
#
#   bash scripts/kerberos_hdfs_enable.sh enable
#   bash scripts/kerberos_hdfs_enable.sh status
#   bash scripts/kerberos_hdfs_enable.sh rollback
#
# Why this script exists
# ----------------------
# The 2026-11-24/25 attempts showed that HDFS RPC Kerberos works once:
#   1. stale federation keys (dfs.*ns-fed*) are removed from hdfs-site.xml;
#   2. NameNode/JournalNode keep `_HOST` (Java resolves the FQDN here);
#   3. DataNode uses an explicit FQDN principal, because the secure DataNode
#      (jsvc/root -> hdfs) may resolve `_HOST` to the Docker DNS alias and the
#      NameNode then rejects it as "only accessible by dn/<fqdn>@REALM";
#   4. HTTP/web auth stays `simple` (HDFS RPC is Kerberos, web UI is not);
#   5. ZKFC is started after both NameNodes, otherwise both stay standby.
#
# This is a *manual validation* path.  Ambari still reports the HDFS service as
# INSTALLED and must not be asked to start HDFS while this mode is active, or
# it will rewrite /etc/hadoop/conf back to simple.
set -euo pipefail

REALM="${KRB_REALM:-HODOOPFORGE.LOCAL}"
CONF=/etc/hadoop/conf
KEYTABS=/etc/security/keytabs
HOSTS=(0 1 2 3)

log() { printf '%s\n' "$*"; }

apply_host() {
  local h=$1
  docker exec -e HOST_ID="$h" -e KRB_REALM="$REALM" "bigtop_hostname$h" python3 - <<'PY'
import os
import re

h = os.environ['HOST_ID']
realm = os.environ['KRB_REALM']
fqdn = 'bigtop-hostname%s.bigtop.apache.org' % h
conf = '/etc/hadoop/conf'

def set_props(path, values, remove=()):
    with open(path) as fh:
        text = fh.read()
    for name in list(values) + list(remove):
        text = re.sub(
            r'\s*<property>\s*<name>' + re.escape(name) + r'</name>.*?</property>',
            '', text, flags=re.S)
    # Drop stale federation properties; this was the hidden cause of
    # "Configuration has multiple addresses that match local node's address".
    text = re.sub(
        r'\s*<property>\s*<name>[^<]*ns-fed[^<]*</name>.*?</property>',
        '', text, flags=re.S)
    text = re.sub(
        r'(<name>dfs\.nameservices</name>\s*<value>)[^<]*(</value>)',
        r'\g<1>qixuandata\g<2>', text)
    add = ''.join(
        '  <property><name>%s</name><value>%s</value></property>\n' % (k, v)
        for k, v in values.items())
    text = text.replace('</configuration>', add + '</configuration>')
    with open(path, 'w') as fh:
        fh.write(text)

# Keep the Ambari-generated simple config for rollback.
for name in ('core-site.xml', 'hdfs-site.xml'):
    src = os.path.join(conf, name)
    backup = src + '.simple.bak'
    if not os.path.exists(backup):
        with open(src) as s, open(backup, 'w') as d:
            d.write(s.read())

core = {
    'hadoop.security.authentication': 'kerberos',
    'hadoop.security.authorization': 'true',
    'hadoop.http.authentication.type': 'simple',
    'hadoop.http.authentication.simple.anonymous.allowed': 'true',
}
set_props(os.path.join(conf, 'core-site.xml'), core, remove=(
    'hadoop.http.authentication.kerberos.principal',
    'hadoop.http.authentication.kerberos.keytab',
))

hdfs = {
    # NN/JN must stay _HOST: the NameNode builds one client principal per
    # JournalNode/peer NameNode from the same key.
    'dfs.namenode.kerberos.principal': 'nn/_HOST@' + realm,
    'dfs.namenode.keytab.file': KEYTABS + '/nn.service.keytab',
    'dfs.namenode.kerberos.principal.pattern': 'nn/*@' + realm,
    'dfs.journalnode.kerberos.principal': 'jn/_HOST@' + realm,
    'dfs.journalnode.keytab.file': KEYTABS + '/jn.service.keytab',
    # DN must be explicit: the secure DataNode jsvc child resolves _HOST to
    # the Docker DNS alias, while the NameNode expects the FQDN principal.
    'dfs.datanode.kerberos.principal': 'dn/%s@%s' % (fqdn, realm),
    'dfs.datanode.keytab.file': KEYTABS + '/dn.service.keytab',
}
set_props(os.path.join(conf, 'hdfs-site.xml'), hdfs, remove=(
    'dfs.web.authentication.kerberos.principal',
    'dfs.web.authentication.kerberos.keytab',
    'dfs.web.authentication.keytab.file',
    'dfs.web.authentication.principal',
))
print('configured %s (nn/jn=_HOST, dn=%s)' % (fqdn, fqdn))
PY
}

stop_all() {
  local h
  for h in 0 3; do
    docker exec "bigtop_hostname$h" bash -c \
      "pkill -KILL -f '[p]roc_namenode' || true; pkill -KILL -f '[p]roc_zkfc' || true; \
       rm -f /var/run/hadoop/hdfs/*namenode* /var/run/hadoop/hdfs/*zkfc*"
  done
  for h in 0 1 3; do
    docker exec "bigtop_hostname$h" bash -c \
      "pkill -KILL -f '[p]roc_journalnode' || true; rm -f /var/run/hadoop/hdfs/*journalnode*"
  done
  for h in 1 2 3; do
    docker exec "bigtop_hostname$h" bash -c \
      "pkill -KILL -f '[p]roc_datanode' || true; rm -f /var/run/hadoop/hdfs/*datanode*"
  done
  sleep 5
}

start_all() {
  local h
  for h in 0 1 3; do
    docker exec "bigtop_hostname$h" bash -c \
      "su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR=$CONF; hdfs --daemon start journalnode' >/dev/null 2>&1"
  done
  sleep 15
  for h in 0 3; do
    docker exec "bigtop_hostname$h" bash -c \
      "su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR=$CONF; hdfs --daemon start namenode' >/dev/null 2>&1"
  done
  sleep 30
  for h in 1 2 3; do
    docker exec -u root "bigtop_hostname$h" bash -c \
      "export HADOOP_CONF_DIR=$CONF HDFS_DATANODE_SECURE_USER=hdfs; /usr/bin/hdfs --daemon start datanode >/dev/null 2>&1"
  done
  sleep 20
  for h in 0 3; do
    docker exec "bigtop_hostname$h" bash -c \
      "su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR=$CONF; hdfs --daemon start zkfc' >/dev/null 2>&1"
  done
  sleep 15
}

kinit_hdfs() {
  local h=$1
  docker exec "bigtop_hostname$h" bash -c "
    su -s /bin/bash hdfs -c '
      export HADOOP_CONF_DIR=$CONF
      if [ -f $KEYTABS/hdfs.headless.keytab ]; then
        kinit -kt $KEYTABS/hdfs.headless.keytab hdfs-qixuandata@$REALM
      else
        kinit -kt $KEYTABS/nn.service.keytab nn/bigtop-hostname0.bigtop.apache.org@$REALM
      fi
    '"
}

verify() {
  local h=0
  kinit_hdfs "$h"
  docker exec "bigtop_hostname$h" bash -c "
    su -s /bin/bash hdfs -c '
      export HADOOP_CONF_DIR=$CONF
      hdfs haadmin -getAllServiceState
      hdfs dfsadmin -report 2>/dev/null | grep -E \"^Live datanodes|^Name:|^Missing blocks\"
      kdestroy
    '" 2>&1 | tail -12
}

case "${1:-status}" in
  enable)
    log "== apply explicit-principal Kerberos config =="
    for h in "${HOSTS[@]}"; do apply_host "$h"; done
    log "== stop HDFS =="
    stop_all
    log "== start JN -> NN -> DN -> ZKFC =="
    start_all
    log "== verify =="
    verify
    ;;
  status)
    for h in 0 3; do
      printf 'h%s 8020: ' "$h"
      docker exec "bigtop_hostname$h" bash -c "ss -ltn | grep -q 8020 && echo ok || echo no"
    done
    for h in 1 2 3; do
      printf 'h%s 1019: ' "$h"
      docker exec "bigtop_hostname$h" bash -c "ss -ltn | grep -q 1019 && echo ok || echo no"
    done
    verify
    ;;
  rollback)
    log "== restore simple config =="
    for h in "${HOSTS[@]}"; do
      docker exec "bigtop_hostname$h" bash -c \
        "cp -f $CONF/core-site.xml.simple.bak $CONF/core-site.xml 2>/dev/null || true; \
         cp -f $CONF/hdfs-site.xml.simple.bak $CONF/hdfs-site.xml 2>/dev/null || true"
    done
    stop_all
    start_all
    log "== verify (simple) =="
    docker exec bigtop_hostname0 bash -c \
      "su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR=$CONF; \
       hdfs haadmin -getAllServiceState; \
       hdfs dfsadmin -report 2>/dev/null | grep -E \"^Live datanodes|^Missing blocks\"'" 2>&1 | tail -6
    ;;
  *)
    echo "usage: $0 {enable|status|rollback}" >&2
    exit 2
    ;;
esac
