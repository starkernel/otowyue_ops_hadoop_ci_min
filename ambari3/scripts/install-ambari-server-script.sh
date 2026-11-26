#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

set -ex

# ── Yum repo pointing to local nginx ──────────────────────────────────────────
tee /etc/yum.repos.d/ambari.repo << 'EOF'
# >>> 配置YUM源指向本地Nginx仓库，实现完全离线安装
[ambari]
name=Ambari 3.1.0 + Bigtop 3.5.0 Local Repository
baseurl=http://bigtop_hostname0
gpgcheck=0
enabled=1
EOF

dnf clean all
dnf makecache --disablerepo=ambari || dnf makecache

# ── Enable PowerTools/CRB repo for devel packages ─────────────────────────────
dnf install -y 'dnf-command(config-manager)' 2>/dev/null || true
dnf config-manager --set-enabled powertools 2>/dev/null || \
  dnf config-manager --set-enabled crb 2>/dev/null || true

# ── Java ───────────────────────────────────────────────────────────────────────
dnf install -y java-17-openjdk-devel java-1.8.0-openjdk-devel
# >>> 安装JDK 8和17：Ambari Server用JDK8，部分组件需要JDK17

# ── Ambari dependencies ────────────────────────────────────────────────────────
dnf install -y python3 python3-distro python3-psycopg2

# ── Ambari Agent (also runs on server node) ────────────────────────────────────
dnf install -y ambari-agent
# >>> 主节点也需要安装Agent，用于管理本节点上的服务组件

# ── Ambari Server ──────────────────────────────────────────────────────────────
dnf install -y ambari-server
# >>> 安装Ambari Server核心包，提供Web UI和REST API管理能力

# ── MySQL 8 ────────────────────────────────────────────────────────────────────
dnf install -y https://dev.mysql.com/get/mysql80-community-release-el8-1.noarch.rpm
# >>> 安装MySQL 8.0官方YUM源，获取最新稳定版MySQL Server
dnf install -y mysql-server

systemctl stop mysqld.service 2>/dev/null || true

# --initialize-insecure: root 初始密码为空，无需解析随机临时密码
# >>> 初始化MySQL数据目录，--initialize-insecure使root初始密码为空
if [ ! -f /var/lib/mysql/mysql/user.ibd ]; then
  rm -rf /var/lib/mysql
  mkdir -p /var/lib/mysql /var/log/mysql
  chown -R mysql:mysql /var/lib/mysql /var/log/mysql
  chmod 750 /var/lib/mysql /var/log/mysql
  mysqld --initialize-insecure --user=mysql
  # >>> 初始化MySQL数据目录，--initialize-insecure使root初始密码为空
fi

echo 'bind-address=0.0.0.0' >> /etc/my.cnf.d/mysql-server.cnf
# >>> 允许MySQL监听所有网络接口，使集群其他节点可以连接

systemctl enable mysqld.service
systemctl start mysqld.service

# root 密码为空，直接连接设置所有用户和数据库
mysql -u root --password="" << 'EOSQL'
-- mysql_native_password 兼容旧版 JDBC（Ranger dba_script.py 用 useSSL=false 连接，不支持 caching_sha2_password 的公钥交换）
-- 注意：容器重建/重跑时 root@localhost 已由 --initialize-insecure 创建（空密码），
--       CREATE USER IF NOT EXISTS 对已存在用户不生效，必须再 ALTER USER 设密码。
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';
CREATE USER IF NOT EXISTS 'root'@'%.bigtop.apache.org' IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';
ALTER USER 'root'@'%.bigtop.apache.org' IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%.bigtop.apache.org' WITH GRANT OPTION;
-- 容器内 IP 直连（Ranger dba_script 从 172.19.0.x 连接时用 IP 而非域名）
CREATE USER IF NOT EXISTS 'root'@'172.19.0.%' IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';
ALTER USER 'root'@'172.19.0.%' IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'172.19.0.%' WITH GRANT OPTION;

CREATE USER IF NOT EXISTS 'ambari'@'localhost' IDENTIFIED BY 'ambari';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'localhost';
CREATE USER IF NOT EXISTS 'ambari'@'%' IDENTIFIED BY 'ambari';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'%';

CREATE DATABASE IF NOT EXISTS ambari CHARACTER SET utf8 COLLATE utf8_general_ci;
# >>> Ambari元数据库：存储集群配置、服务状态、主机信息等
CREATE DATABASE IF NOT EXISTS hive CHARACTER SET utf8 COLLATE utf8_general_ci;
# >>> Hive元数据库：存储表结构、分区、统计信息等元数据
CREATE DATABASE IF NOT EXISTS ranger CHARACTER SET utf8 COLLATE utf8_general_ci;
# >>> Ranger数据库：存储安全策略、审计日志等
CREATE DATABASE IF NOT EXISTS rangerkms CHARACTER SET utf8 COLLATE utf8_general_ci;
# >>> Ranger数据库：存储安全策略、审计日志等
CREATE DATABASE IF NOT EXISTS oozie CHARACTER SET utf8 COLLATE utf8_general_ci;

CREATE USER IF NOT EXISTS 'hive'@'%' IDENTIFIED BY 'hive';
GRANT ALL PRIVILEGES ON hive.* TO 'hive'@'%';

CREATE USER IF NOT EXISTS 'ranger'@'%' IDENTIFIED BY 'ranger';
GRANT ALL PRIVILEGES ON *.* TO 'ranger'@'%' WITH GRANT OPTION;

-- rangeradmin: Ambari UI 配置 Ranger 时使用的 DB 用户名
CREATE USER IF NOT EXISTS 'rangeradmin'@'%' IDENTIFIED BY 'Admin1234!';
GRANT ALL PRIVILEGES ON ranger.* TO 'rangeradmin'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'rangeradmin'@'localhost' IDENTIFIED BY 'Admin1234!';
GRANT ALL PRIVILEGES ON ranger.* TO 'rangeradmin'@'localhost' WITH GRANT OPTION;
-- 容器内 IP 直连
CREATE USER IF NOT EXISTS 'rangeradmin'@'172.19.0.%' IDENTIFIED BY 'Admin1234!';
GRANT ALL PRIVILEGES ON ranger.* TO 'rangeradmin'@'172.19.0.%' WITH GRANT OPTION;

CREATE USER IF NOT EXISTS 'rangerkms'@'%' IDENTIFIED BY 'rangerkms';
GRANT ALL PRIVILEGES ON rangerkms.* TO 'rangerkms'@'%';

CREATE USER IF NOT EXISTS 'oozie'@'%' IDENTIFIED BY 'oozie';
GRANT ALL PRIVILEGES ON oozie.* TO 'oozie'@'%';

FLUSH PRIVILEGES;
EOSQL

# ── Initialize Ambari DB schema ────────────────────────────────────────────────
# 幂等：表已存在（re-run/容器重建后 /var/lib/mysql 仍是挂载态）则跳过，避免 CREATE TABLE 报错中断
AMBARI_TABLES=$(mysql -uambari -pambari -N -e \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='ambari'" 2>/dev/null || echo 0)
if [ "${AMBARI_TABLES:-0}" -lt 2 ]; then
  mysql -uambari -pambari ambari < /var/lib/ambari-server/resources/Ambari-DDL-MySQL-CREATE.sql
  # >>> 导入Ambari数据库Schema，创建users/clusters/hosts等所有表
else
  echo "==> Ambari DB schema already initialized (${AMBARI_TABLES} tables), skip DDL import"
fi

# ── MySQL JDBC connector ───────────────────────────────────────────────────────
mkdir -p /usr/share/java
wget -q https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar \
  -O /usr/share/java/mysql-connector-java.jar

ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar

echo "server.jdbc.url=jdbc:mysql://localhost:3306/ambari?useSSL=false" \
  >> /etc/ambari-server/conf/ambari.properties

# ── 禁用 credential store ──────────────────────────────────────────────────────
cat >> /etc/ambari-server/conf/ambari.properties << 'EOF'
security.credential.store.enabled=false
# >>> 禁用凭证存储，避免jceks文件找不到导致的启动错误
security.temporary.keystore.actAsCredentialStore=false
EOF

# ── Ambari Server setup (non-interactive) ─────────────────────────────────────
ambari-server setup -s \
  -j /usr/lib/jvm/java-1.8.0-openjdk \
  --ambari-java-home /usr/lib/jvm/java-17-openjdk \
  --database=mysql \
  --databasehost=localhost \
  --databaseport=3306 \
  --databasename=ambari \
  --databaseusername=ambari \
  --databasepassword=ambari

# ── Inject Bigtop 3.5.0 stack definition ──────────────────────────────────────
bash /root/setup-bigtop-stack.sh
# >>> 核心步骤：注入Bigtop 3.5.0 Stack定义，HodoopForge核心创新

# ── 清理父栈（3.2.0/3.3.0/3.4.0）${stack_version} 占位符（必须紧跟 setup-bigtop-stack）─
# Agent 通过继承链加载 3.2.0 父栈的 service metainfo，若 metainfo 里包名仍是
# hadoop_${stack_version}，Deploy 时所有服务 Install 全失败（No package found）。
# 3.5.0 由 setup-bigtop-stack 从 3.4.0（无占位符）复制而来，但 3.2.0 基栈是
# RPM 自带原始文件，必须用 fix-package-names.sh 原地清理（含 metainfo.xml、
# params.py、archive.zip 等）。
bash /root/fix-package-names.sh
# >>> 核心步骤：清理父栈 ${stack_version} 占位符，保证 Deploy 包名可见

# ── python -> python3 symlink ──────────────────────────────────────────────────
# 兼容使用 `#!/usr/bin/python` 的旧脚本（如 Ranger credential helper）。
# 悬空/缺失软链接会导致组件 Start 失败，必须修复指向真实解释器。
if [ ! -e /usr/bin/python ]; then
  ln -sf /usr/bin/python3 /usr/bin/python
  echo "[INFO] created /usr/bin/python -> $(readlink /usr/bin/python)"
fi
# >>> 创建python->python3软链接，兼容使用python命令的旧脚本

# ── Fix ranger script permissions ─────────────────────────────────────────────
for d in ranger-admin ranger-usersync ranger-tagsync ranger-kms; do
  [ -d /usr/lib/${d} ] && find /usr/lib/${d} -name '*.sh' -exec chmod a+x {} \; 2>/dev/null || true
done

# >>> hive-client是distro-select使用的别名，指向实际的/usr/lib/hive
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

# ── Fix bigtop-select: add missing packages to leaves dict ────────────────────
sed -i 's/"hadoop-hdfs-namenode": "hadoop-hdfs",/"hadoop-hdfs-namenode": "hadoop-hdfs",\n           "hadoop-hdfs-dfsrouter": "hadoop-hdfs",/' \
  /usr/lib/bigtop-select/distro-select 2>/dev/null || true

# ── Disable credential store in ambari-agent (no jceks support) ───────────────
sed -i 's/if credential_store_enabled and command_name != self.COMMAND_NAME_STATUS:/if False and command_name != self.COMMAND_NAME_STATUS:  # disabled: no jceks support/' \
  /usr/lib/ambari-agent/lib/ambari_agent/CustomServiceOrchestrator.py || true

# ── Start Ambari Server ────────────────────────────────────────────────────────
# Fix bigtop-select directory structure before starting
# distro-select 期望 /usr/bigtop/3.5.0/usr/lib/<pkg>，RPM 装到 /usr/lib/<pkg>
# >>> distro-select期望此目录结构，将实际安装路径软链接进来
mkdir -p /usr/bigtop/3.5.0/usr/lib
# >>> distro-select期望此目录结构，将实际安装路径软链接进来
for pkg in hadoop hadoop-hdfs hadoop-yarn hadoop-mapreduce hbase hive hive-hcatalog \
           zookeeper kafka spark tez ranger ranger-admin ranger-kms ranger-usersync \
           ranger-tagsync flink solr zeppelin livy phoenix; do
  [ -d /usr/lib/${pkg} ] && ln -sfn /usr/lib/${pkg} /usr/bigtop/3.5.0/usr/lib/${pkg}
  # >>> distro-select期望此目录结构，将实际安装路径软链接进来
done
# hive-client 是 distro-select 用的别名，指向 /usr/lib/hive
# >>> hive-client是distro-select使用的别名，指向实际的/usr/lib/hive
[ -d /usr/lib/hive ] && ln -sfn /usr/lib/hive /usr/bigtop/3.5.0/usr/lib/hive-client
# >>> distro-select期望此目录结构，将实际安装路径软链接进来
# 所有 ranger plugin 也需要链接
for pkg in $(ls /usr/lib/ | grep ranger); do
  ln -sfn /usr/lib/${pkg} /usr/bigtop/3.5.0/usr/lib/${pkg} 2>/dev/null || true
  # >>> distro-select期望此目录结构，将实际安装路径软链接进来
done
ln -sfn /usr/lib/hadoop-hdfs/bin/hdfs /usr/bin/hdfs 2>/dev/null || true
ln -sfn /usr/lib/hadoop/bin/hadoop /usr/bin/hadoop 2>/dev/null || true
ln -sfn /usr/lib/hadoop-yarn/bin/yarn /usr/bin/yarn 2>/dev/null || true
ln -sfn /usr/lib/hadoop-mapreduce/bin/mapred /usr/bin/mapred 2>/dev/null || true
for f in /usr/lib/hadoop/libexec/*; do
  ln -sfn $f /usr/libexec/$(basename $f) 2>/dev/null || true
done

# /usr/bin 下的命令需要是软链接，否则 distro-select 报错
for cmd in hbase hadoop hdfs yarn mapred beeline hive hcat; do
  [ -f /usr/bin/${cmd} ] && [ ! -L /usr/bin/${cmd} ] && rm -f /usr/bin/${cmd}
done

# mysql-connector 复制到 hive lib 目录
mkdir -p /usr/lib/hive/lib
cp -f /usr/share/java/mysql-connector-java.jar /usr/lib/hive/lib/mysql-connector-java.jar 2>/dev/null || true
# >>> JDBC驱动复制到Hive lib目录，Metastore连接MySQL必需

ambari-server start
# >>> 启动Ambari Server服务，随后轮询等待API就绪

# ── 等待 Ambari Server API 就绪 ───────────────────────────────────────────────
echo "==> Waiting for Ambari API to be ready..."
# >>> 轮询等待API就绪，最多等待150秒(30次×5秒)，确保后续操作成功
for i in $(seq 1 30); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/v1/clusters)
  if [ "${STATUS}" = "200" ] || [ "${STATUS}" = "403" ]; then
    echo "==> Ambari API is ready (HTTP ${STATUS})"
    break
  fi
  echo "    waiting... (${i}/30)"
  sleep 5
done

# ── 生成 VDF 文件 ─────────────────────────────────────────────────────────────
cat > /var/repo/ambari/bigtop-3.5.0-vdf.xml << 'VDFEOF'
<?xml version="1.0"?>
<repository-version xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:noNamespaceSchemaLocation="version_definition.xsd">
  <release>
    <type>STANDARD</type>
    <stack-id>BIGTOP-3.5.0</stack-id>
    <version>3.5.0.0</version>
    <build>1</build>
    <compatible-with>3.5.*</compatible-with>
    <release-notes>http://bigtop.apache.org</release-notes>
    <display>Bigtop-3.5.0.0-1</display>
  </release>
  <manifest>
    <service id="HDFS-350"       name="HDFS"       version="3.3.6"  versionId="HDFS-3.3.6"/>
    <service id="YARN-350"       name="YARN"       version="3.3.6"  versionId="YARN-3.3.6"/>
    <service id="MAPREDUCE2-350" name="MAPREDUCE2" version="3.3.6"  versionId="MAPREDUCE2-3.3.6"/>
    <service id="HIVE-350"       name="HIVE"       version="4.0.1"  versionId="HIVE-4.0.1"/>
    <service id="HBASE-350"      name="HBASE"      version="2.6.2"  versionId="HBASE-2.6.2"/>
    <service id="ZOOKEEPER-350"  name="ZOOKEEPER"  version="3.8.4"  versionId="ZOOKEEPER-3.8.4"/>
    <service id="KAFKA-350"      name="KAFKA"      version="3.4.1"  versionId="KAFKA-3.4.1"/>
    <service id="SPARK-350"      name="SPARK"      version="3.5.6"  versionId="SPARK-3.5.6"/>
    <service id="RANGER-350"     name="RANGER"     version="2.7.0"  versionId="RANGER-2.7.0"/>
    <service id="RANGER_KMS-350" name="RANGER_KMS" version="2.7.0"  versionId="RANGER_KMS-2.7.0"/>
    <service id="TEZ-350"        name="TEZ"        version="0.10.4" versionId="TEZ-0.10.4"/>
    <service id="FLINK-350"      name="FLINK"      version="1.20.1" versionId="FLINK-1.20.1"/>
    <service id="SOLR-350"       name="SOLR"       version="8.11.4" versionId="SOLR-8.11.4"/>
    <service id="ZEPPELIN-350"   name="ZEPPELIN"   version="0.11.2" versionId="ZEPPELIN-0.11.2"/>
    <service id="LIVY-350"       name="LIVY"       version="0.8.0"  versionId="LIVY-0.8.0"/>
  </manifest>
  <available-services>
    <service idref="HDFS-350"/>
    <service idref="YARN-350"/>
    <service idref="MAPREDUCE2-350"/>
    <service idref="HIVE-350"/>
    <service idref="HBASE-350"/>
    <service idref="ZOOKEEPER-350"/>
    <service idref="KAFKA-350"/>
    <service idref="SPARK-350"/>
    <service idref="RANGER-350"/>
    <service idref="RANGER_KMS-350"/>
    <service idref="TEZ-350"/>
    <service idref="FLINK-350"/>
    <service idref="SOLR-350"/>
    <service idref="ZEPPELIN-350"/>
    <service idref="LIVY-350"/>
  </available-services>
  <repository-info>
    <os family="redhat8">
      <repo>
        <baseurl>http://bigtop_hostname0</baseurl>
        <repoid>BIGTOP-3.5.0</repoid>
        <reponame>Bigtop 3.5.0</reponame>
        <unique>true</unique>
      </repo>
    </os>
  </repository-info>
</repository-version>
VDFEOF

# ── 安装 mysql-connector 并注入 repo_version ─────────────────────────────────
pip3 install mysql-connector-python==8.0.28 -q
python3 /root/insert-repo-version.py
# >>> 向Ambari数据库注入Bigtop 3.5.0版本记录，使UI可选择该版本

# ── 禁用所有服务的 credential store（避免 jceks 文件找不到的错误）────────────
mysql -uambari -pambari ambari -e \
  "UPDATE servicedesiredstate SET credential_store_enabled = 0;" 2>/dev/null || true
  # >>> 数据库层面禁用所有服务的凭证存储，彻底避免jceks相关错误

# ── Hive 服务修复 ──────────────────────────────────────────────────────────────
# 1. 修复 Bigtop stack service_advisor.py 中的 hive.exec.post.hooks bug
#    Bigtop 3.5.0 的 service_advisor.py 在没有 hooks 时返回 " "（空格）而不是 ""（空字符串）
#    这会导致 Hive 4.0.1 抛出 ClassNotFoundException
echo "==> Fixing Bigtop service_advisor.py hive.exec.post.hooks bug..."
SERVICE_ADVISOR="/var/lib/ambari-server/resources/stacks/BIGTOP/3.2.0/services/HIVE/service_advisor.py"
if [ -f "$SERVICE_ADVISOR" ]; then
  # 修复：将 " " 改为 ""（空字符串）
  sed -i 's/hooks_value = " " if len(hive_hooks) == 0/hooks_value = "" if len(hive_hooks) == 0/g' "$SERVICE_ADVISOR"
  sed -i 's/hooks_value = " "$/hooks_value = ""/g' "$SERVICE_ADVISOR"
  # 清除 Python 缓存
  rm -f /var/lib/ambari-server/resources/stacks/BIGTOP/3.2.0/services/HIVE/__pycache__/service_advisor.cpython-*.pyc 2>/dev/null || true
  echo "    Fixed service_advisor.py"
fi

# 2. 修复 Ambari Agent hive_check.py 中的 auth=noSasl 兼容性问题
# >>> 修复：Hive 4.0.1对auth参数大小写敏感，noSasl->none
#    Hive 4.0.1 对 auth 参数大小写敏感，auth=noSasl 会失败，需要改为 auth=none
# >>> 修复：Hive 4.0.1对auth参数大小写敏感，noSasl->none
echo "==> Fixing Ambari Agent hive_check.py auth parameter..."
HIVE_CHECK="/usr/lib/ambari-agent/lib/resource_management/libraries/functions/hive_check.py"
if [ -f "$HIVE_CHECK" ]; then
  sed -i 's/beeline_url.append("auth=noSasl")/beeline_url.append("auth=none")/g' "$HIVE_CHECK"
  # >>> 修复：Hive 4.0.1对auth参数大小写敏感，noSasl->none
  echo "    Fixed hive_check.py"
fi

# 2. 初始化 Hive Metastore schema（Hive 4.0 需要手动初始化）
#    Ambari 的 schematool -initSchema 在 Hive 4.0 中有兼容性问题
#    使用 MySQL 直接初始化 schema
if [ -d /usr/lib/hive ]; then
  echo "==> Initializing Hive Metastore schema..."
  # 检查 schema 是否已初始化
  SCHEMA_VERSION=$(mysql -uhive -phive hive -N -e "SELECT SCHEMA_VERSION FROM VERSION 2>/dev/null" || echo "")
  if [ -z "$SCHEMA_VERSION" ]; then
    # 使用 schematool 初始化（需要 Metastore 服务运行，这里用 MySQL 脚本）
    # Hive 4.0.1 的 schema 脚本位置
    if [ -f /usr/lib/hive/scripts/metastore/upgrade/mysql/hive-schema-4.0.0.mysql.sql ]; then
    # >>> 初始化Hive Metastore Schema，创建VERSION/DBS/TBLS等核心表
      mysql -uhive -phive hive < /usr/lib/hive/scripts/metastore/upgrade/mysql/hive-schema-4.0.0.mysql.sql 2>/dev/null || true
      # >>> 初始化Hive Metastore Schema，创建VERSION/DBS/TBLS等核心表
      echo "==> Hive Metastore schema initialized"
    fi
  else
    echo "==> Hive Metastore schema already initialized: $SCHEMA_VERSION"
  fi
fi

# 3. 创建 HDFS 上 Hive 需要的目录并设置权限
#    这些目录在 Hive 服务启动时需要
echo "==> Creating HDFS directories for Hive..."
# 等待 HDFS 可用
for i in $(seq 1 30); do
  if hdfs dfs -test -d / 2>/dev/null; then
    break
  fi
  echo "  waiting for HDFS... (${i}/30)"
  sleep 5
done

# 创建 Hive 仓库目录
hdfs dfs -mkdir -p /warehouse/tablespace/managed/hive 2>/dev/null || true
hdfs dfs -mkdir -p /warehouse/tablespace/external/hive 2>/dev/null || true
hdfs dfs -mkdir -p /tmp/hive 2>/dev/null || true
hdfs dfs -mkdir -p /user/hive 2>/dev/null || true

# 设置权限
hdfs dfs -chown -R hive:hadoop /warehouse/tablespace 2>/dev/null || true
hdfs dfs -chown hive:hadoop /tmp/hive 2>/dev/null || true
hdfs dfs -chown hive:hadoop /user/hive 2>/dev/null || true
hdfs dfs -chmod -R 1777 /tmp/hive 2>/dev/null || true

echo "==> Hive HDFS directories created"

# 4. 品牌定制：将 Ambari UI 左上角产品名改为 HodoopForge（幂等）
#    容器重建后所有 UI 文件恢复为镜像原始 'Ambari'，此步保证重装后仍显示 HodoopForge
echo "==> Applying HodoopForge UI branding..."

# 4a. 旧版 Ember UI（app.js — I18n 键 app.name / app.name.subtitle）
APPJS=/usr/lib/ambari-server/web/javascripts/app.js
if grep -q "'app.name': 'HodoopForge'" "$APPJS" 2>/dev/null; then
  echo "  [old UI] (already applied, skip)"
else
  sed -i \
    -e "s/'app.name': 'Ambari',/'app.name': 'HodoopForge',/" \
    -e "s/'app.name.subtitle': 'Ambari - {0}',/'app.name.subtitle': 'HodoopForge - {0}',/" \
    -e "s/'app.name.subtitle.experimental': 'Ambari Experimental',/'app.name.subtitle.experimental': 'HodoopForge Experimental',/" \
    "$APPJS"
  echo "  [old UI] OK: app.name changed to HodoopForge"
fi

# 4b. 新版 ADMIN_VIEW（AngularJS admin console — common.ambari / common.apacheAmbari 翻译键）
ADMIN_VIEW_DIR=$(find /var/lib/ambari-server/resources/views/work -maxdepth 1 -type d -name 'ADMIN_VIEW*' 2>/dev/null | head -1)
if [ -n "$ADMIN_VIEW_DIR" ]; then
  ADMIN_JS="$ADMIN_VIEW_DIR/scripts/main.js"
  ADMIN_HTML="$ADMIN_VIEW_DIR/index.html"
  if grep -q "'common.ambari': 'HodoopForge'" "$ADMIN_JS" 2>/dev/null; then
    echo "  [admin view] (already applied, skip)"
  else
    sed -i \
      -e "s/'common.ambari': 'Ambari',/'common.ambari': 'HodoopForge',/" \
      -e "s/'common.apacheAmbari': 'Apache Ambari',/'common.apacheAmbari': 'HodoopForge',/" \
      "$ADMIN_JS"
    [ -f "$ADMIN_HTML" ] && sed -i 's|<title>Ambari</title>|<title>HodoopForge</title>|' "$ADMIN_HTML"
    echo "  [admin view] OK: common.ambari changed to HodoopForge"
  fi
else
  echo "  [admin view] (ADMIN_VIEW not yet deployed, skip)"
fi

echo "==> Ambari Server ready. Access UI at http://localhost:20609 (admin/admin)"