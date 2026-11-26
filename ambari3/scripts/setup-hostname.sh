#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

# Run this after containers restart to refresh IP addresses in /etc/hosts

set -ex

INSTANCES="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"

# ── 重新应用 fix-package-names.sh（容器重启后 stack 文件恢复原始状态）────────
# /var/lib/ambari-server/ 是容器可写层，重启后丢失，需要每次重新修复
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> Re-applying fix-package-names.sh after container restart..."
docker compose cp "${SCRIPT_DIR}/fix-package-names.sh" bigtop_hostname0:/root/fix-package-names.sh
docker compose exec bigtop_hostname0 bash /root/fix-package-names.sh
echo "==> Package names fixed"

# ── 重放 FLINK JobManager/TaskManager 栈补丁（容器重启后可写层丢失）────────
# 必须在 ambari-server restart 之前执行！它会向 3.2.0 栈的 FLINK metainfo.xml
# 追加 FLINK_JOBMANAGER/FLINK_TASKMANAGER 组件 + commandScript；若在重启后才写盘，
# Server 内存（只启动时加载一次）里没有这两个组件，FLINK 安装仍失败。
echo "==> Re-applying Flink JobManager/TaskManager stack fix..."
docker compose cp -a "${SCRIPT_DIR}/flink-stack-fix" bigtop_hostname0:/root/flink-stack-fix
docker compose cp "${SCRIPT_DIR}/setup-flink-stack-fix.sh" bigtop_hostname0:/root/setup-flink-stack-fix.sh
docker compose exec bigtop_hostname0 bash /root/setup-flink-stack-fix.sh
echo "==> Flink stack fix applied"

# ── 重启 ambari-server 强制重载栈定义到内存（必须，否则 Retry 仍用旧占位符）───
# AmbariMetaInfo 只在 ambari-server 启动时从磁盘加载一次；运行期间修改
# metainfo.xml 不会热加载。若只改盘不重启，Server 生成的命令 package_list
# 仍是 hadoop_${stack_version}，Agent 照旧报 No package found。因此重放
# fix-package-names.sh / flink-stack-fix 之后必须 ambari-server restart。
echo "==> Restarting ambari-server to reload fixed stack metainfo..."
docker compose exec bigtop_hostname0 ambari-server restart >/dev/null 2>&1 || \
  docker compose exec bigtop_hostname0 ambari-server start >/dev/null 2>&1 || true
echo "==> ambari-server restarted"

# ── 清理 4 节点 Agent 栈缓存，强制重新下发修复后的父栈 metainfo ────────────
# Agent 首次 Deploy 时会向 Server 拉取整个继承链（含 3.2.0 父栈）并缓存到
# /var/lib/ambari-agent/cache/stacks/BIGTOP/。若该缓存是"修复前"拉取的旧文件
# （含 ${stack_version} 占位符），仅重放 fix-package-names.sh 不够——旧缓存不会
# 自动失效，Deploy 仍报 No package found for hadoop_${stack_version}。
# 必须删除缓存目录（含 pycache）并重启 agent，使下次请求按修复后栈重新下发。
echo "==> Clearing stale agent stack caches on all nodes..."
for i in $INSTANCES; do
  docker compose exec $i bash -c "
    rm -rf /var/lib/ambari-agent/cache/stacks/BIGTOP/3.2.0 /var/lib/ambari-agent/cache/stacks/BIGTOP/3.3.0
    find /var/lib/ambari-agent/cache/stacks/BIGTOP -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
    ambari-agent restart >/dev/null 2>&1 || systemctl restart ambari-agent 2>/dev/null || true
  " 2>/dev/null || true
done
echo "==> Agent stack caches cleared, agents restarted"

# ── 校验：确认 Server 磁盘 + Agent 缓存均无包装占位符（fail-fast）───────────
echo "==> Verifying no _\${stack_version} placeholder remains..."
SERVER_LEFT=$(docker compose exec bigtop_hostname0 bash -c \
  "grep -rl --fixed-strings '_\${stack_version}' /var/lib/ambari-server/resources/stacks/BIGTOP/ --include=metainfo.xml 2>/dev/null | wc -l" || true)
if [ "${SERVER_LEFT:-1}" -gt 0 ]; then
  echo "FATAL: Server 磁盘仍有 ${SERVER_LEFT} 个 metainfo.xml 含 _\${stack_version}" >&2
  exit 1
fi
AGENT_LEFT=$(for i in $INSTANCES; do
  docker compose exec $i bash -c \
    "grep -rl --fixed-strings '_\${stack_version}' /var/lib/ambari-agent/cache/stacks/ 2>/dev/null | wc -l" 2>/dev/null || true
done | awk '{s+=$1} END{print s+0}')
echo "==> VERIFY: Server 0 残留，Agent 缓存总残留 ${AGENT_LEFT}"
if [ "${AGENT_LEFT}" -gt 0 ]; then
  echo "WARN: 仍有 Agent 缓存含占位符（可接受：agent 未重新拉取前仍可用旧缓存）" >&2
fi

# ── 重建 /usr/bigtop/3.5.0/usr/lib/ 软链接（容器重启后可写层丢失）──────────
# distro-select 和 yarn.py/hive.py 等 install 脚本依赖
# /usr/bigtop/current/<pkg> -> /usr/bigtop/3.5.0/usr/lib/<pkg> -> /usr/lib/<pkg>
# 第二层软链接在容器重启后消失，需要重建
echo "==> Rebuilding /usr/bigtop/3.5.0/usr/lib symlinks on all nodes..."
REBUILD_SYMLINKS='
mkdir -p /usr/bigtop/3.5.0/usr/lib
for pkg in hadoop hadoop-hdfs hadoop-yarn hadoop-mapreduce hbase hive hive-hcatalog \
           zookeeper kafka spark tez flink solr zeppelin livy phoenix; do
  TARGET=/usr/bigtop/3.5.0/usr/lib/${pkg}
  if [ -d "${TARGET}" ] && [ ! -L "${TARGET}" ]; then
    rmdir "${TARGET}" 2>/dev/null || true
  fi
  [ -d /usr/lib/${pkg} ] && ln -sfn /usr/lib/${pkg} ${TARGET} 2>/dev/null || true
done
[ -d /usr/lib/hive ] && ln -sfn /usr/lib/hive /usr/bigtop/3.5.0/usr/lib/hive-client 2>/dev/null || true
# hive-webhcat -> hive-hcatalog（Hive 4.x 包名变更，旧名 hcatalog-core.jar -> hive-hcatalog-core.jar）
TARGET=/usr/bigtop/3.5.0/usr/lib/hive-webhcat
[ -d "${TARGET}" ] && [ ! -L "${TARGET}" ] && rmdir "${TARGET}" 2>/dev/null || true
[ -d /usr/lib/hive-hcatalog ] && ln -sfn /usr/lib/hive-hcatalog ${TARGET} 2>/dev/null || true
JAR_DIR=/usr/lib/hive-hcatalog/share/hcatalog
[ -f "${JAR_DIR}/hive-hcatalog-core.jar" ] && [ ! -f "${JAR_DIR}/hcatalog-core.jar" ] && \
  ln -sfn hive-hcatalog-core.jar ${JAR_DIR}/hcatalog-core.jar 2>/dev/null || true
for pkg in $(ls /usr/lib/ 2>/dev/null | grep -E "^ranger"); do
  TARGET=/usr/bigtop/3.5.0/usr/lib/${pkg}
  if [ -d "${TARGET}" ] && [ ! -L "${TARGET}" ]; then
    rmdir "${TARGET}" 2>/dev/null || true
  fi
  ln -sfn /usr/lib/${pkg} ${TARGET} 2>/dev/null || true
done
echo "symlinks: $(ls /usr/bigtop/3.5.0/usr/lib/ | wc -l) entries"
'
for i in $INSTANCES; do
  docker compose exec $i bash -c "$REBUILD_SYMLINKS" || true
done
# ── 修复 ranger 脚本执行权限（容器重启后恢复原始 -r-xr--r-- 权限）──────────
# ranger 服务以 ranger 用户身份执行 .sh 脚本，other 无执行权限会报 exit 126
for i in $INSTANCES; do
  docker compose exec $i bash -c "
    for d in ranger-admin ranger-usersync ranger-tagsync ranger-kms; do
      [ -d /usr/lib/\${d} ] && find /usr/lib/\${d} -name '*.sh' -exec chmod a+x {} \; 2>/dev/null || true
    done
  " 2>/dev/null || true
done
echo "==> Ranger script permissions fixed"

# ── 修复 Ranger HBase Plugin 缺失 commons-lang-2.6.jar ─────────────────────
# ranger-hbase-plugin-impl 没有打包 commons-lang-2.6.jar，
# 导致 RangerAuthorizationCoprocessor 加载时 ClassNotFoundException，
# HBase Master ABORT 退出。从 ranger-hdfs-plugin-impl 复制补全。
# 注意：需同时补全两个位置——
#   1) /usr/lib/ranger-hbase-plugin/lib/ranger-hbase-plugin-impl/  （插件源目录）
#   2) /usr/lib/hbase/lib/ranger-hbase-plugin-impl/                （HBase 运行时实际加载目录）
# 单独只补插件源目录时，HBase 运行时 classpath 仍会缺该类。
for i in $INSTANCES; do
  docker compose exec $i bash -c "
    SRC=/usr/lib/ranger-hdfs-plugin/lib/ranger-hdfs-plugin-impl/commons-lang-2.6.jar
    for DST in \
      /usr/lib/ranger-hbase-plugin/lib/ranger-hbase-plugin-impl/commons-lang-2.6.jar \
      /usr/lib/hbase/lib/ranger-hbase-plugin-impl/commons-lang-2.6.jar; do
      [ -f \"\$SRC\" ] && [ ! -f \"\$DST\" ] && \
        cp \"\$SRC\" \"\$DST\" && chown hbase:hadoop \"\$DST\" && \
        echo \"commons-lang-2.6.jar patched -> \$DST\" || true
    done
  " 2>/dev/null || true
done
echo "==> Ranger HBase Plugin commons-lang fix done"

# ── 修复 MySQL root/rangeradmin 缺少 172.19.0.% 授权 ─────────────────────────
# Ranger dba_script.py 从 hostname1(172.19.0.5) 连接 hostname0 的 MySQL 时，
# 来源 IP 是 172.19.0.x，不匹配 %.bigtop.apache.org（MySQL % 不匹配 IP），
# 导致 Access denied / Public Key Retrieval 错误。
echo "==> Ensuring MySQL 172.19.0.% grants for root and rangeradmin..."
docker compose exec bigtop_hostname0 bash -c "
  mysql -uroot -pambarirootpass -e \"
    CREATE USER IF NOT EXISTS 'root'@'172.19.0.%'
      IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'172.19.0.%' WITH GRANT OPTION;
    CREATE USER IF NOT EXISTS 'rangeradmin'@'172.19.0.%'
      IDENTIFIED BY 'Admin1234!';
    GRANT ALL PRIVILEGES ON ranger.* TO 'rangeradmin'@'172.19.0.%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
  \" 2>/dev/null | grep -v Warning || true
  echo '  MySQL 172.19.0.% grants OK'
" 2>/dev/null || true

# ── 重放 Iceberg 数据湖配置（容器重启后 jars/JAVA_HOME/conf 恢复原始状态）─
# Iceberg 1.11 runtime 需 JDK17，且与 Hive3.1 client 冲突需用 hadoop catalog。
# 容器重启后：/usr/lib/spark/jars/ 里的 jar、spark-env.sh 的 JAVA_HOME、
# spark-defaults.conf 的 iceberg 段都会丢/还原，需每次重放。
echo "==> Re-applying Iceberg data lake setup..."
bash "${SCRIPT_DIR}/setup-iceberg.sh"
echo "==> Iceberg setup applied"

rm -f hosts
printf '127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4\n' > hosts
printf '::1         localhost localhost.localdomain localhost6 localhost6.localdomain6\n\n' >> hosts

for i in $INSTANCES ; do
  docker compose exec -it $i dnf install -y net-tools -q 2>/dev/null || true
  docker compose cp getip.sh $i:/root/getip.sh
  IP=$(docker compose exec -it $i /bin/bash /root/getip.sh | tr -d '\r')
  FQDN=$(echo "$i" | sed 's/_/-/g')".bigtop.apache.org"
  echo "${IP}  ${FQDN} ${i}" >> hosts
done

if [ "$(basename $PWD)" == "scripts" ] ; then
  cat hosts > ../conf/hosts
else
  cat hosts > conf/hosts
fi
rm -f hosts
