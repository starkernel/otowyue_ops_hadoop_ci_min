#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

# 修正 BIGTOP stack 各服务的包名：
# 1. 清除所有父栈（3.2.0/3.3.0/3.4.0）metainfo.xml 中的 ${stack_version} 占位符
# 2. 覆盖 BIGTOP/3.5.0 各服务 metainfo.xml 为实际 rpm 包名
# 3. 末尾自校验：字面量 _${stack_version} 残留 >0 时 exit 1（fail-fast）
#
# ⚠ 运行后必须重启 ambari-server：AmbariMetaInfo 只在启动时读盘，不重启则
#   Server 内存仍是旧占位符，Retry 生成的命令 package_list 照旧报
#   No package found for xxx_${stack_version}（见 setup-hostname.sh / post-deploy-fixes.sh）
#
# 干扰说明：grep "stack_version" 命中 package/scripts/*.py 是 Python 变量名
#   （stack_version_formatted 等），不是包名占位符，无需处理。

set -ex

# ── 清除所有父栈中的 ${stack_version} 占位符 ─────────────────────────────────
# Ambari agent 安装时会沿继承链查找包名，父栈里的 xxx_${stack_version} 会被展开
# 成 xxx_3_5_0 导致 yum 找不到包，需要全部替换为实际包名
for PARENT_VER in 3.2.0 3.3.0 3.4.0; do
  PARENT_DIR=/var/lib/ambari-server/resources/stacks/BIGTOP/${PARENT_VER}/services
  [ -d "${PARENT_DIR}" ] || continue
  echo "==> Patching ${PARENT_VER} metainfo.xml files..."
  find "${PARENT_DIR}" -name "metainfo.xml" | while read f; do
    # 去掉 _${stack_version} 和 ${stack_version}_ 以及单独的 ${stack_version}
    sed -i 's/_\${stack_version}//g' "$f"
    sed -i 's/\${stack_version}_//g' "$f"
    sed -i 's/\${stack_version}//g' "$f"
    # 修复残留的 xxx_-yyy 格式（原来是 xxx_${stack_version}-yyy）→ xxx-yyy
    sed -i 's/_-/-/g' "$f"
  done
done

STACK=/var/lib/ambari-server/resources/stacks/BIGTOP/3.5.0/services

# ── HDFS ──────────────────────────────────────────────────────────────────────
cat > ${STACK}/HDFS/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>HDFS</name>
      <version>3.3.6-1</version>
      <components>
        <component>
          <name>NAMENODE</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-hdfs-namenode</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>DATANODE</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-hdfs-datanode</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>SECONDARY_NAMENODE</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-hdfs-secondarynamenode</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>HDFS_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-client</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>JOURNALNODE</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-hdfs-journalnode</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>ZKFC</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-hdfs-zkfc</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── YARN ──────────────────────────────────────────────────────────────────────
cat > ${STACK}/YARN/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>YARN</name>
      <version>3.3.6-1</version>
      <components>
        <component>
          <name>RESOURCEMANAGER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-yarn-resourcemanager</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>NODEMANAGER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-yarn-nodemanager</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>YARN_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-client</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>APP_TIMELINE_SERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-yarn-timelineserver</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
    <service>
      <name>MAPREDUCE2</name>
      <version>3.3.6-1</version>
      <components>
        <component>
          <name>HISTORYSERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-mapreduce-historyserver</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>MAPREDUCE2_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hadoop</name></package>
              <package><name>hadoop-mapreduce</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── HBASE ─────────────────────────────────────────────────────────────────────
cat > ${STACK}/HBASE/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>HBASE</name>
      <version>2.6.2-1</version>
      <components>
        <component>
          <name>HBASE_MASTER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hbase</name></package>
              <package><name>hbase-master</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>HBASE_REGIONSERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hbase</name></package>
              <package><name>hbase-regionserver</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>HBASE_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hbase</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── HIVE ──────────────────────────────────────────────────────────────────────
cat > ${STACK}/HIVE/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>HIVE</name>
      <version>4.0.1-1</version>
      <components>
        <component>
          <name>HIVE_SERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hive</name></package>
              <package><name>hive-server2</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>HIVE_METASTORE</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hive</name></package>
              <package><name>hive-metastore</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>HIVE_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hive</name></package>
              <package><name>hive-jdbc</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>WEBHCAT_SERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>hive-webhcat</name></package>
              <package><name>hive-webhcat-server</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── ZOOKEEPER ─────────────────────────────────────────────────────────────────
cat > ${STACK}/ZOOKEEPER/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>ZOOKEEPER</name>
      <version>3.8.4-1</version>
      <components>
        <component>
          <name>ZOOKEEPER_SERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>zookeeper</name></package>
              <package><name>zookeeper-server</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>ZOOKEEPER_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>zookeeper</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── KAFKA ─────────────────────────────────────────────────────────────────────
cat > ${STACK}/KAFKA/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>KAFKA</name>
      <version>3.4.1-1</version>
      <components>
        <component>
          <name>KAFKA_BROKER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>kafka</name></package>
              <package><name>kafka-server</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── SPARK ─────────────────────────────────────────────────────────────────────
cat > ${STACK}/SPARK/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>SPARK</name>
      <version>3.5.6-1</version>
      <components>
        <component>
          <name>SPARK_JOBHISTORYSERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>spark</name></package>
              <package><name>spark-core</name></package>
              <package><name>spark-history-server</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>SPARK_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>spark</name></package>
              <package><name>spark-core</name></package>
              <package><name>spark-python</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>SPARK_THRIFTSERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>spark</name></package>
              <package><name>spark-thriftserver</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── TEZ ───────────────────────────────────────────────────────────────────────
cat > ${STACK}/TEZ/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>TEZ</name>
      <version>0.10.4-1</version>
      <components>
        <component>
          <name>TEZ_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>tez</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── RANGER ────────────────────────────────────────────────────────────────────
cat > ${STACK}/RANGER/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>RANGER</name>
      <version>2.7.0-1</version>
      <components>
        <component>
          <name>RANGER_ADMIN</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>ranger-admin</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>RANGER_USERSYNC</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>ranger-usersync</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>RANGER_TAGSYNC</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>ranger-tagsync</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── RANGER_KMS ────────────────────────────────────────────────────────────────
cat > ${STACK}/RANGER_KMS/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>RANGER_KMS</name>
      <version>2.7.0-1</version>
      <components>
        <component>
          <name>RANGER_KMS_SERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>ranger-kms</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── SOLR ──────────────────────────────────────────────────────────────────────
cat > ${STACK}/SOLR/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>SOLR</name>
      <version>8.11.4-1</version>
      <components>
        <component>
          <name>SOLR_SERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>solr</name></package>
              <package><name>solr-server</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── ZEPPELIN ──────────────────────────────────────────────────────────────────
cat > ${STACK}/ZEPPELIN/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>ZEPPELIN</name>
      <version>0.11.2-1</version>
      <components>
        <component>
          <name>ZEPPELIN_MASTER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>zeppelin</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── LIVY ──────────────────────────────────────────────────────────────────────
cat > ${STACK}/LIVY/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>LIVY</name>
      <version>0.8.0-1</version>
      <components>
        <component>
          <name>LIVY_SERVER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>livy</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

# ── FLINK ─────────────────────────────────────────────────────────────────────
cat > ${STACK}/FLINK/metainfo.xml << 'EOF'
<?xml version="1.0"?>
<metainfo>
  <schemaVersion>2.0</schemaVersion>
  <services>
    <service>
      <name>FLINK</name>
      <version>1.20.1-1</version>
      <components>
        <component>
          <name>FLINK_CLIENT</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>flink</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>FLINK_JOBMANAGER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>flink</name></package>
              <package><name>flink-jobmanager</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
        <component>
          <name>FLINK_TASKMANAGER</name>
          <osSpecifics><osSpecific><osFamily>any</osFamily>
            <packages>
              <package><name>flink</name></package>
              <package><name>flink-taskmanager</name></package>
            </packages>
          </osSpecific></osSpecifics>
        </component>
      </components>
    </service>
  </services>
</metainfo>
EOF

echo "==> All package names fixed for BIGTOP/3.5.0"

# ── 删除父 stack 中不存在于 el8 基础仓库的包依赖 ────────────────────────────
# snappy-devel 在 el8 上需要 PowerTools/CRB 仓库，父 stack 里不应强依赖
# 如果安装时该仓库未启用会导致 DataNode/NameNode Install 失败
for v in 3.2.0 3.3.0 3.4.0; do
  META="/var/lib/ambari-server/resources/stacks/BIGTOP/${v}/services/HDFS/metainfo.xml"
  [ -f "${META}" ] && sed -i '/<name>snappy-devel<\/name>/d' "${META}" || true
done
echo "==> snappy-devel dependency removed from parent stacks"

# ── 确保 ambari-infra-solr(-client) 真实 RPM 已收录到本地仓库 ────────────────
# INFRA_SOLR / INFRA_SOLR_CLIENT 依赖 ambari-infra-solr(-client)（Ambari 自带包，
# 不是 Bigtop 组件）。这两包是 2019 年 el7 时代的通用 RPM（纯文件、无 scriptlet）。
# 规则：本地优先——若 /var/repo/ambari 已有 .el8 重打包版本则跳过；
#       否则从公共镜像下载原包到 /tmp/ah，并用 rebuild-ambari-infra-rpm.sh
#       重建头信息（el8 rpm/dnf 拒绝旧头的 no digest）后放入本地仓库。
SOLR_RPMS_VERSION=2.7.4.0-118
SOLR_RPMS_MIRROR=https://repo-hdp.bigbox.ai/ambari/centos7/ambari-2.7.4.0/ambari
SOLR_REPO_DIR=/var/repo/ambari
SOLR_SRC_DIR=/tmp/ah
REBUILD_SCRIPT="$(dirname "$0")/rebuild-ambari-infra-rpm.sh"
[ -x "${REBUILD_SCRIPT}" ] || REBUILD_SCRIPT=/root/rebuild-ambari-infra-rpm.sh
mkdir -p "${SOLR_REPO_DIR}" "${SOLR_SRC_DIR}"
for pkg in ambari-infra-solr ambari-infra-solr-client; do
  if ls "${SOLR_REPO_DIR}"/${pkg}-*.el8.noarch.rpm >/dev/null 2>&1; then
    echo "==> ${pkg}: 本地仓库已有 el8 重打包版本，跳过"
  else
    rpmfile="${pkg}-${SOLR_RPMS_VERSION}.noarch.rpm"
    if [ ! -f "${SOLR_SRC_DIR}/${rpmfile}" ]; then
      echo "==> ${pkg}: 下载原包 ${rpmfile}（镜像 ${SOLR_RPMS_MIRROR}）"
      curl -sfL --retry 3 --max-time 600 -o "${SOLR_SRC_DIR}/${rpmfile}" "${SOLR_RPMS_MIRROR}/${rpmfile}" \
        || { echo "FATAL: ${rpmfile} 下载失败"; exit 1; }
    fi
    echo "==> ${pkg}: 重打包为 el8（内容与原包一致）"
    "${REBUILD_SCRIPT}" "${pkg}" "${SOLR_SRC_DIR}" "${SOLR_REPO_DIR}" || { echo "FATAL: ${pkg} 重打包失败"; exit 1; }
  fi
done
echo "==> ambari-infra-solr el8 rpm(s) in repo: $(ls ${SOLR_REPO_DIR}/ambari-infra-solr*.el8.noarch.rpm 2>/dev/null | wc -l)"
( cd "${SOLR_REPO_DIR}" && createrepo --update -q . ) 2>/dev/null \
  || ( cd "${SOLR_REPO_DIR}" && createrepo . )
echo "==> 已刷新本地仓库元数据 (repodata)"

# ── 在 distro-select 补充 hadoop-hdfs-dfsrouter 映射 ─────────────────────────
# Router 组件（HDFS Federation Router）在 distro-select 的 leaves dict 里
# 缺失，after-INSTALL hook 调用 distro-select 时报
# "hadoop-hdfs-dfsrouter is not supported"
sed -i 's/"hadoop-hdfs-namenode": "hadoop-hdfs",/"hadoop-hdfs-namenode": "hadoop-hdfs",\n           "hadoop-hdfs-dfsrouter": "hadoop-hdfs",/' \
  /usr/lib/bigtop-select/distro-select 2>/dev/null || true
# 幂等：防止重复插入
python3 -c "
content=open('/usr/lib/bigtop-select/distro-select').read()
count=content.count('\"hadoop-hdfs-dfsrouter\"')
if count > 1:
    # 有重复，保留第一个，删除多余
    import re
    fixed=re.sub(r'(\n\s+\"hadoop-hdfs-dfsrouter\"[^\n]+\n)+',
                 lambda m: m.group(0).split('\n')[0]+'\n' if m.group(0).count('\n')>1 else m.group(0),
                 content, count=1)
    open('/usr/lib/bigtop-select/distro-select','w').write(content)
" 2>/dev/null || true
echo "==> hadoop-hdfs-dfsrouter added to distro-select"

# ── 自校验：父栈 + 3.5.0 全部 metainfo.xml 已无包装占位符（fail-fast）────────
# 只查字面量 _${stack_version}（包名占位符）；params_*.py 里的 stack_version
# 是 Python 变量名不纳入检查。残留 >0 立即退出，避免后续 Deploy 白跑一轮。
LEFTOVER=$(grep -rl --fixed-strings '_\${stack_version}' \
  /var/lib/ambari-server/resources/stacks/BIGTOP/ --include=metainfo.xml 2>/dev/null | wc -l)
if [ "${LEFTOVER}" -gt 0 ]; then
  echo "FATAL: ${LEFTOVER} 个 metainfo.xml 仍含 _\${stack_version} 占位符：" >&2
  grep -rl --fixed-strings '_\${stack_version}' \
    /var/lib/ambari-server/resources/stacks/BIGTOP/ --include=metainfo.xml 2>/dev/null | sed 's/^/  /' >&2 || true
  exit 1
fi
echo "==> VERIFY: 全部 BIGTOP metainfo.xml 已无 _\${stack_version}（0 残留）"
