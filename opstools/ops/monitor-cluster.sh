#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: monitor-cluster.sh
# 文件功能: 集群监控脚本
#   实时监控集群资源使用、服务状态、
#   告警信息等，输出监控报告。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="c1"

echo "==> HodoopForge: 集群监控"
echo "=========================================="
echo "监控时间: $(date)"
echo ""

# 监控1: 集群概览
echo "--- 集群概览 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME} \
  | jq -r '.Clusters | "集群名称: \(.cluster_name)\n状态: \(.provisioning_state)\n版本: \(.version)"'

# 监控2: 节点状态
echo ""
echo "--- 节点状态 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/hosts \
  | jq -r '.items[] | "\(.Hosts.host_name): \(.Hosts.host_state)"'

# 监控3: 服务状态
echo ""
echo "--- 服务状态 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/services \
  | jq -r '.items[] | "\(.ServiceName): \(.State) (\(.maintenance_state)"'

# 监控4: 告警信息
echo ""
echo "--- 告警信息 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/alerts \
  | jq -r '.items[] | "\(.label): \(.state)"' | head -10

# 监控5: 资源使用
echo ""
echo "--- 资源使用 ---"
for i in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  echo "节点: $i"
  docker compose exec -T $i bash -c \
    "free -h | grep Mem" | awk '{print "  内存: " $3 " / " $2}'
  docker compose exec -T $i bash -c \
    "df -h /data | tail -1" | awk '{print "  磁盘: " $3 " / " $2}'
done

echo "=========================================="
echo "  监控报告完成"
echo "=========================================="
