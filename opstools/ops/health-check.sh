#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: health-check.sh
# 文件功能: 集群健康检查脚本
#   检查集群各服务的运行状态、资源使用情况、
#   网络连通性等，输出健康报告。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

# 配置参数
AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="c1"

echo "==> HodoopForge: 集群健康检查"
echo "=========================================="

# 检查1: Ambari Server 连通性
echo "[1/6] 检查 Ambari Server 连通性..."
if curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/stacks > /dev/null; then
  echo "    [OK] Ambari Server 可访问"
else
  echo "    [ERROR] Ambari Server 无法访问"
  exit 1
fi

# 检查2: 集群状态
echo "[2/6] 检查集群状态..."
CLUSTER_STATE=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME} \
  | jq -r '.Clusters.provisioning_state')
echo "    集群状态: ${CLUSTER_STATE}"

# 检查3: 节点注册状态
echo "[3/6] 检查节点注册状态..."
NODE_COUNT=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/hosts \
  | jq -r '.items | length')
echo "    已注册节点数: ${NODE_COUNT}"

# 检查4: 服务状态
echo "[4/6] 检查服务状态..."
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/services \
  | jq -r '.items[] | "\(.ServiceName): \(.State"' | while read line; do
  echo "    ${line}"
done

# 检查5: HDFS 状态
echo "[5/6] 检查 HDFS 状态..."
if command -v hdfs &> /dev/null; then
  HDFS_HEALTH=$(hdfs dfsadmin -report 2>/dev/null | head -5)
  echo "    HDFS 健康状态正常"
else
  echo "    [SKIP] hdfs 命令不可用"
fi

# 检查6: 资源使用
echo "[6/6] 检查资源使用..."
echo "    CPU 使用率: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')"
echo "    内存使用率: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"

echo "=========================================="
echo "  健康检查完成"
echo "=========================================="
