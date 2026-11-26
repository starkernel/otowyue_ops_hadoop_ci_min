#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: cluster-info.sh
# 文件功能: 集群信息查询脚本
#   输出集群的详细信息，包括版本、配置、
#   资源使用等，用于运维管理。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="c1"

echo "==> HodoopForge: 集群信息"
echo "=========================================="
echo "查询时间: $(date)"
echo ""

# 集群基本信息
echo "--- 集群基本信息 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME} \
  | jq -r '.Clusters | "集群名称: \(.cluster_name)\n集群ID: \(.cluster_id)\n版本: \(.version)\n状态: \(.provisioning_state)\n安全状态: \(.security_type)"'

# Stack 信息
echo ""
echo "--- Stack 信息 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/stack_version \
  | jq -r '.'

# 节点信息
echo ""
echo "--- 节点信息 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/hosts \
  | jq -r '.items[] | "\(.Hosts.host_name): \(.Hosts.ip) (\(.Hosts.host_state))"'

# 服务信息
echo ""
echo "--- 服务信息 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/services \
  | jq -r '.items[] | "\(.ServiceName): \(.State) - 维护模式: \(.maintenance_state)"'

# 组件信息
echo ""
echo "--- 组件信息 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/components \
  | jq -r '.items[] | "\(.ServiceComponentInfo.component_name): \(.ServiceComponentInfo.state)"' | head -20

# 配置信息
echo ""
echo "--- 配置信息 ---"
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/configurations/service_config_versions \
  | jq -r '.items[0] | "配置版本: \(.version)\n创建时间: \(.created_time)"'

echo "=========================================="
echo "  集群信息查询完成"
echo "=========================================="
