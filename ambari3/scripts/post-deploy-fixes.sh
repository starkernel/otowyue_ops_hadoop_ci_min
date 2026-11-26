#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: post-deploy-fixes.sh
# 文件功能: Ambari Web UI 完成集群创建向导（Deploy）后的修复脚本
#   解决 Ambari 3.1.0 + Bigtop 3.5.0 在 Deploy 阶段
#   暴露的所有已知兼容性问题，保证 Retry 后能成功完成安装。
# 版    本: V1.0
# 编制日期: 2026年9月
# 使用方法:
#   在宿主机 ambari3/ 目录下执行：
#   ./scripts/post-deploy-fixes.sh [cluster_name]
#   cluster_name 默认自动从 Ambari API 获取
# ============================================================

set -euo pipefail

AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${YELLOW}════ $* ════${NC}"; }

AMBARI_API="http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1"

# ── 自动获取集群名 ────────────────────────────────────────────────────────────
if [ -z "${CLUSTER_NAME}" ]; then
  CLUSTER_NAME=$(curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
    "${AMBARI_API}/clusters" | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d.get('items',[])
if items: print(items[0]['Clusters']['cluster_name'])
" 2>/dev/null)
  if [ -z "${CLUSTER_NAME}" ]; then
    echo -e "${RED}[ERROR]${NC} 无法获取集群名，请确认 Ambari Server 已启动且集群已创建"
    exit 1
  fi
fi

info "目标集群: ${CLUSTER_NAME}"

# ════════════════════════════════════════════════════════════
# Fix 1: 所有节点建 dummy chronyd 服务
#   问题: 容器内无硬件时钟，Ambari Agent 检查 ntpd/chronyd
#         服务状态上报 UNHEALTHY，导致 Server 拒绝下发 Install 任务
# ════════════════════════════════════════════════════════════
section "Fix 1: 所有节点建 dummy chronyd 服务（Agent UNHEALTHY 修复）"

CHRONYD_UNIT='[Unit]
Description=Dummy NTP service for Ambari health check (HodoopForge)
[Service]
ExecStart=/bin/true
RemainAfterExit=yes
Type=oneshot
[Install]
WantedBy=multi-user.target'

for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  info "  ${h}: 安装 dummy chronyd..."
  docker exec "${h}" bash -c "
    printf '%s\n' '${CHRONYD_UNIT}' > /etc/systemd/system/chronyd.service
    systemctl daemon-reload
    systemctl enable chronyd 2>/dev/null || true
    systemctl start chronyd  2>/dev/null || true
    systemctl is-active chronyd
  " 2>&1 | tail -1 | grep -q "active" && ok "  ${h}: chronyd active" \
    || warn "  ${h}: chronyd 启动异常，检查 systemctl status chronyd"
done

# ════════════════════════════════════════════════════════════
# Fix 2: stack_packages 补 APP_TIMELINE_SERVER 映射
#   问题: cluster-env 的 stack_packages 里 YARN 下缺少
#         APP_TIMELINE_SERVER 条目，stack-select 找不到映射
#         直接 abort，导致 Timeline Service V2 Install 失败
# ════════════════════════════════════════════════════════════
section "Fix 2: 补充 APP_TIMELINE_SERVER stack-select 映射"

# 获取当前 cluster-env tag
CE_TAG=$(curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
  "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=cluster-env" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d.get('items',[])
if items: print(items[-1]['tag'])
" 2>/dev/null)

if [ -z "${CE_TAG}" ]; then
  warn "无法获取 cluster-env tag，跳过 Fix 2"
else
  info "cluster-env tag: ${CE_TAG}"
  # 读取当前配置并补充条目
  PATCH_RESULT=$(curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
    "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=cluster-env&tag=${CE_TAG}" \
    | python3 -c "
import json,sys

d=json.load(sys.stdin)
props=d['items'][0]['properties']
sp=json.loads(props.get('stack_packages','{}'))

yarn=sp.get('BIGTOP',{}).get('stack-select',{}).get('YARN',{})

fixes={}

# APP_TIMELINE_SERVER (YARN Timeline Service V1/V2)
if 'APP_TIMELINE_SERVER' not in yarn:
    fixes['APP_TIMELINE_SERVER']={
        'STACK-SELECT-PACKAGE':'hadoop-yarn-timelineserver',
        'INSTALL':['hadoop-yarn-timelineserver','hadoop-client'],
        'PATCH':['hadoop-yarn-timelineserver'],
        'STANDARD':['hadoop-yarn-timelineserver']
    }

# TIMELINE_READER (YARN Timeline Service V2 Reader)
if 'TIMELINE_READER' not in yarn:
    fixes['TIMELINE_READER']={
        'STACK-SELECT-PACKAGE':'hadoop-yarn-timelinereader',
        'INSTALL':['hadoop-yarn-timelinereader','hadoop-client'],
        'PATCH':['hadoop-yarn-timelinereader'],
        'STANDARD':['hadoop-yarn-timelinereader']
    }

if not fixes:
    print('SKIP')
    sys.exit(0)

sp.setdefault('BIGTOP',{}).setdefault('stack-select',{}).setdefault('YARN',{}).update(fixes)
props['stack_packages']=json.dumps(sp)

payload={
    'Clusters':{
        'desired_configs':{
            'type':'cluster-env',
            'tag':'post-deploy-fixes-ats',
            'properties':props
        }
    }
}
print(json.dumps(payload))
" 2>/dev/null)

  if [ "${PATCH_RESULT}" = "SKIP" ]; then
    ok "APP_TIMELINE_SERVER 映射已存在，无需修复"
  elif [ -n "${PATCH_RESULT}" ]; then
    HTTP=$(echo "${PATCH_RESULT}" | curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
      -X PUT -H "X-Requested-By: ambari" -H "Content-Type: application/json" \
      -d @- -o /dev/null -w "%{http_code}" \
      "${AMBARI_API}/clusters/${CLUSTER_NAME}")
    [ "${HTTP}" = "200" ] || [ "${HTTP}" = "201" ] || [ -z "${HTTP}" ] \
      && ok "APP_TIMELINE_SERVER + TIMELINE_READER 映射已写入" \
      || warn "写入失败 HTTP=${HTTP}"
  else
    warn "无法生成 patch，跳过"
  fi
fi

# ════════════════════════════════════════════════════════════
# Fix 3: 修复 Ambari Server stack_id=0 问题（EclipseLink 拒绝）
#   问题: INSERT IGNORE + NULL 主键可能让 BIGTOP 3.5.0 拿到
#         stack_id=0，EclipseLink JPA 把 0 当 null 拒绝持久化
#         导致 VDF 上传时抛 ValidationException
# ════════════════════════════════════════════════════════════
section "Fix 3: 修复 BIGTOP 3.5.0 stack_id=0 问题"

docker exec bigtop_hostname0 bash -c "
  mysql -uambari -pambari -e '
    use ambari;
    SELECT stack_id, stack_version FROM stack WHERE stack_name=\"BIGTOP\" AND stack_version=\"3.5.0\";
  ' 2>/dev/null | grep -v Warning
" | grep -q "^0" && {
  info "  检测到 stack_id=0，修正为 10..."
  docker exec bigtop_hostname0 bash -c "
    mysql -uambari -pambari -e '
      use ambari;
      SET FOREIGN_KEY_CHECKS=0;
      UPDATE stack SET stack_id=10 WHERE stack_id=0 AND stack_name=\"BIGTOP\" AND stack_version=\"3.5.0\";
      UPDATE repo_version SET stack_id=10 WHERE stack_id=0;
      SET FOREIGN_KEY_CHECKS=1;
    ' 2>/dev/null | grep -v Warning
  "
  ok "stack_id 已修正为 10"
} || ok "stack_id 正常，无需修复"

# ════════════════════════════════════════════════════════════
# Fix 3b: 清理所有节点 Agent cache 里残留的 ${stack_version} 包名
#   问题: Agent cache 是 Server 下发的旧版 metainfo，包含
#         hadoop_${stack_version} 等占位符，fix-package-names.sh
#         只修了 Server 端，Agent cache 需单独清理
# ════════════════════════════════════════════════════════════
section "Fix 3b: 清理所有节点 Agent cache 中的 \${stack_version} 占位符"

for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  COUNT=$(docker exec "${h}" grep -r 'stack_version' \
    /var/lib/ambari-agent/cache/stacks/ 2>/dev/null | grep '<name>' | wc -l)
  if [ "${COUNT}" -gt 0 ]; then
    docker exec "${h}" bash -c "
      find /var/lib/ambari-agent/cache/stacks/ -name 'metainfo.xml' | \
        xargs grep -l 'stack_version' 2>/dev/null | while read f; do
          sed -i 's/_\${stack_version}//g' \"\$f\"
          sed -i 's/\${stack_version}_//g' \"\$f\"
          sed -i 's/\${stack_version}//g' \"\$f\"
          sed -i 's/_-/-/g' \"\$f\"
        done
    " 2>/dev/null
    ok "  ${h}: 已清理 ${COUNT} 处 \${stack_version}"
  else
    ok "  ${h}: 无残留，跳过"
  fi
done

# ════════════════════════════════════════════════════════════
# Fix 3c: 确保所有节点安装了 JDK8（before-ANY hook 依赖）
#   问题: Agent 的 before-ANY hook 检查 java-1.8.0-openjdk，
#         hostname2/3 为纯 Agent 节点，若 JDK 未安装则所有
#         install 任务都会因 hook 失败而报错
# ════════════════════════════════════════════════════════════
section "Fix 3c: 确保所有节点安装 JDK8 + JDK17"

for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  MISSING=$(docker exec "${h}" bash -c "
    [ -f /usr/lib/jvm/java-1.8.0-openjdk/bin/java ] && \
    [ -f /usr/lib/jvm/java-17-openjdk/bin/java ] && echo OK || echo MISSING
  " 2>/dev/null)
  if [ "${MISSING}" = "MISSING" ]; then
    info "  ${h}: 安装 JDK..."
    docker exec "${h}" bash -c \
      "dnf install -y java-17-openjdk-devel java-1.8.0-openjdk-devel 2>&1 | tail -1" \
      2>/dev/null
    ok "  ${h}: JDK 安装完成"
  else
    ok "  ${h}: JDK 已存在"
  fi
done

# ════════════════════════════════════════════════════════════
# Fix 3d: 在 Server 磁盘重放 fix-package-names.sh（必须在 Fix 7 重启 Server 之前）
#   问题: 包名来自 Server 端 metainfo.xml，只修 Agent cache（Fix 3b）不够。
#         容器重启后 /var/lib/ambari-server/resources/stacks 恢复原始状态，
#         ${stack_version} 占位符重现。必须在 ambari-server restart（Fix 7）
#         之前修好磁盘并自校验，否则重启加载的还是脏栈，Retry 仍失败。
# ════════════════════════════════════════════════════════════
section "Fix 3d: 重放 fix-package-names.sh（Server 磁盘 metainfo 清理 + 自校验）"

POST_DIR="$(cd "$(dirname "$0")" && pwd)"
docker cp "${POST_DIR}/fix-package-names.sh" bigtop_hostname0:/root/fix-package-names.sh
docker exec bigtop_hostname0 bash /root/fix-package-names.sh
LEFTOVER=$(docker exec bigtop_hostname0 bash -c \
  "grep -rl --fixed-strings '_\${stack_version}' /var/lib/ambari-server/resources/stacks/BIGTOP/ --include=metainfo.xml 2>/dev/null | wc -l" || true)
if [ "${LEFTOVER:-1}" -gt 0 ]; then
  echo -e "${RED}[ERROR]${NC} Server 磁盘仍有 ${LEFTOVER:-?} 个 metainfo.xml 含 _\${stack_version}"
  exit 1
fi
ok "Server 磁盘 metainfo 校验通过（0 残留）"

# ════════════════════════════════════════════════════════════
# Fix 3e: 重建所有节点 /usr/bigtop/3.5.0/usr/lib 软链接
#   问题: /usr/bigtop/current/<pkg> -> /usr/bigtop/3.5.0/usr/lib/<pkg> -> /usr/lib/<pkg>
#         第二层软链接缺失/悬空时，YARN_CLIENT/MAPREDUCE2_CLIENT/HIVE_CLIENT 等
#         install 会报 parent directory /usr/bigtop/current/<pkg>/bin doesn't exist
#         （HIVE_CLIENT 另报 cp 到 hive-client/lib 失败）。容器重启或重建后必现。
#         START 阶段同样依赖该链：ranger-tagsync 启动时类路径
#         /usr/bigtop/current/ranger-tagsync/lib/* 悬空会导致
#         Could not find or load main class org.apache.ranger.credentialapi.buildks
#         （buildks 实际位于 /usr/lib/ranger-tagsync/lib/credentialbuilder-*.jar）。
#         ranger 包（尤其后装的 tagsync）常缺失中层与顶层链，需两层都补。
# ════════════════════════════════════════════════════════════
section "Fix 3e: 重建所有节点 /usr/bigtop/3.5.0/usr/lib 软链接"

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
TARGET=/usr/bigtop/3.5.0/usr/lib/hive-webhcat
[ -d "${TARGET}" ] && [ ! -L "${TARGET}" ] && rmdir "${TARGET}" 2>/dev/null || true
[ -d /usr/lib/hive-hcatalog ] && ln -sfn /usr/lib/hive-hcatalog ${TARGET} 2>/dev/null || true
for pkg in $(ls /usr/lib/ 2>/dev/null | grep -E "^ranger"); do
  TARGET=/usr/bigtop/3.5.0/usr/lib/${pkg}
  if [ -d "${TARGET}" ] && [ ! -L "${TARGET}" ]; then
    rmdir "${TARGET}" 2>/dev/null || true
  fi
  ln -sfn /usr/lib/${pkg} ${TARGET} 2>/dev/null || true
  ln -sfn ${TARGET} /usr/bigtop/current/${pkg} 2>/dev/null || true
done
echo "symlinks: $(ls /usr/bigtop/3.5.0/usr/lib/ | wc -l)"
'
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  docker exec "${h}" bash -c "${REBUILD_SYMLINKS}" 2>/dev/null
  ok "  ${h}: /usr/bigtop/3.5.0/usr/lib 软链接已重建"
done

# ════════════════════════════════════════════════════════════
# Fix 3f: 所有节点 distro-select 补充 hadoop-hdfs-dfsrouter 映射
#   HDFS Federation Router 组件缺失该映射时，after-INSTALL hook 报
#   "The package hadoop-hdfs-dfsrouter is not supported by this
#   version of the stack-select tool." 只在 Server（fix-package-names）
#   补丁不够，agent 节点必须各自补。
# ════════════════════════════════════════════════════════════
section "Fix 3f: 各节点 distro-select 补充 hadoop-hdfs-dfsrouter 映射"
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  docker exec "${h}" bash -c \
    'sed -i "s/\"hadoop-hdfs-namenode\": \"hadoop-hdfs\",/\"hadoop-hdfs-namenode\": \"hadoop-hdfs\",\n           \"hadoop-hdfs-dfsrouter\": \"hadoop-hdfs\",/" /usr/lib/bigtop-select/distro-select 2>/dev/null'
  CNT=$(docker exec "${h}" bash -c "grep -c 'hadoop-hdfs-dfsrouter' /usr/lib/bigtop-select/distro-select" 2>/dev/null || echo 0)
  ok "  ${h}: distro-select dfsrouter 映射 = ${CNT}"
done

# ════════════════════════════════════════════════════════════
# Fix 4: 修复 Bigtop stack service_advisor.py hive.exec.post.hooks bug
#   问题: Bigtop 3.2.0 base stack 的 service_advisor.py 在无 hooks 时
#         返回 " "（空格）而非 ""，Hive 4.0.1 尝试加载空格类名抛 ClassNotFoundException
# ════════════════════════════════════════════════════════════
section "Fix 4: 修复 Hive service_advisor.py hooks 空格 bug"

docker exec bigtop_hostname0 bash -c "
  SA='/var/lib/ambari-server/resources/stacks/BIGTOP/3.2.0/services/HIVE/service_advisor.py'
  if grep -q 'hooks_value = \" \"' \"\$SA\" 2>/dev/null; then
    sed -i 's/hooks_value = \" \" if len(hive_hooks) == 0/hooks_value = \"\" if len(hive_hooks) == 0/g' \"\$SA\"
    sed -i 's/hooks_value = \" \"\$/hooks_value = \"\"/g' \"\$SA\"
    find \$(dirname \$SA) -name '*.pyc' -delete 2>/dev/null || true
    echo 'FIXED'
  else
    echo 'OK'
  fi
" | grep -q "FIXED" && ok "service_advisor.py hooks bug 已修复" \
  || ok "service_advisor.py hooks bug 已是正确状态"

# ════════════════════════════════════════════════════════════
# Fix 5: 修复 Agent hive_check.py auth=noSasl 兼容性问题
#   问题: Hive 4.0.1 只认 auth=none，Ambari Agent 用 auth=noSasl
#         导致健康检查失败，触发 Ambari 反复重启 Hive 服务
# ════════════════════════════════════════════════════════════
section "Fix 5: 修复 Hive Agent hive_check.py auth 参数（所有节点）"

for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  RESULT=$(docker exec "${h}" bash -c "
    HC='/usr/lib/ambari-agent/lib/resource_management/libraries/functions/hive_check.py'
    if [ -f \"\$HC\" ] && grep -q 'noSasl' \"\$HC\"; then
      sed -i 's/beeline_url.append(\"auth=noSasl\")/beeline_url.append(\"auth=none\")/g' \"\$HC\"
      echo FIXED
    else
      echo OK
    fi
  " 2>/dev/null)
  [ "${RESULT}" = "FIXED" ] && ok "  ${h}: hive_check.py 已修复" \
    || info "  ${h}: hive_check.py 已是正确状态"
done

# ════════════════════════════════════════════════════════════
# Fix 6: repoinfo.xml / metainfo.xml 清理遗留注释行
#   问题: setup-bigtop-stack.sh 早期版本在 heredoc 里混入 # >>> 注释
#         写入 XML 后导致解析失败，Ambari 显示为 3.4.0 而非 3.5.0
# ════════════════════════════════════════════════════════════
section "Fix 6: 修复 BIGTOP/3.5.0 stack XML 文件（清理注释行）"

docker exec bigtop_hostname0 bash -c "
  STACK_HOME='/var/lib/ambari-server/resources/stacks/BIGTOP/3.5.0'

  # metainfo.xml
  META='\${STACK_HOME}/metainfo.xml'
  if grep -q '^#' \"\${META}\" 2>/dev/null || ! grep -q '</metainfo>' \"\${META}\" 2>/dev/null; then
    printf '%s\n' \
      '<?xml version=\"1.0\"?>' \
      '<metainfo>' \
      '  <versions><active>true</active></versions>' \
      '  <extends>3.4.0</extends>' \
      '</metainfo>' > \"\${META}\"
    python3 -c \"import xml.etree.ElementTree as ET; ET.parse('\${META}'); print('metainfo.xml OK')\"
    echo 'FIXED_META'
  else
    echo 'OK_META'
  fi

  # repoinfo.xml
  REPO='\${STACK_HOME}/repos/repoinfo.xml'
  if grep -q '^#' \"\${REPO}\" 2>/dev/null || ! grep -q '</reposinfo>' \"\${REPO}\" 2>/dev/null; then
    printf '%s\n' \
      '<?xml version=\"1.0\"?>' \
      '<reposinfo>' \
      '  <latest>http://bigtop_hostname0/repodata/repomd.xml</latest>' \
      '  <os family=\"redhat8\">' \
      '    <repo>' \
      '      <baseurl>http://bigtop_hostname0</baseurl>' \
      '      <repoid>BIGTOP-3.5.0</repoid>' \
      '      <reponame>Bigtop 3.5.0</reponame>' \
      '      <unique>true</unique>' \
      '    </repo>' \
      '  </os>' \
      '</reposinfo>' > \"\${REPO}\"
    python3 -c \"import xml.etree.ElementTree as ET; ET.parse('\${REPO}'); print('repoinfo.xml OK')\"
    echo 'FIXED_REPO'
  else
    echo 'OK_REPO'
  fi
" 2>&1 | while read line; do
  case "${line}" in
    FIXED_META) ok "metainfo.xml 注释行已清理" ;;
    OK_META)    ok "metainfo.xml 格式正常" ;;
    FIXED_REPO) ok "repoinfo.xml 注释行已清理" ;;
    OK_REPO)    ok "repoinfo.xml 格式正常" ;;
    *OK*)       ok "${line}" ;;
    *) info "  ${line}" ;;
  esac
done

# ════════════════════════════════════════════════════════════
# Fix 6b: Flink 跨主机配置（JobManager 作为 RPC/REST 地址）
#   问题: Bigtop Flink 模板默认 jobmanager.rpc.address / rest.address
#         = localhost，若 JobManager 与 TaskManager 部署在不同主机，
#         TM 无法连上 JM。需把 RPC/REST 地址改写为 JM 所在主机，
#         并把 bind-host 改为 0.0.0.0 以接受外部连接。
#   注意: 本修复依赖 FLINK_JOBMANAGER 已部署（Ambari 中已添加组件），
#         若未部署则跳过。仅当配置值正确时保持幂等。
# ════════════════════════════════════════════════════════════
section "Fix 6b: Flink 跨主机配置（jobmanager.rpc.address → JM 主机）"

FLINK_FC_TAG=$(curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
  "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=flink-conf" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d.get('items',[])
if items: print(items[-1]['tag'])
" 2>/dev/null)

if [ -z "${FLINK_FC_TAG}" ]; then
  info "  flink-conf 配置尚不存在（Flink 未安装），跳过 Fix 6b"
else
  # 定位 FLINK_JOBMANAGER 所在主机
  JM_HOST=$(curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
    "${AMBARI_API}/clusters/${CLUSTER_NAME}/services/FLINK/components/FLINK_JOBMANAGER?fields=host_components/HostRoles/host_name" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
hosts=[h['HostRoles']['host_name'] for h in d.get('host_components',[])]
print(hosts[0] if hosts else '')
" 2>/dev/null)
  [ -n "${JM_HOST}" ] && JM_HOST_FQDN="${JM_HOST}" || JM_HOST_FQDN=""

  if [ -z "${JM_HOST_FQDN}" ]; then
    info "  FLINK_JOBMANAGER 尚未部署到任何主机，跳过 Fix 6b"
  else
    info "  检测到 JobManager 部署于: ${JM_HOST_FQDN}"
    PATCH=$(curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
      "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations?type=flink-conf&tag=${FLINK_FC_TAG}" \
      | python3 -c "
import json,sys,os
d=json.load(sys.stdin)
props=d['items'][0]['properties']
content=props['content']
checks=(
  'jobmanager.rpc.address: ${JM_HOST_FQDN}',
  'rest.address: ${JM_HOST_FQDN}',
  'jobmanager.bind-host: 0.0.0.0',
  'taskmanager.bind-host: 0.0.0.0',
  'taskmanager.host: 0.0.0.0',
)
if all(c in content for c in checks):
    print('SKIP')
    sys.exit(0)
new=content.replace('jobmanager.rpc.address: localhost','jobmanager.rpc.address: ${JM_HOST_FQDN}')
new=new.replace('rest.address: localhost','rest.address: ${JM_HOST_FQDN}')
new=new.replace('jobmanager.bind-host: localhost','jobmanager.bind-host: 0.0.0.0')
new=new.replace('taskmanager.bind-host: localhost','taskmanager.bind-host: 0.0.0.0')
new=new.replace('taskmanager.host: localhost','taskmanager.host: 0.0.0.0')
payload={'type':'flink-conf','tag':'flink-cross-host','properties':{'content':new}}
print(json.dumps(payload))
" 2>/dev/null)

    if [ "${PATCH}" = "SKIP" ]; then
      ok "flink-conf 已是跨主机配置"
    elif [ -n "${PATCH}" ]; then
      HTTP=$(echo "${PATCH}" | curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
        -X POST -H "X-Requested-By: ambari" -H "Content-Type: application/json" \
        -d @- -o /dev/null -w "%{http_code}" \
        "${AMBARI_API}/clusters/${CLUSTER_NAME}/configurations")
      # 设为 desired
      DHTTP=$(echo "{\"Clusters\":{\"desired_configs\":{\"flink-conf\":{\"tag\":\"flink-cross-host\",\"type\":\"flink-conf\"}}}}" \
        | curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
          -X PUT -H "X-Requested-By: ambari" -H "Content-Type: application/json" \
          -d @- -o /dev/null -w "%{http_code}" \
          "${AMBARI_API}/clusters/${CLUSTER_NAME}")
      [ "${HTTP}" = "200" ] || [ "${HTTP}" = "201" ] \
        && ok "flink-conf 跨主机配置已写入并设为 desired（PUT=${DHTTP}）" \
        || warn "flink-conf 写入失败 HTTP=${HTTP}"
    else
      warn "无法读取 flink-conf 配置，跳过 Fix 6b"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════
# Fix 6c: Iceberg 数据湖部署（Spark JDK17 + Hadoop Catalog）
#   问题1: Iceberg 1.11 runtime 的 ExtendedParser 等类编译为 Java17，
#          Bigtop Spark 默认 Java8 会 UnsupportedClassVersionError
#   问题2: Iceberg(Java17) 与 Hive 3.1 client(Java8-era) 冲突
#          （HiveClientImpl.NoSuchFieldError:out），故用 hadoop catalog
#          避开 Hive client 初始化
#   问题3: Ambari spark-defaults 模板含无效 hive.metastore.version=4.0.1
#   问题4: 单 DataNode 集群默认 dfs.replication=3 导致 YARN AM 本地化写出
#          /app-logs 失败（could only be written to 0 of minReplication nodes）
#   问题5: DataNode 向 NN 上报错误网关 IP(172.19.0.1) 而非容器 IP，
#          导致 NM 在 AM 本地化时读不到 staging 块
#   修复: 调用 setup-iceberg.sh（幂等）：
#         - hdfs-site: dfs.replication=1 + datanode use.hostname=true
#         - spark-env/driver: JDK17
#         - spark-defaults: iceberg hadoop catalog 段
# ════════════════════════════════════════════════════════════
section "Fix 6c: Iceberg 数据湖部署（Spark JDK17 + Hadoop Catalog + HDFS 前置）"
ICE_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${ICE_DIR}/setup-iceberg.sh" ]; then
  bash "${ICE_DIR}/setup-iceberg.sh"
else
  warn "setup-iceberg.sh 不存在，跳过 Fix 6c"
fi

# ════════════════════════════════════════════════════════════
# Fix 7: 重启 Ambari Server（刷新 stack 缓存和 JPA 缓存）
# ════════════════════════════════════════════════════════════
section "Fix 7: 重启 Ambari Server（刷新缓存）"

info "重启 Ambari Server..."
docker exec bigtop_hostname0 ambari-server restart 2>&1 | \
  grep -E "started|stopped|listening|error" | head -5
ok "Ambari Server 重启完成"

# ════════════════════════════════════════════════════════════
# Fix 8: 等待 Agent 重新注册并确认所有节点 HEALTHY
# ════════════════════════════════════════════════════════════
section "Fix 8: 等待所有节点 Agent 恢复 HEALTHY"

info "等待 Ambari Server API 就绪..."
for i in $(seq 1 30); do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -u "${AMBARI_USER}:${AMBARI_PASS}" \
    "${AMBARI_API}/clusters" 2>/dev/null)
  [ "${HTTP}" = "200" ] && break
  sleep 3
done

sleep 15  # 等待 Agent 心跳同步

info "检查各节点状态..."
ALL_HEALTHY=true
HOSTS=("bigtop-hostname0.bigtop.apache.org" "bigtop-hostname1.bigtop.apache.org" \
       "bigtop-hostname2.bigtop.apache.org" "bigtop-hostname3.bigtop.apache.org")

for host in "${HOSTS[@]}"; do
  STATUS=$(curl -s -u "${AMBARI_USER}:${AMBARI_PASS}" \
    "${AMBARI_API}/hosts/${host}?fields=Hosts/host_status,Hosts/last_heartbeat_time" \
    | python3 -c "
import json,sys,time
d=json.load(sys.stdin)
h=d.get('Hosts',{})
ts=h.get('last_heartbeat_time',0)
ago=int(time.time()*1000-ts)//1000 if ts else -1
print(h.get('host_status','UNKNOWN'), ago)
" 2>/dev/null)
  STATUS_VAL=$(echo "${STATUS}" | awk '{print $1}')
  HB_AGO=$(echo "${STATUS}" | awk '{print $2}')
  if [ "${STATUS_VAL}" = "HEALTHY" ]; then
    ok "  ${host}: HEALTHY (心跳${HB_AGO}s前)"
  else
    warn "  ${host}: ${STATUS_VAL} (心跳${HB_AGO}s前) — 可能需要更多时间"
    ALL_HEALTHY=false
  fi
done

echo ""
echo "════════════════════════════════════════════════════"
if ${ALL_HEALTHY}; then
  echo -e "${GREEN}  所有修复已应用，所有节点 HEALTHY${NC}"
  echo -e "${GREEN}  现在回到 Ambari UI 点击 Retry 重试失败的安装任务${NC}"
else
  echo -e "${YELLOW}  修复已应用，部分节点状态待刷新${NC}"
  echo -e "${YELLOW}  等待约 30 秒后再 Retry，或手动刷新 Ambari UI${NC}"
fi
echo "════════════════════════════════════════════════════"
