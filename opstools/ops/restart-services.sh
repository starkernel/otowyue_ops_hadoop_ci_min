#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: restart-services.sh
# 文件功能: 服务重启脚本
#   通过 Ambari API 重启指定服务或全部服务，
#   支持优雅停机，避免数据丢失。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="c1"

# 服务名称（参数传入，默认为空）
SERVICE_NAME=${1:-""}

echo "==> HodoopForge: 重启服务"
echo "=========================================="

if [ -z "$SERVICE_NAME" ]; then
  echo "用法: $0 <SERVICE_NAME>"
  echo "示例: $0 HDFS"
  echo "可用服务: HDFS, YARN, HIVE, HBASE, SPARK2"
  exit 1
fi

echo "目标服务: ${SERVICE_NAME}"

# 检查服务是否存在
SERVICE_CHECK=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/services/${SERVICE_NAME})

if [ -z "$SERVICE_CHECK" ]; then
  echo "    [ERROR] 服务不存在: ${SERVICE_NAME}"
  exit 1
fi

# 停止服务
echo "正在停止服务 ${SERVICE_NAME}..."
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  -X PUT \
  -H "X-Requested-By: ambari" \
  -d '{"RequestInfo": {"context": "停止服务"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/services/${SERVICE_NAME}

# 等待停止完成
echo "等待服务停止完成..."
sleep 30

# 启动服务
echo "正在启动服务 ${SERVICE_NAME}..."
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  -X PUT \
  -H "X-Requested-By: ambari" \
  -d '{"RequestInfo": {"context": "启动服务"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/services/${SERVICE_NAME}

echo "=========================================="
echo "  服务 ${SERVICE_NAME} 重启请求已提交"
echo "  请在 Ambari UI 中查看进度"
echo "=========================================="
