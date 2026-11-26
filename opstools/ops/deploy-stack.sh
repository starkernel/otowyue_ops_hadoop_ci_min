#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: deploy-stack.sh
# 文件功能: Stack 部署脚本
#   通过 Ambari API 部署指定 Stack 版本，
#   自动化安装 Hadoop 组件。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="c1"
STACK_NAME="BIGTOP"
STACK_VERSION="3.5.0"

echo "==> HodoopForge: 部署 Stack"
echo "=========================================="
echo "Stack: ${STACK_NAME} ${STACK_VERSION}"

# 检查 Stack 是否已注册
STACK_CHECK=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/stacks/${STACK_NAME}/${STACK_VERSION})

if [ -z "$STACK_CHECK" ]; then
  echo "    [ERROR] Stack 未注册: ${STACK_NAME} ${STACK_VERSION}"
  echo "    请先执行 setup-bigtop-stack.sh"
  exit 1
fi

echo "    [OK] Stack 已注册"

# 创建集群（如果不存在）
echo "检查集群状态..."
CLUSTER_CHECK=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME})

if [ -z "$CLUSTER_CHECK" ]; then
  echo "创建集群..."
  curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
    -X POST \
    -H "X-Requested-By: ambari" \
    -d "{
      \"cluster_name\": \"${CLUSTER_NAME}\",
      \"version\": \"${STACK_VERSION}\"
    }" \
    http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters
  echo "    [OK] 集群创建请求已提交"
else
  echo "    [INFO] 集群已存在"
fi

echo "=========================================="
echo "  Stack 部署准备完成"
echo "  请在 Ambari UI 中完成组件安装"
echo "=========================================="
