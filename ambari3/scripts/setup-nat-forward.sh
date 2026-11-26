#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: setup-nat-forward.sh
# 文件功能: 宿主机 NAT 端口转发配置脚本
#
#   按实际组件分布，将各容器服务端口分段映射到宿主机，
#   避免端口冲突，支持局域网其他机器访问。
#
#   实际组件分布（来自 Ambari，已逐节点核对）：
#   hostname0 (172.19.0.2): NameNode, ResourceManager, HBase Master,
#                            HiveServer2, Hive Metastore, WebHCat,
#                            Ranger Admin / Usersync / KMS,
#                            MapReduce HistoryServer,
#                            Spark HistoryServer, Flink JobManager/HistoryServer,
#                            Kafka Broker, Timeline Reader(V2), Infra Solr,
#                            ZooKeeper, MySQL, YARN Registry DNS
#   hostname1 (172.19.0.5): App Timeline Server(V1), Spark ThriftServer,
#                            Secondary NameNode, DataNode, NodeManager, ZooKeeper
#   hostname2 (172.19.0.3): Flink TaskManager, DataNode, NodeManager, ZooKeeper
#   hostname3 (172.19.0.4): DataNode, NodeManager, HBase RegionServer,
#                            Ranger Tagsync, HDFS Router (Federation)
#
# 版    本: V2.7
#   V2.7 修订（2026-11-09）：
#   - Kafka 外部访问补齐：9092→h0:9092、9093→h2:9092、9094→h3:9092
#   - 配合 advertised.listeners=as.long.kim:9092/9093/9094，支持三分区写入
#   - 容器内 hairpin 规则与 Kafka 配置见 scripts/kafka_external_listener.sh
#   V2.6 修订（2026-10-26）：
#   - Spark App UI 4040→h1:4040（ThriftServer 常驻 h1 端口稳定，可固定映射）
#   - Spark HS 18081 注释补充说明 4041 已移除、4040 归属 h1
#   V2.5 修订（2026-10-26，按实测监听端口核对）：
#   - 删除 18 条"黑洞规则"（目标端口无监听）：9000/14000/8199/10001/6182/
#     9393/9093/18080/4040/4041/8190/50072/7085/8998/9995/19999/19998/29999/30000
#   - 删除 8440/8441（Ambari Agent 内部端口，不应对外）
#   - 修正 4040 归属错误（Spark Application UI 实际在 h1 且为动态端口，不映射）
#   - 新增 3000（Grafana/AMS Web UI，实测在 h0 监听）
#   - MySQL 3306 保留但标注安全警示（数据库直接暴露局域网）
#   V2.4 新增：persist/unpersist —— 安装 systemd 服务，宿主机重启后
#   自动 refresh 规则（iptables 不持久化，重启即丢）；修正 apply 计数统计。
#   V2.3 关键修复：所有 DNAT 规则增加 `-m addrtype --dst-type LOCAL` 守卫
#   （与 Docker 一致），确保仅转发「发往宿主机本机地址」的外部流量，
#   绝不劫持容器之间的内部通信；移除 50010（DataNode 传输端口）转发；
#   remove/refresh 改为通用清理，可删除任意历史遗留/重复的 DNAT 规则。
# 使用方法:
#   sudo ./setup-nat-forward.sh apply     # 应用规则
#   sudo ./setup-nat-forward.sh remove    # 清除规则
#   sudo ./setup-nat-forward.sh status    # 查看状态
#   sudo ./setup-nat-forward.sh refresh   # 自动探测IP后重建规则
#   sudo ./setup-nat-forward.sh persist   # 安装开机自恢复服务（推荐）
#   sudo ./setup-nat-forward.sh unpersist # 卸载开机自恢复服务
# ============================================================

set -euo pipefail

# ── IP 配置（支持 refresh 模式自动探测）────────────────────
H0_IP="${H0_IP:-172.19.0.2}"   # bigtop_hostname0
H1_IP="${H1_IP:-172.19.0.5}"   # bigtop_hostname1
H2_IP="${H2_IP:-172.19.0.3}"   # bigtop_hostname2
H3_IP="${H3_IP:-172.19.0.4}"   # bigtop_hostname3
SUBNET="${SUBNET:-172.19.0.0/24}"  # 容器网段（用于限定 MASQUERADE，避免影响容器间通信）

ACTION="${1:-apply}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${YELLOW}──── $* ────${NC}"; }
err()     { echo -e "${RED}[ERR ]${NC}  $*"; }

if [[ $EUID -ne 0 ]]; then
  err "此脚本需要 root 权限，请使用 sudo 运行。"
  exit 1
fi

# ── refresh 模式：从 docker inspect 自动探测 IP ────────────
if [ "$ACTION" = "refresh" ]; then
  info "自动探测各容器 IP..."
  H0_IP=$(docker inspect bigtop_hostname0 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "$H0_IP")
  H1_IP=$(docker inspect bigtop_hostname1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "$H1_IP")
  H2_IP=$(docker inspect bigtop_hostname2 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "$H2_IP")
  H3_IP=$(docker inspect bigtop_hostname3 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "$H3_IP")
  info "hostname0=$H0_IP  hostname1=$H1_IP  hostname2=$H2_IP  hostname3=$H3_IP"
  # IP 探测完成后，让下方 case 分支的 refresh 处理 remove → apply 流程
fi

# ══════════════════════════════════════════════════════════════
# 规则定义：按节点分段，精确对应实际组件分布
# 格式: "宿主机端口:目标IP:目标端口:服务说明"
# ══════════════════════════════════════════════════════════════

# ── hostname0：NameNode / ResourceManager / HBase Master ─────
# Hive / Ranger / WebHCat / MR History / Flink / Spark / Kafka
# Timeline Reader(V2) / Infra Solr / MySQL / Ambari / ZooKeeper
H0_RULES=(
  # Ambari（docker-compose 已映射 20609:8080；此处 8080 为习惯性直访端口）
  "8080:${H0_IP}:8080:Ambari Server HTTP"
  # 注：8440/8441 为 Ambari Agent 内部注册/心跳端口，不对外映射（V2.5 移除）

  # HDFS NameNode
  "50070:${H0_IP}:50070:HDFS NameNode Web UI"
  "8020:${H0_IP}:8020:HDFS NameNode RPC"
  # 已移除(V2.5，实测无监听)：9000 旧RPC / 14000 HttpFS

  # YARN ResourceManager
  "8088:${H0_IP}:8088:YARN ResourceManager Web UI"
  "8050:${H0_IP}:8050:YARN ResourceManager RPC"
  "8030:${H0_IP}:8030:YARN ResourceManager Scheduler"
  "8025:${H0_IP}:8025:YARN ResourceManager 资源追踪"
  "8141:${H0_IP}:8141:YARN ResourceManager 管理"

  # ZooKeeper（hostname0 节点）
  # 对外暴露使用非标准宿主端口 21810（避免占用内网 2181，防止 DNAT
  # 劫持 hostname0 到其他 ZK peer 的 client 定向流量）。
  # 注意：2888（Follower 通信）与 3888（Leader 选举）为 ZK 集群
  # 内部仲裁端口，绝不能 DNAT 对外，否则会破坏仲裁/被外部冒充 peer，
  # 且会劫持容器间同端口流量。此处已移除 2888/3888 的转发。
  "21810:${H0_IP}:2181:ZooKeeper Client（hostname0，外部访问用 21810）"

  # YARN Timeline Reader（V2，实际在 hostname0；Web UI 8198，非 8188）
  "8198:${H0_IP}:8198:YARN Timeline Reader(V2) Web UI"
  # 已移除(V2.5，实测无监听)：8199 HTTPS

  # HBase Master
  "16000:${H0_IP}:16000:HBase Master RPC"
  "16010:${H0_IP}:16010:HBase Master Web UI"

  # Hive（实际部署在 hostname0）
  "10000:${H0_IP}:10000:HiveServer2 JDBC/Thrift"
  "10002:${H0_IP}:10002:HiveServer2 Web UI"
  "9083:${H0_IP}:9083:Hive Metastore Thrift"
  # 已移除(V2.5，实测无监听)：10001 HS2 HTTP 模式（transportMode 为 binary）

  # WebHCat（Templeton，实际在 hostname0）
  "50111:${H0_IP}:50111:WebHCat (Templeton) REST"

  # Ranger Admin / Usersync / KMS（实际部署在 hostname0）
  "6080:${H0_IP}:6080:Ranger Admin Web UI HTTP"
  "5151:${H0_IP}:5151:Ranger Usersync (unix auth)"
  "9292:${H0_IP}:9292:Ranger KMS Web UI HTTP"
  # 已移除(V2.5)：6182/9393 HTTPS 无监听；7085 shutdown 仅绑 127.0.0.1，DNAT 无效

  # MapReduce History Server（实际在 hostname0，非 hostname1）
  "19888:${H0_IP}:19888:MapReduce History Server Web UI"
  "10020:${H0_IP}:10020:MapReduce History Server IPC"

  # Kafka Broker
  "9092:${H0_IP}:9092:Kafka Broker PLAINTEXT"
  "8083:${H0_IP}:8083:Kafka Connect REST API"
  # 已移除(V2.5，实测无监听)：9093 SSL

  # Spark History Server（实际 UI 端口为 18081）
  "18081:${H0_IP}:18081:Spark History Server Web UI"
  # 已移除(V2.5)：18080 无监听；4041 为第二 Application UI（动态）
  # 注：4040 已在 H1_RULES 中固定映射（ThriftServer 常驻，实际在 h1）

  # Flink JobManager / HistoryServer（实际在 hostname0）
  "8081:${H0_IP}:8081:Flink JobManager Web UI"
  "6123:${H0_IP}:6123:Flink JobManager RPC"
  "8082:${H0_IP}:8082:Flink HistoryServer Web UI"

  # Infra Solr（Ambari Infra）
  "8886:${H0_IP}:8886:Ambari Infra Solr"

  # Grafana（AMS 仪表盘，V2.5 新增，实测监听）
  "3000:${H0_IP}:3000:Grafana (Ambari Metrics) Web UI"

  # MySQL（hostname0 本地元数据库。⚠ 数据库直接暴露局域网有风险，
  # 仅排障时启用。⚠ 宿主机自身 MySQL 已占用 3306，为避免 DNAT 劫持
  # 宿主机本地 MySQL 流量，对外统一使用偏移端口 13306 → 容器 3306）
  "13306:${H0_IP}:3306:MySQL 元数据库（宿主端口 13306，非 3306）"

  # 已移除(V2.5，组件未安装)：8998 Livy / 9995 Zeppelin / 19999+19998 Alluxio
)

# ── hostname1：App Timeline Server(V1) / Spark Thrift / 2NN ──
H1_RULES=(
  # YARN App Timeline Server（V1，实际在 hostname1；Web UI 8188）
  "8188:${H1_IP}:8188:YARN App Timeline Server(V1) Web UI"
  "10200:${H1_IP}:10200:YARN App Timeline Server(V1) RPC"
  # 已移除(V2.5，实测无监听)：8190 HTTPS

  # Spark ThriftServer（实际在 hostname1）
  "10016:${H1_IP}:10016:Spark ThriftServer JDBC/Thrift"
  # V2.6 新增：Spark ThriftServer 常驻 h1，App Web UI 端口 4040 稳定监听，
  # 固定映射便于直接在浏览器查看 SQL 查询进度与 Executor 状态
  "4040:${H1_IP}:4040:Spark App Web UI（ThriftServer 常驻，端口稳定）"

  # Secondary NameNode（在 hostname1）
  "50090:${H1_IP}:50090:HDFS Secondary NameNode Web UI"

  # HDFS DataNode / YARN NodeManager（hostname1，使用偏移宿主端口避免同名冲突）
  "50076:${H1_IP}:50075:HDFS DataNode Web UI（hostname1）"
  "8043:${H1_IP}:8042:YARN NodeManager Web UI（hostname1）"

  # ZooKeeper（hostname1 节点，使用不同宿主机端口避免冲突）
  "12181:${H1_IP}:2181:ZooKeeper Client（hostname1）"

  # Prometheus / Alertmanager（h1，V2.8 新增）
  "9090:${H1_IP}:9090:Prometheus Web UI"
  "19093:${H1_IP}:9093:Alertmanager Primary Web UI"
)

# ── hostname2：Flink TaskManager / DataNode / NodeManager ────
H2_RULES=(
  # Flink TaskManager 使用动态监听端口（无固定端口），且仅需经
  # JobManager(hostname0:6123) 调度通信，故无需 NAT 转发。

  # HDFS DataNode / YARN NodeManager（hostname2，偏移宿主端口避免冲突）
  "50077:${H2_IP}:50075:HDFS DataNode Web UI（hostname2）"
  "8044:${H2_IP}:8042:YARN NodeManager Web UI（hostname2）"

  # ZooKeeper（hostname2 节点，使用不同宿主机端口避免冲突）
  "22181:${H2_IP}:2181:ZooKeeper Client（hostname2）"

  # Kafka Broker 1002 外部监听（advertised.listeners=as.long.kim:9093）
  "9093:${H2_IP}:9092:Kafka Broker 1002 PLAINTEXT（external）"

  # Prometheus / Alertmanager standby（h2，V2.8 新增）
  "19090:${H2_IP}:9090:Prometheus Standby Web UI"
  "29093:${H2_IP}:9093:Alertmanager Standby Web UI"

  # Prometheus 稳定查询入口（h2 上的只读故障切换代理）
  "19099:${H2_IP}:9099:Prometheus Failover Query Proxy"
)

# ── hostname3：DataNode / NodeManager / HBase RS / Router ────
H3_RULES=(
  # Kafka Broker 1003 外部监听（advertised.listeners=as.long.kim:9094）
  "9094:${H3_IP}:9092:Kafka Broker 1003 PLAINTEXT（external）"

  # HBase RegionServer
  "16020:${H3_IP}:16020:HBase RegionServer RPC"
  "16030:${H3_IP}:16030:HBase RegionServer Web UI"

  # HDFS DataNode / YARN NodeManager（hostname3）
  "50075:${H3_IP}:50075:HDFS DataNode Web UI（hostname3）"
  # 注意：50010（DataNode 数据传输端口）绝不能 DNAT 对外。当
  # net.bridge.bridge-nf-call-iptables=1 时，该规则会劫持容器之间
  # DataNode 之间建立写管线（pipeline）的连接，导致 HDFS 写超时、
  # 反复 "Excluding datanode" 及 HBase WAL 写入失败。此处已移除。
  "8042:${H3_IP}:8042:YARN NodeManager Web UI（hostname3）"

  # HDFS Router (Federation；实际 RPC 20010、Admin 8111，原 8888 有误)
  "50071:${H3_IP}:50071:HDFS Router Web UI"
  "20010:${H3_IP}:20010:HDFS Router RPC"
  "8111:${H3_IP}:8111:HDFS Router Admin"
  # 已移除(V2.5，实测无监听)：50072 HTTPS

  # Ranger Tagsync 为拉取型客户端（从 Ranger Admin/Atlas 拉取策略），
  # 不监听对外端口，无需 NAT 转发（原 6085 映射无效，已移除）。

  # 已移除(V2.5，组件未安装)：29999/30000 Alluxio Worker
)

# 所有规则合并
ALL_RULES=("${H0_RULES[@]}" "${H1_RULES[@]}" "${H2_RULES[@]}" "${H3_RULES[@]}")

# ══════════════════════════════════════════════════════════════
# 应用规则
# ══════════════════════════════════════════════════════════════
do_apply() {
  section "启用 IP 转发"
  echo 1 > /proc/sys/net/ipv4/ip_forward
  sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true
  ok "net.ipv4.ip_forward = 1"

  local sections=("hostname0（NameNode/RM/HBase/Hive/Ranger/WebHCat/Flink/Spark/Kafka）"
                  "hostname1（AppTimelineV1/Spark Thrift/2NN/DataNode/NM）"
                  "hostname2（Flink TaskManager/DataNode/NM/ZooKeeper）"
                  "hostname3（DataNode/NM/HBase RS/HDFS Router）")
  local rule_groups=("H0_RULES[@]" "H1_RULES[@]" "H2_RULES[@]" "H3_RULES[@]")

  local total=0
  for idx in 0 1 2 3; do
    section "${sections[$idx]}"
    local count=0
    eval "local rules=(\"\${${rule_groups[$idx]}}\")"
    for rule in "${rules[@]}"; do
      IFS=':' read -r HOST_PORT DST_IP DST_PORT DESC <<< "$rule"
      local added=0
      # PREROUTING：处理来自局域网/其他主机的流量
      if iptables -t nat -C PREROUTING -p tcp --dport "${HOST_PORT}" \
          -m addrtype --dst-type LOCAL \
          -j DNAT --to-destination "${DST_IP}:${DST_PORT}" 2>/dev/null; then
        warn "已存在(PREROUTING)，跳过: ${HOST_PORT} -> ${DST_IP}:${DST_PORT}"
      else
        iptables -t nat -A PREROUTING -p tcp --dport "${HOST_PORT}" \
          -m addrtype --dst-type LOCAL \
          -j DNAT --to-destination "${DST_IP}:${DST_PORT}"
        added=1
      fi
      # OUTPUT：处理宿主机本机访问本机地址的流量（本机包不经 PREROUTING，
      # 缺了这条在宿主机上 curl 192.168.0.60:10000 会永远不通，极易误判
      # 为"规则没生效"。V2.5 起双链同步，保证本机与局域网行为一致。）
      if iptables -t nat -C OUTPUT -p tcp --dport "${HOST_PORT}" \
          -m addrtype --dst-type LOCAL \
          -j DNAT --to-destination "${DST_IP}:${DST_PORT}" 2>/dev/null; then
        warn "已存在(OUTPUT)，跳过: ${HOST_PORT} -> ${DST_IP}:${DST_PORT}"
      else
        iptables -t nat -A OUTPUT -p tcp --dport "${HOST_PORT}" \
          -m addrtype --dst-type LOCAL \
          -j DNAT --to-destination "${DST_IP}:${DST_PORT}"
        added=1
      fi
      if [ "${added}" = "1" ]; then
        ok "已添加: ${HOST_PORT} -> ${DST_IP}:${DST_PORT}  (${DESC})"
        (( count++ )) || true
        (( total++ )) || true
      fi
    done
    info "  本段新增: ${count} 条"
  done

  section "POSTROUTING MASQUERADE（仅出网段流量）"
  # ⚠️ 绝不能使用无差别的 `-j MASQUERADE`：
  # 当 net.bridge.bridge-nf-call-iptables=1 时，无差别 MASQUERADE 会把容器之间
  # 互访的源地址改写成网关 IP（172.19.0.1），导致 HBase Master 反解 RegionServer
  # 时得到 "_gateway"，触发 "Master passed us a different hostname" 并启动失败。
  # 兼容清理旧版遗留的无差别规则。
  while iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null; do
    iptables -t nat -D POSTROUTING -j MASQUERADE
    warn "已删除遗留的无差别 MASQUERADE 规则（会破坏容器间通信）"
  done
  if iptables -t nat -C POSTROUTING -s "${SUBNET}" ! -d "${SUBNET}" -j MASQUERADE 2>/dev/null; then
    warn "MASQUERADE（出网段）已存在，跳过"
  else
    iptables -t nat -A POSTROUTING -s "${SUBNET}" ! -d "${SUBNET}" -j MASQUERADE
    ok "MASQUERADE（出网段）已添加"
  fi

  section "FORWARD 规则（容器网段）"
  for subnet in "${SUBNET}"; do
    if iptables -C FORWARD -d "$subnet" -j ACCEPT 2>/dev/null; then
      warn "FORWARD $subnet 已存在，跳过"
    else
      iptables -I FORWARD -d "$subnet" -j ACCEPT
      ok "FORWARD $subnet 已添加"
    fi
  done

  echo ""
  info "本次新增规则总数: ${total}"
  ok "所有 NAT 端口转发规则已应用！"
  echo ""
  info "局域网机器 /etc/hosts 中添加（将 <宿主机IP> 替换为实际IP）："
  echo "  <宿主机IP>  bigtop-hostname0.bigtop.apache.org bigtop-hostname0"
  echo "  <宿主机IP>  bigtop-hostname1.bigtop.apache.org bigtop-hostname1"
  echo "  <宿主机IP>  bigtop-hostname2.bigtop.apache.org bigtop-hostname2"
  echo "  <宿主机IP>  bigtop-hostname3.bigtop.apache.org bigtop-hostname3"
  echo ""
  info "ZooKeeper 多节点访问说明（宿主机端口不同，避免冲突）："
  echo "  hostname0 ZK: <宿主机IP>:21810"
  echo "  hostname1 ZK: <宿主机IP>:12181"
  echo "  hostname2 ZK: <宿主机IP>:22181"
  echo "  （2888/3888 仲裁端口不对外转发，仅供集群内部使用）"
  echo ""
  info "多节点同名 Web UI 偏移端口说明（避免宿主端口冲突）："
  echo "  DataNode Web UI: hostname3=50075  hostname1=50076  hostname2=50077"
  echo "  NodeManager Web UI: hostname3=8042  hostname1=8043  hostname2=8044"
  echo ""
  info "关键服务实际归属（如对端 NAT 需同步修正）："
  echo "  HiveServer2/Metastore、Ranger Admin、WebHCat、MR History -> hostname0"
  echo "  App Timeline Server(V1,8188)、Spark ThriftServer(10016) -> hostname1"
  echo "  Timeline Reader(V2,8198)、Flink JM(8081)/HistoryServer(8082) -> hostname0"
  echo "  HDFS Router RPC -> hostname3:20010（非 8888）"
}

# ══════════════════════════════════════════════════════════════
# 清除规则
# ══════════════════════════════════════════════════════════════
do_remove() {
  section "清除所有 PREROUTING/OUTPUT DNAT 规则（含历史遗留）"
  local count=0
  # 通用清理：删除 PREROUTING 与 OUTPUT 中所有直接 DNAT 规则，可清除任意
  # 历史版本遗留/重复的规则。Docker 自带的发布端口规则位于 DOCKER 链中，
  # 不受影响（OUTPUT 链中指向 DOCKER 链的跳转非直接 DNAT，不会被误删）。
  local rule rules
  for chain in PREROUTING OUTPUT; do
    rules=$(iptables -t nat -S "${chain}" 2>/dev/null | grep -- '-j DNAT' || true)
    while IFS= read -r rule; do
      [ -z "$rule" ] && continue
      iptables -t nat ${rule/-A ${chain}/-D ${chain}} 2>/dev/null || continue
      warn "已删除: ${rule}"
      (( count++ )) || true
    done <<< "$rules"
  done

  section "清除 POSTROUTING MASQUERADE 规则"
  if iptables -t nat -C POSTROUTING -s "${SUBNET}" ! -d "${SUBNET}" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -D POSTROUTING -s "${SUBNET}" ! -d "${SUBNET}" -j MASQUERADE
    ok "MASQUERADE（出网段）已删除"
  fi
  while iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null; do
    iptables -t nat -D POSTROUTING -j MASQUERADE
    warn "已删除遗留的无差别 MASQUERADE 规则"
  done

  section "清除 FORWARD 规则"
  if iptables -C FORWARD -d "${SUBNET}" -j ACCEPT 2>/dev/null; then
    iptables -D FORWARD -d "${SUBNET}" -j ACCEPT
    ok "FORWARD 规则已删除"
  fi

  echo ""
  info "已删除规则数: ${count}"
  ok "清除完成。"
}

# ══════════════════════════════════════════════════════════════
# 查看状态
# ══════════════════════════════════════════════════════════════
do_status() {
  local sections=("hostname0" "hostname1" "hostname2" "hostname3")
  local rule_groups=("H0_RULES[@]" "H1_RULES[@]" "H2_RULES[@]" "H3_RULES[@]")

  for idx in 0 1 2 3; do
    section "${sections[$idx]}"
    printf "  %-10s %-22s %-8s %s\n" "宿主机端口" "目标IP:端口" "状态" "服务"
    printf "  %-10s %-22s %-8s %s\n" "----------" "----------------------" "------" "----"
    eval "local rules=(\"\${${rule_groups[$idx]}}\")"
    for rule in "${rules[@]}"; do
      IFS=':' read -r HOST_PORT DST_IP DST_PORT DESC <<< "$rule"
      if iptables -t nat -C PREROUTING -p tcp --dport "${HOST_PORT}" \
          -m addrtype --dst-type LOCAL -j DNAT --to-destination "${DST_IP}:${DST_PORT}" 2>/dev/null; then
        STATUS="${GREEN}YES${NC}"
      else
        STATUS="${RED} NO${NC}"
      fi
      printf "  %-10s %-22s " "${HOST_PORT}" "${DST_IP}:${DST_PORT}"
      echo -e "${STATUS}     ${DESC}"
    done
  done

  section "IP 转发状态"
  FWD=$(cat /proc/sys/net/ipv4/ip_forward)
  [ "$FWD" = "1" ] && ok "net.ipv4.ip_forward=1（已启用）" || warn "net.ipv4.ip_forward=0（未启用）"
}

# ══════════════════════════════════════════════════════════════
# 持久化：安装 systemd 服务，宿主机重启后自动重建规则
#   （iptables 规则不持久化，重启即丢失；容器使用固定 IP，refresh 可靠）
# ══════════════════════════════════════════════════════════════
NAT_SERVICE=/etc/systemd/system/hodoopforge-nat.service

do_persist() {
  section "安装 NAT 规则持久化 systemd 服务"
  local script_path
  script_path="$(readlink -f "$0")"
  cat > "${NAT_SERVICE}" <<EOF
[Unit]
Description=HodoopForge NAT port forwarding (setup-nat-forward.sh)
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
# 等待容器网络就绪后按实际 IP 重建规则
ExecStart=/bin/bash -c 'sleep 15; ${script_path} refresh'
ExecStop=/bin/bash -c '${script_path} remove || true'

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable hodoopforge-nat.service >/dev/null 2>&1
  ok "已安装并启用 ${NAT_SERVICE}（开机 15s 后自动 refresh）"
  info "立即生效可执行：systemctl start hodoopforge-nat.service"
}

do_unpersist() {
  section "卸载 NAT 规则持久化 systemd 服务"
  systemctl disable --now hodoopforge-nat.service 2>/dev/null || true
  rm -f "${NAT_SERVICE}"
  systemctl daemon-reload
  ok "已移除 ${NAT_SERVICE}"
}

# ══════════════════════════════════════════════════════════════
# 入口
# ══════════════════════════════════════════════════════════════
echo "============================================================"
echo "  HodoopForge NAT 端口转发配置脚本 V2.6"
echo "  hostname0=${H0_IP}  hostname1=${H1_IP}"
echo "  hostname2=${H2_IP}  hostname3=${H3_IP}"
echo "  操作模式: ${ACTION}"
echo "============================================================"

case "${ACTION}" in
  apply)            do_apply ;;
  remove)           do_remove ;;
  status)           do_status ;;
  refresh)          do_remove; ACTION=apply; do_apply ;;
  persist)          do_persist ;;
  unpersist)        do_unpersist ;;
  *)
    echo "用法: sudo $0 [apply|remove|status|refresh|persist|unpersist]"
    echo "  apply     — 应用端口转发规则（默认）"
    echo "  remove    — 清除所有规则"
    echo "  status    — 查看规则状态"
    echo "  refresh   — 自动探测容器IP后重建规则（容器重启后使用）"
    echo "  persist   — 安装 systemd 服务，宿主机重启后自动重建规则"
    echo "  unpersist — 卸载上述 systemd 服务"
    exit 1
    ;;
esac
