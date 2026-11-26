#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

set -ex

# ── Yum repo ───────────────────────────────────────────────────────────────────
tee /etc/yum.repos.d/ambari.repo << 'EOF'
[ambari]
name=Ambari 3.1.0 + Bigtop 3.5.0 Local Repository
baseurl=http://bigtop_hostname0
gpgcheck=0
enabled=1
EOF

dnf clean all
dnf makecache

# ── Enable PowerTools/CRB repo for devel packages ─────────────────────────────
dnf install -y 'dnf-command(config-manager)' 2>/dev/null || true
dnf config-manager --set-enabled powertools 2>/dev/null || \
  dnf config-manager --set-enabled crb 2>/dev/null || true

if [ -z "$1" ]; then
  echo "Usage: $0 <agent-fqdn>"
  exit 1
fi

AMBARI_AGENT_HOSTNAME="$1"
hostname "${AMBARI_AGENT_HOSTNAME}"

# ── Java ───────────────────────────────────────────────────────────────────────
dnf install -y java-17-openjdk-devel java-1.8.0-openjdk-devel

# ── Ambari Agent ───────────────────────────────────────────────────────────────
dnf install -y python3 python3-distro
dnf install -y ambari-agent

# Point agent to server
sed -i "s/hostname=.*/hostname=bigtop-hostname0.bigtop.apache.org/" \
  /etc/ambari-agent/conf/ambari-agent.ini

# ── python -> python3 symlink (ranger_credential_helper.py 需要 /usr/bin/python) ─
# 必须保证 /usr/bin/python 指向真实解释器；缺失或悬空都要修复，否则组件
# Start/Restart 会因 "bad interpreter: No such file or directory" 失败
# （典型：HBASE_MASTER 的 Ranger 凭据步骤）。
if [ ! -e /usr/bin/python ]; then
  ln -sf /usr/bin/python3 /usr/bin/python
  echo "[INFO] created /usr/bin/python -> $(readlink /usr/bin/python)"
fi


# ── Fix ranger script permissions (other users need execute) ──────────────────
for d in ranger-admin ranger-usersync ranger-tagsync ranger-kms; do
  [ -d /usr/lib/${d} ] && find /usr/lib/${d} -name '*.sh' -exec chmod a+x {} \; 2>/dev/null || true
done

# ── Fix bigtop-select: add missing packages to leaves dict ────────────────────
# hadoop-hdfs-dfsrouter (HDFS Federation Router) 不在默认 leaves 里
sed -i 's/"hadoop-hdfs-namenode": "hadoop-hdfs",/"hadoop-hdfs-namenode": "hadoop-hdfs",\n           "hadoop-hdfs-dfsrouter": "hadoop-hdfs",/' \
  /usr/lib/bigtop-select/distro-select 2>/dev/null || true

# ── Disable credential store in ambari-agent (no jceks support) ───────────────
sed -i 's/if credential_store_enabled and command_name != self.COMMAND_NAME_STATUS:/if False and command_name != self.COMMAND_NAME_STATUS:  # disabled: no jceks support/' \
  /usr/lib/ambari-agent/lib/ambari_agent/CustomServiceOrchestrator.py || true

# ── Fix bigtop-select directory structure ─────────────────────────────────────
# distro-select 期望 /usr/bigtop/3.5.0/usr/lib/<pkg> 存在，但 RPM 装到 /usr/lib/<pkg>
# 需要建软链接，否则 after-INSTALL hook 执行 distro-select set 时报 "Invalid version"
mkdir -p /usr/bigtop/3.5.0/usr/lib
for pkg in hadoop hadoop-hdfs hadoop-yarn hadoop-mapreduce hbase hive hive-hcatalog \
           zookeeper kafka spark tez ranger ranger-admin ranger-kms ranger-usersync \
           ranger-tagsync flink solr zeppelin livy phoenix; do
  [ -d /usr/lib/${pkg} ] && ln -sfn /usr/lib/${pkg} /usr/bigtop/3.5.0/usr/lib/${pkg}
done
# hive-client 是 distro-select 用的别名
[ -d /usr/lib/hive ] && ln -sfn /usr/lib/hive /usr/bigtop/3.5.0/usr/lib/hive-client
# 所有 ranger plugin 也需要链接
for pkg in $(ls /usr/lib/ | grep ranger); do
  ln -sfn /usr/lib/${pkg} /usr/bigtop/3.5.0/usr/lib/${pkg} 2>/dev/null || true
done
# /usr/bin 下的命令需要是软链接而非真实文件，否则 distro-select 报错
for cmd in hbase hadoop hdfs yarn mapred beeline hive hcat spark-shell spark-submit pyspark; do
  [ -f /usr/bin/${cmd} ] && [ ! -L /usr/bin/${cmd} ] && rm -f /usr/bin/${cmd}
done
# mysql-connector 复制到 hive lib（如果 hive 已安装）
[ -d /usr/lib/hive/lib ] && \
  cp -f /usr/share/java/mysql-connector-java.jar /usr/lib/hive/lib/ 2>/dev/null || true

# ── Fix distro-select command symlink paths ────────────────────────────────────
# 默认路径 hadoop-hdfs-client/../../bin/hdfs 解析为不存在的路径，修正为正确路径
sed -i \
  -e 's|"hdfs" : "hadoop-hdfs-client/../../bin/hdfs"|"hdfs" : "hadoop-hdfs-client/bin/hdfs"|' \
  -e 's|"hadoop" : "hadoop-client/../../bin/hadoop"|"hadoop" : "hadoop-client/bin/hadoop"|' \
  -e 's|"yarn" : "hadoop-yarn-client/../../bin/yarn"|"yarn" : "hadoop-yarn-client/bin/yarn"|' \
  -e 's|"mapred" : "hadoop-mapreduce-client/../../bin/mapred"|"mapred" : "hadoop-mapreduce-client/bin/mapred"|' \
  -e 's|"beeline" : "hive-client/../../bin/beeline"|"beeline" : "hive-client/bin/beeline"|' \
  -e 's|"hive" : "hive-client/../../bin/hive"|"hive" : "hive-client/bin/hive"|' \
  -e 's|"hcat" : "hive-webhcat/../../bin/hcat"|"hcat" : "hive-webhcat/bin/hcat"|' \
  -e 's|"spark-shell" : "spark-client/../../bin/spark-shell"|"spark-shell" : "spark-client/bin/spark-shell"|' \
  -e 's|"spark-submit" : "spark-client/../../bin/spark-submit"|"spark-submit" : "spark-client/bin/spark-submit"|' \
  -e 's|"pyspark" : "spark-client/../../bin/pyspark"|"pyspark" : "spark-client/bin/pyspark"|' \
  /usr/lib/bigtop-select/distro-select 2>/dev/null || true

# ── Fix hadoop command paths ───────────────────────────────────────────────────
# hdfs/hadoop/yarn/mapred 需要直接指向实际二进制，并且 libexec 要在 /usr/libexec/ 下
ln -sfn /usr/lib/hadoop-hdfs/bin/hdfs /usr/bin/hdfs 2>/dev/null || true
ln -sfn /usr/lib/hadoop/bin/hadoop /usr/bin/hadoop 2>/dev/null || true
ln -sfn /usr/lib/hadoop-yarn/bin/yarn /usr/bin/yarn 2>/dev/null || true
ln -sfn /usr/lib/hadoop-mapreduce/bin/mapred /usr/bin/mapred 2>/dev/null || true
for f in /usr/lib/hadoop/libexec/*; do
  ln -sfn $f /usr/libexec/$(basename $f) 2>/dev/null || true
done

# ── Chrony (time sync) — 容器内可能无硬件时钟，忽略启动失败 ──────────────────
dnf install -y chrony
systemctl enable chronyd || true
systemctl start chronyd || true

# ── 确保 PowerTools/CRB 已启用并安装编译依赖 ──────────────────────────────────
# snappy-devel 等包需要 PowerTools，DataNode/NameNode install 时会被依赖
dnf config-manager --set-enabled powertools 2>/dev/null || \
  dnf config-manager --set-enabled crb 2>/dev/null || true
dnf install -y snappy-devel lzo lzo-devel zlib-devel 2>/dev/null || true

# ── Start / restart agent ──────────────────────────────────────────────────────
AGENT_RUNNING=$(ambari-agent status 2>/dev/null | grep -c running || true)
if [ "${AGENT_RUNNING}" != "1" ]; then
  ambari-agent start
else
  ambari-agent restart
fi

# ── Cleanup puppet packages (not needed) ──────────────────────────────────────
dnf remove -y rubygem-multi_json rubygem-semantic_puppet cpp-hocon rubygem-hocon \
  rubygem-puppet-resource_api hiera leatherman ruby-facter \
  rubygem-concurrent-ruby rubygem-deep_merge puppet rubygem-httpclient \
  ruby-augeas facter yaml-cpp 2>/dev/null || true

echo "==> Ambari Agent started on ${AMBARI_AGENT_HOSTNAME}"
