#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#
# Hive 服务修复脚本
# 解决以下问题：
# 1. hive.exec.post.hooks 配置空格值导致 ClassNotFoundException
# 2. HiveServer2 以 root 用户运行导致 HDFS 权限问题
# 3. Metastore schema 初始化问题
# 4. PID 文件不匹配导致状态检测失败
# 5. /tmp/report.json 权限问题导致 metrics 报错
# >>> 清理临时metrics文件，避免权限问题导致的Ambari告警
#

set -e

echo "==> HodoopForge Hive Service Fix Script"
echo ""

# ── 1. 修复 hive-site.xml 中的 hive.exec.post.hooks 配置 ───────────────────────
echo "[1/6] Fixing hive.exec.post.hooks configuration..."
if [ -f /etc/hive/conf/hive-site.xml ]; then
  sed -i 's|<name>hive.exec.post.hooks</name>\n      <value> </value>|<name>hive.exec.post.hooks</name>\n      <value></value>|g' /etc/hive/conf/hive-site.xml
  sed -i 's|<value> </value>|<value></value>|g' /etc/hive/conf/hive-site.xml
  echo "    Fixed hive.exec.post.hooks empty value"
fi

# ── 1b. 禁用 Hive Metastore metrics（HadoopMetrics2Reporter 与 Hadoop 3.x 不兼容）───
# Hive 4.x 的 dropwizard-metrics-hadoop-metrics2-reporter jar 使用了
# HadoopMetrics2Reporter.forRegistry() 方法，该方法在 Hadoop 3.x 中
# 接口已变更，导致 Metastore 启动时抛 NoSuchMethodError 直接崩溃。
# 解决方案：在所有 hive conf 目录中禁用 metastore metrics 上报。
echo "[1b/6] Disabling Hive Metastore metrics (HadoopMetrics2Reporter incompatible with Hadoop 3.x)..."
for CONF_DIR in /etc/hive/conf /etc/hive/conf.dist; do
  HIVE_SITE="${CONF_DIR}/hive-site.xml"
  [ -f "$HIVE_SITE" ] || continue
  if grep -q 'hive.metastore.metrics.enabled' "$HIVE_SITE"; then
    # 已存在，确保值为 false
    sed -i '/<name>hive.metastore.metrics.enabled<\/name>/{n;s|<value>.*</value>|<value>false</value>|}' "$HIVE_SITE"
  else
    # 新增
    sed -i 's|</configuration>|  <property><name>hive.metastore.metrics.enabled</name><value>false</value><description>Disabled: HadoopMetrics2Reporter incompatible with Hadoop 3.x</description></property>\n</configuration>|' "$HIVE_SITE"
  fi
  echo "    Set hive.metastore.metrics.enabled=false in ${CONF_DIR}"
done

# ── 2. 修复 /tmp/report.json 权限问题 ─────────────────────────────────────────
# >>> 清理临时metrics文件，避免权限问题导致的Ambari告警
echo "[2/7] Fixing /tmp/report.json permissions..."
# >>> 清理临时metrics文件，避免权限问题导致的Ambari告警
rm -f /tmp/report.json /tmp/hmetrics*.json 2>/dev/null || true
# >>> 清理临时metrics文件，避免权限问题导致的Ambari告警
echo "    Cleaned up temp metric files"

# ── 3. 修复 Ambari Agent hive_check.py auth 参数 ───────────────────────────────
echo "[3/7] Fixing Ambari Agent hive_check.py auth parameter..."
HIVE_CHECK="/usr/lib/ambari-agent/lib/resource_management/libraries/functions/hive_check.py"
if [ -f "$HIVE_CHECK" ]; then
  # Hive 4.0.1 对 auth 参数大小写敏感，auth=noSasl 会失败，需要改为 auth=none
  # >>> 修复BUG-003：Hive 4.0.1对auth参数大小写敏感，noSasl->none
  sed -i 's/beeline_url.append("auth=noSasl")/beeline_url.append("auth=none")/g' "$HIVE_CHECK"
  # >>> 修复BUG-003：Hive 4.0.1对auth参数大小写敏感，noSasl->none
  echo "    Fixed hive_check.py auth parameter"
fi

# ── 4. 修复 HDFS 上 Hive 目录权限 ─────────────────────────────────────────────
echo "[4/7] Fixing HDFS directory permissions for Hive..."
hdfs dfs -mkdir -p /warehouse/tablespace/managed/hive 2>/dev/null || true
hdfs dfs -mkdir -p /warehouse/tablespace/external/hive 2>/dev/null || true
hdfs dfs -mkdir -p /tmp/hive 2>/dev/null || true
hdfs dfs -mkdir -p /user/hive 2>/dev/null || true

hdfs dfs -chown -R hive:hadoop /warehouse/tablespace 2>/dev/null || true
# >>> Hive服务以hive用户运行，必须拥有仓库目录的写入权限
hdfs dfs -chown hive:hadoop /tmp/hive 2>/dev/null || true
hdfs dfs -chown hive:hadoop /user/hive 2>/dev/null || true
hdfs dfs -chmod -R 1777 /tmp/hive 2>/dev/null || true
# >>> 1777=sticky bit，允许所有用户写入但只能删除自己的文件
echo "    HDFS directories ready"

# ── 5. 检查并初始化 Metastore schema ──────────────────────────────────────────
echo "[5/7] Checking Hive Metastore schema..."
SCHEMA_VERSION=$(mysql -uhive -phive hive -N -e "SELECT SCHEMA_VERSION FROM VERSION" 2>/dev/null || echo "")
if [ -z "$SCHEMA_VERSION" ]; then
  echo "    Initializing Metastore schema..."
  if [ -f /usr/lib/hive/scripts/metastore/upgrade/mysql/hive-schema-4.0.0.mysql.sql ]; then
  # >>> 修复BUG-005：初始化Metastore Schema，创建VERSION/DBS/TBLS等表
    mysql -uhive -phive hive < /usr/lib/hive/scripts/metastore/upgrade/mysql/hive-schema-4.0.0.mysql.sql 2>/dev/null || true
    # >>> 修复BUG-005：初始化Metastore Schema，创建VERSION/DBS/TBLS等表
    echo "    Schema initialized"
  else
    echo "    WARNING: Schema SQL file not found, please initialize manually"
  fi
else
  echo "    Schema already initialized: $SCHEMA_VERSION"
fi

# 创建 SYS DB 标记文件（Ambari 告警需要）
if [ ! -f /etc/hive/sys.db.created ]; then
  touch /etc/hive/sys.db.created
  echo "    Created /etc/hive/sys.db.created marker file"
fi

# ── 6. 修复 PID 文件 ───────────────────────────────────────────────────────────
echo "[6/7] Fixing PID files..."

# HiveServer2 PID
HS2_PID=$(ps aux | grep "HiveServer2" | grep -v grep | awk '{print $2}' | head -1)
if [ -n "$HS2_PID" ]; then
  echo $HS2_PID > /var/run/hive/hive-server.pid
  # >>> 修复BUG-004：更新PID文件，使Ambari状态检测正确识别进程
  chown hive:hadoop /var/run/hive/hive-server.pid 2>/dev/null || true
  # >>> 修复BUG-004：更新PID文件，使Ambari状态检测正确识别进程
  echo "    HiveServer2 PID: $HS2_PID"
fi

# Metastore PID
MS_PID=$(ps aux | grep "HiveMetaStore" | grep -v grep | awk '{print $2}' | head -1)
if [ -n "$MS_PID" ]; then
  echo $MS_PID > /var/run/hive/hive-metastore.pid
  chown hive:hadoop /var/run/hive/hive-metastore.pid 2>/dev/null || true
  echo "    Metastore PID: $MS_PID"
fi

# ── 7. 验证服务状态 ────────────────────────────────────────────────────────────
echo "[7/7] Verifying services..."

# 检查 Metastore
if netstat -tlnp 2>/dev/null | grep -q ":9083"; then
  echo "    Metastore: RUNNING (port 9083)"
  # >>> 9083是Hive Metastore的Thrift服务端口
else
  echo "    Metastore: NOT RUNNING"
  echo "    To start: su hive -c '/usr/bigtop/current/hive-client/bin/hive --service metastore &'"
fi

# 检查 HiveServer2
if netstat -tlnp 2>/dev/null | grep -q ":10000"; then
  echo "    HiveServer2: RUNNING (port 10000)"
  # >>> 10000是HiveServer2的JDBC/Thrift服务端口
else
  echo "    HiveServer2: NOT RUNNING"
  echo "    To start: su hive -c '/usr/bigtop/current/hive-client/bin/hive --service hiveserver2 &'"
fi

echo ""
echo "==> Fix completed. Please restart Hive services from Ambari UI if needed."