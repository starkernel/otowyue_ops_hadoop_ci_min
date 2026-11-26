#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

# Inject Bigtop 3.5.0 stack definition into Ambari 3.1.0
# This script runs inside bigtop_hostname0 after ambari-server is installed

set -ex

STACKS_DIR=/var/lib/ambari-server/resources/stacks
STACK_HOME=${STACKS_DIR}/BIGTOP/3.5.0

# ── Locate existing BIGTOP stack to inherit from（动态取最新版本）────────────
PARENT_STACK=$(ls "${STACKS_DIR}/BIGTOP/" | grep -v '3.5.0' | sort -V | tail -1)
# >>> 动态检测父Stack版本：排除3.5.0自身，按版本号排序取最新版

if [ -z "${PARENT_STACK}" ]; then
  echo "ERROR: No existing BIGTOP stack found under ${STACKS_DIR}/BIGTOP/"
  # >>> 安全检查：若找不到父Stack则报错退出，避免创建无效Stack
  ls "${STACKS_DIR}/" || true
  exit 1
fi

echo "==> Found parent stack BIGTOP/${PARENT_STACK}, creating BIGTOP/3.5.0..."

# Copy parent stack as base
cp -r "${STACKS_DIR}/BIGTOP/${PARENT_STACK}" "${STACK_HOME}"
# >>> 复制父Stack目录作为基础，继承所有服务定义、脚本、配置模板

# ── Update stack metainfo.xml ─────────────────────────────────────────────────
# 注意：heredoc 内不能有 shell 注释（# 开头），否则会原文写入 XML 导致解析失败
cat > "${STACK_HOME}/metainfo.xml" << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <versions>
    <active>true</active>
  </versions>
  <extends>PARENT_VERSION</extends>
</metainfo>
EOF
# 用 sed 将占位符 PARENT_VERSION 替换为实际父版本号，建立继承关系
sed -i "s/PARENT_VERSION/${PARENT_STACK}/" "${STACK_HOME}/metainfo.xml"

# ── repos: define where to find packages ─────────────────────────────────────
# 告知 Ambari 从本地 Nginx 仓库下载组件包
# 注意：heredoc 内不能有 shell 注释，否则会原文写入 XML 导致解析失败
mkdir -p "${STACK_HOME}/repos"
cat > "${STACK_HOME}/repos/repoinfo.xml" << 'EOF'
<?xml version="1.0"?>
<reposinfo>
  <latest>http://bigtop_hostname0/repodata/repomd.xml</latest>
  <os family="redhat8">
    <repo>
      <baseurl>http://bigtop_hostname0</baseurl>
      <repoid>BIGTOP-3.5.0</repoid>
      <reponame>Bigtop 3.5.0</reponame>
      <unique>true</unique>
    </repo>
  </os>
</reposinfo>
EOF

# ── Update component versions in each service metainfo.xml ───────────────────
update_service_version() {
  # 通用版本更新函数：更新指定服务 metainfo.xml 中的版本号
  local service=$1
  local pkg=$2
  local version=$3
  local svc_dir="${STACK_HOME}/services/${service}"

  [ -d "${svc_dir}" ] || return 0

  # Update version tags in metainfo.xml
  sed -i "s|<version>.*</version>|<version>${version}</version>|g" \
    "${svc_dir}/metainfo.xml" 2>/dev/null || true

  # Update package name/version in metainfo.xml
  sed -i "s|<name>${pkg}-[0-9].*</name>|<name>${pkg}-${version}</name>|g" \
    "${svc_dir}/metainfo.xml" 2>/dev/null || true
}

# Component version map matching bigtoprpm packages (Bigtop 3.5.0)
update_service_version HDFS       hadoop    3.3.6
update_service_version YARN       hadoop    3.3.6
update_service_version MAPREDUCE2 hadoop    3.3.6
update_service_version HBASE      hbase     2.6.2
update_service_version HIVE       hive      4.0.1
update_service_version ZOOKEEPER  zookeeper 3.8.4
update_service_version KAFKA      kafka     3.4.1
update_service_version SPARK2     spark     3.5.6
update_service_version SPARK3     spark     3.5.6
update_service_version RANGER     ranger    2.7.0
update_service_version TEZ        tez       0.10.4
update_service_version FLINK      flink     1.20.1
update_service_version SOLR       solr      8.11.4
update_service_version ZEPPELIN   zeppelin  0.11.2
update_service_version LIVY       livy      0.8.0
update_service_version PHOENIX    phoenix   5.2.1

# ── Patch package version strings in all service metainfo.xml files ──────────
# Replace old bigtop version references with Bigtop 3.5.0 component versions
find "${STACK_HOME}/services" -name "metainfo.xml" | while read f; do
  # Hadoop ecosystem
  sed -i 's/hadoop-3\.[0-9]\+\.[0-9]\+/hadoop-3.3.6/g' "$f"
  sed -i 's/hbase-[0-9]\+\.[0-9]\+\.[0-9]\+/hbase-2.6.2/g' "$f"
  sed -i 's/hive-[0-9]\+\.[0-9]\+\.[0-9]\+/hive-4.0.1/g' "$f"
  sed -i 's/zookeeper-[0-9]\+\.[0-9]\+\.[0-9]\+/zookeeper-3.8.4/g' "$f"
  sed -i 's/kafka-[0-9]\+\.[0-9]\+\.[0-9]\+/kafka-3.4.1/g' "$f"
  sed -i 's/spark-[0-9]\+\.[0-9]\+\.[0-9]\+/spark-3.5.6/g' "$f"
  sed -i 's/ranger-[0-9]\+\.[0-9]\+\.[0-9]\+/ranger-2.7.0/g' "$f"
  sed -i 's/tez-[0-9]\+\.[0-9]\+\.[0-9]\+/tez-0.10.4/g' "$f"
  sed -i 's/flink-[0-9]\+\.[0-9]\+\.[0-9]\+/flink-1.20.1/g' "$f"
  sed -i 's/solr-[0-9]\+\.[0-9]\+\.[0-9]\+/solr-8.11.4/g' "$f"
  sed -i 's/zeppelin-[0-9]\+\.[0-9]\+\.[0-9]\+/zeppelin-0.11.2/g' "$f"
  sed -i 's/livy-[0-9]\+\.[0-9]\+\.[0-9]\+/livy-0.8.0/g' "$f"
  sed -i 's/phoenix-[0-9]\+\.[0-9]\+\.[0-9]\+/phoenix-5.2.1/g' "$f"
done

# ── Update stack version in Ambari DB ────────────────────────────────────────
# 向 Ambari 数据库注册 BIGTOP 3.5.0 Stack，INSERT IGNORE 避免重复插入报错
# 注意：heredoc 内不能有 shell 注释，否则会被当作 SQL 发送导致报错
mysql -uambari -pambari ambari << 'EOSQL' 2>/dev/null || true
INSERT IGNORE INTO stack (stack_id, stack_name, stack_version)
  VALUES (NULL, 'BIGTOP', '3.5.0');
EOSQL

echo "==> BIGTOP/3.5.0 stack injected successfully (inherited from BIGTOP/${PARENT_STACK})"
echo "==> Stack location: ${STACK_HOME}"

# ── Apply FLINK JobManager/TaskManager stack fix ────────────────────────────
# Ambari 3.5.0 FLINK metainfo 的 FLINK_JOBMANAGER / FLINK_TASKMANAGER 组件
# 没有 commandScript（且引用不存在的 flink-jobmanager / flink-taskmanager 包），
# Ambari 无法安装/启动它们。补丁脚本 + metainfo 组件定义需写入 3.2.0 栈
# （agent 实际加载 FLINK 脚本的版本；3.5.0 仅覆盖组件列表）。
if [ -x /root/setup-flink-stack-fix.sh ] && [ -d /root/flink-stack-fix ]; then
  echo "==> Applying FLINK JobManager/TaskManager stack fix..."
  bash /root/setup-flink-stack-fix.sh
else
  echo "==> WARN: /root/setup-flink-stack-fix.sh not present, skip FLINK fix"
fi
