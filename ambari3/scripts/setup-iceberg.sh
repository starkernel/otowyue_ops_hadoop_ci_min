#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: setup-iceberg.sh
# 文件功能: 幂等部署/恢复 Iceberg 数据湖与 Spark 前置配置（JDK17 + Hadoop Catalog）
#   - 部署 iceberg-spark-runtime jar 到所有 Spark 节点的 $SPARK_HOME/jars
#   - spark-env.sh JAVA_HOME 切换为 JDK17（Iceberg 1.11 需 Java17 编译类）
#   - spark-defaults.conf 注入 Iceberg hadoop catalog 配置（避免 Java17+Hive3.1 冲突）
#   - 修复 Ambari spark-defaults 里无效的 hive.metastore.version=4.0.1
#   - Ambari desired_configs 对齐（spark-defaults/spark-env/hdfs-site）
#   - 确保 HDFS /iceberg-warehouse 存在
# 版    本: V1.0
# 编制日期: 2026年9月
# 使用方法:
#   在宿主机 ambari3/ 目录下执行：
#   ./scripts/setup-iceberg.sh
# 依赖:
#   - 容器 bigtop_hostname0 / bigtop_hostname3 运行中（Spark 节点）
#   - jar 位于与脚本同级的 ambari-repo/ 目录
# 幂等性: 可重复执行，操作均带存在性/一致性检查，无副作用
# ============================================================
set -euo pipefail

SPARK_NODES="bigtop_hostname0 bigtop_hostname3"
JAR_NAME="iceberg-spark-runtime-3.5_2.12-1.11.0.jar"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAR_PATH="${SCRIPT_DIR}/../ambari-repo/${JAR_NAME}"

AMBARI_PORT="20609"
AMBARI_API="http://localhost:${AMBARI_PORT}/api/v1"
CLUSTER_NAME=$(curl -s -u admin:admin "${AMBARI_API}/clusters" | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d.get('items',[])
if items: print(items[0]['Clusters']['cluster_name'])
" 2>/dev/null)
[ -z "${CLUSTER_NAME}" ] && CLUSTER_NAME="qixuandata"

SPARK_DEFAULTS_TAG="iceberg-hadoopcat"
SPARK_ENV_TAG="jdk17"
HDFS_SITE_TAG="datanode-hostname"
ICEBERG_WAREHOUSE="hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse"

ok()     { echo -e "\033[32m[ OK ]\033[0m  $*"; }
warn()   { echo -e "\033[33m[WARN]\033[0m  $*"; }
info()   { echo -e "\033[36m[INFO]\033[0m  $*"; }
section(){ echo -e "\n\033[33m════ $* ════\033[0m"; }

# ════════════════════════════════════════════════════════════
# 1) 部署 iceberg runtime jar 到每台 Spark 节点
# ════════════════════════════════════════════════════════════
section "1) 部署 Iceberg jar 到 SPARK_HOME/jars"
if [ ! -f "${JAR_PATH}" ]; then
  warn "jar 不存在: ${JAR_PATH}，跳过部署" 
else
  for h in ${SPARK_NODES}; do
    EXIST=$(docker compose exec "${h}" bash -c \
      "sha256sum /usr/lib/spark/jars/${JAR_NAME} 2>/dev/null | awk '{print \$1}'" 2>/dev/null || true)
    LOCAL=$(sha256sum "${JAR_PATH}" | awk '{print $1}')
    if [ "${EXIST}" = "${LOCAL}" ]; then
      ok "${h}: jar 已存在且一致"
    else
      docker compose cp "${JAR_PATH}" "${h}:/usr/lib/spark/jars/${JAR_NAME}" >/dev/null
      docker compose exec "${h}" chown hive:spark "/usr/lib/spark/jars/${JAR_NAME}"
      ok "${h}: jar 已部署"
    fi
  done
fi

# ════════════════════════════════════════════════════════════
# 2) spark-env.sh JAVA_HOME → JDK17（Iceberg 1.11 需 Java 17）
#    Bigtop 默认 java-1.8.0-openjdk，Iceberg ExtendedParser 等类
#    编译为 class major 61，Java8(52) 无法加载
# ════════════════════════════════════════════════════════════
section "2) spark-env.sh JAVA_HOME → JDK17"
for h in ${SPARK_NODES}; do
  docker compose exec "${h}" bash -c '
    F=/etc/spark/conf.dist/spark-env.sh
    if ! grep -q "JAVA_HOME=/usr/lib/jvm/java-17-openjdk" "$F"; then
      sed -i "s|export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk|export JAVA_HOME=/usr/lib/jvm/java-17-openjdk|" "$F"
      echo "  '"$h"': JAVA_HOME set to JDK17"
    else
      echo "  '"$h"': JAVA_HOME already JDK17"
    fi
  ' 2>/dev/null | tail -1
done

# ════════════════════════════════════════════════════════════
# 3) spark-defaults.conf 注入 Iceberg hadoop catalog 配置段
#    说明: Iceberg 1.11 (Java17) 与 Hive 3.1 client (Java8-era,
#          NoSuchFieldError:out) 冲突，因此采用 Hadoop Catalog +
#          in-memory session，避开 Hive client 初始化。
# ════════════════════════════════════════════════════════════
section "3) spark-defaults.conf Iceberg 配置段"
ICE_CONF='
# === Iceberg data lake (managed by setup-iceberg.sh, tag=iceberg-hadoopcat) ===
spark.sql.catalog.iceberg org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.iceberg.type hadoop
spark.sql.catalog.iceberg.warehouse '${ICEBERG_WAREHOUSE}'
spark.sql.extensions org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.sql.catalogImplementation in-memory
spark.yarn.appMasterEnv.JAVA_HOME /usr/lib/jvm/java-17-openjdk
spark.executorEnv.JAVA_HOME /usr/lib/jvm/java-17-openjdk
spark.sql.hive.metastore.version 3.1.3
'
for h in ${SPARK_NODES}; do
  docker compose exec "${h}" bash -c '
    F=/etc/spark/conf.dist/spark-defaults.conf
    WH="'"${ICEBERG_WAREHOUSE}"'"
    python3 - <<PYEOF
f = "$F"
wh = "$WH"
block = [
  "",
  "# === Iceberg data lake (managed by setup-iceberg.sh, tag=iceberg-hadoopcat) ===",
  "spark.sql.catalog.iceberg org.apache.iceberg.spark.SparkCatalog",
  "spark.sql.catalog.iceberg.type hadoop",
  "spark.sql.catalog.iceberg.warehouse " + wh,
  "spark.sql.extensions org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
  "spark.sql.catalogImplementation in-memory",
  "spark.yarn.appMasterEnv.JAVA_HOME /usr/lib/jvm/java-17-openjdk",
  "spark.executorEnv.JAVA_HOME /usr/lib/jvm/java-17-openjdk",
  "spark.sql.hive.metastore.version 3.1.3",
  "",
]
MARK = "# === Iceberg data lake"
lines = open(f).read().splitlines()
out = []
skip = False
for ln in lines:
    if ln.strip().startswith(MARK):
        skip = True
        continue
    if skip and ln.strip() == "":
        skip = False
        continue
    if skip:
        continue
    s = ln.lstrip()
    if s.startswith("spark.sql.catalog.iceberg ") or \
       s.startswith("spark.sql.catalog.iceberg.type ") or \
       s.startswith("spark.sql.catalog.iceberg.uri ") or \
       s.startswith("spark.sql.catalog.iceberg.warehouse ") or \
       s.startswith("spark.sql.catalog.spark_catalog") or \
       s.startswith("spark.sql.catalog.spark_catalog.type") or \
       s.startswith("spark.sql.catalogImplementation "):
        continue
    out.append(ln)
out.extend(block)
seen = set(); final = []
for ln in out:
    s = ln.strip()
    if s and not ln.lstrip().startswith("#") and s in seen:
        continue
    seen.add(s); final.append(ln)
open(f, "w").write("\n".join(final) + "\n")
print("OK")
PYEOF
  ' 2>/dev/null | grep -q OK && ok "${h}: Iceberg conf applied" \
    || warn "${h}: Iceberg conf 应用失败"
done

# ════════════════════════════════════════════════════════════
# 4) 对齐 Ambari 配置 tag + desired_configs（持久化，Ambari 重配时保持）
#    若目标 tag 不存在，则基于当前 desired tag 派生并写入
#    （含 hdfs-site dfs.replication=1 + datanode hostname 前置修复）
# ════════════════════════════════════════════════════════════
section "4) Ambari 配置 tag + desired_configs 对齐"

ensure_config() {
  # $1=type $2=target_tag $3=pickle(JSON) of property overrides
  local type="$1" target_tag="$2" overrides="$3"
  local exists cur_tag
  exists=$(curl -s -u admin:admin "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=${type}&tag=${target_tag}" \
    | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print('yes' if d.get('items') else 'no')
except: print('no')" 2>/dev/null)
  if [ "${exists}" = "yes" ]; then
    ok "config ${type}/${target_tag} 已存在"
    return 0
  fi
  # 取当前 desired tag 的属性作为基础
  cur_tag=$(curl -s -u admin:admin "${AMBARI_API}/clusters/${CLUSTER_NAME}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
dc=d.get('Clusters',{}).get('desired_configs',{})
print(dc.get('${type}',{}).get('tag',''))" 2>/dev/null)
  if [ -z "${cur_tag}" ]; then
    warn "无法定位 ${type} 当前 tag，跳过创建 ${target_tag}"
    return 1
  fi
  curl -s -u admin:admin "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=${type}&tag=${cur_tag}" > /tmp/ice_base_${type}.json
  # 用 python 合并 overrides 并写 payload
  python3 - "${type}" "${target_tag}" "${overrides}" <<'PYEOF'
import json,sys
typ,tag,overrides=sys.argv[1],sys.argv[2],json.loads(sys.argv[3])
d=json.load(open('/tmp/ice_base_%s.json' % typ))
props=dict(d['items'][0]['properties'])
props.update({k:(str(v) if not isinstance(v,str) else v) for k,v in overrides.items()})
json.dump({'type':typ,'tag':tag,'properties':props}, open('/tmp/ice_new_%s.json' % typ,'w'))
print('payload ready')
PYEOF
  local http
  http=$(curl -s -u admin:admin -X POST -H "X-Requested-By: ambari" -H "Content-Type: application/json" \
    -d @/tmp/ice_new_${type}.json -o /dev/null -w "%{http_code}" \
    "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations")
  if [ "${http}" = "201" ] || [ "${http}" = "200" ]; then
    ok "config ${type}/${target_tag} 已创建 (HTTP ${http})"
  else
    warn "config ${type}/${target_tag} 创建失败 HTTP=${http}"
    return 1
  fi
}

ensure_config hdfs-site "${HDFS_SITE_TAG}" \
  '{"dfs.replication":"1","dfs.datanode.use.datanode.hostname":"true","dfs.client.use.datanode.hostname":"true"}'
ensure_config spark-defaults "${SPARK_DEFAULTS_TAG}" \
  '{"spark.sql.catalog.iceberg":"org.apache.iceberg.spark.SparkCatalog","spark.sql.catalog.iceberg.type":"hadoop","spark.sql.catalog.iceberg.warehouse":"'"${ICEBERG_WAREHOUSE}"'","spark.sql.extensions":"org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions","spark.sql.catalogImplementation":"in-memory","spark.yarn.appMasterEnv.JAVA_HOME":"/usr/lib/jvm/java-17-openjdk","spark.executorEnv.JAVA_HOME":"/usr/lib/jvm/java-17-openjdk","spark.sql.hive.metastore.version":"3.1.3"}'
# spark-env: 仅需修改 content 里 JAVA_HOME 模板 -> 已由步骤 2 直接改文件，此处确保 tag 存在
if ! curl -s -u admin:admin "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=spark-env&tag=${SPARK_ENV_TAG}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('items') else 'no')" 2>/dev/null | grep -q yes; then
  cur_tag=$(curl -s -u admin:admin "${AMBARI_API}/clusters/${CLUSTER_NAME}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
dc=d.get('Clusters',{}).get('desired_configs',{})
print(dc.get('spark-env',{}).get('tag',''))" 2>/dev/null)
  curl -s -u admin:admin "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=spark-env&tag=${cur_tag}" > /tmp/ice_base_spark-env.json
  python3 - <<'PYEOF'
import json
d=json.load(open('/tmp/ice_base_spark-env.json'))
props=dict(d['items'][0]['properties'])
c=props.get('content','')
c=c.replace('export JAVA_HOME={{java_home}}','export JAVA_HOME=/usr/lib/jvm/java-17-openjdk')
props['content']=c
json.dump({'type':'spark-env','tag':'jdk17','properties':props}, open('/tmp/ice_new_spark-env.json','w'))
print('spark-env payload ready')
PYEOF
  http=$(curl -s -u admin:admin -X POST -H "X-Requested-By: ambari" -H "Content-Type: application/json" \
    -d @/tmp/ice_new_spark-env.json -o /dev/null -w "%{http_code}" \
    "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations")
  [ "${http}" = "201" ] || [ "${http}" = "200" ] && ok "config spark-env/${SPARK_ENV_TAG} 已创建" \
    || warn "config spark-env/${SPARK_ENV_TAG} 创建失败 HTTP=${http}"
else
  ok "config spark-env/${SPARK_ENV_TAG} 已存在"
fi

DESIRED='{"Clusters":{"desired_configs":{"spark-defaults":{"type":"spark-defaults","tag":"'${SPARK_DEFAULTS_TAG}'"},"spark-env":{"type":"spark-env","tag":"'${SPARK_ENV_TAG}'"},"hdfs-site":{"type":"hdfs-site","tag":"'${HDFS_SITE_TAG}'"}}}}'
CUR=$(curl -s -u admin:admin "${AMBARI_API}/clusters/${CLUSTER_NAME}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
dc=d.get('Clusters',{}).get('desired_configs',{})
need=[]
for t,tag in [('spark-defaults','${SPARK_DEFAULTS_TAG}'),('spark-env','${SPARK_ENV_TAG}'),('hdfs-site','${HDFS_SITE_TAG}')]:
    if dc.get(t,{}).get('tag') != tag: need.append(t)
print(','.join(need))
" 2>/dev/null)
if [ -z "${CUR}" ]; then
  ok "Ambari desired_configs 已是目标 tag（${SPARK_DEFAULTS_TAG}/${SPARK_ENV_TAG}/${HDFS_SITE_TAG}）"
else
  curl -s -u admin:admin -X PUT -H "X-Requested-By: ambari" -H "Content-Type: application/json" \
    -d "${DESIRED}" "${AMBARI_API}/clusters/${CLUSTER_NAME}" >/dev/null && \
    ok "Ambari desired_configs 已对齐: ${CUR}"
fi

# ════════════════════════════════════════════════════════════
# 5) 确保 HDFS /iceberg-warehouse（yarn 可写）
# ════════════════════════════════════════════════════════════
section "5) HDFS /iceberg-warehouse 目录"
docker compose exec bigtop_hostname0 bash -c '
  export HADOOP_USER_NAME=hdfs
  if ! hdfs dfs -stat /iceberg-warehouse >/dev/null 2>&1; then
    hdfs dfs -mkdir -p /iceberg-warehouse
    echo "  warehouse created"
  else
    echo "  warehouse exists"
  fi
  hdfs dfs -chown -R yarn:hdfs /iceberg-warehouse >/dev/null 2>&1 || true
' 2>/dev/null | tail -1

section "Iceberg setup complete. 提交 Spark 作业时无需额外配置。"