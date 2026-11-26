#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: upgrade-stack.sh
# 文件功能: Stack 升级脚本
#   将集群从当前 Stack 版本升级到新版本，
#   支持滚动升级，最小化服务中断。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="c1"
TARGET_VERSION=${1:-""}

echo "==> HodoopForge: Stack 升级"
echo "=========================================="

if [ -z "$TARGET_VERSION" ]; then
  echo "用法: $0 <TARGET_VERSION>"
  echo "示例: $0 3.6.0"
  exit 1
fi

echo "目标版本: ${TARGET_VERSION}"

# 检查目标版本是否可用
VERSION_CHECK=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/stacks/BIGTOP/${TARGET_VERSION})

if [ -z "$VERSION_CHECK" ]; then
  echo "    [ERROR] 目标版本不可用: ${TARGET_VERSION}"
  exit 1
fi

echo "    [OK] 目标版本可用"

# 获取当前版本
CURRENT_VERSION=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME} \
  | jq -r '.Clusters.version')

echo "当前版本: ${CURRENT_VERSION}"

# 备份当前配置
echo "备份当前配置..."
./backup-config.sh

# 执行升级请求
echo "提交升级请求..."
curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  -X POST \
  -H "X-Requested-By: ambari" \
  -d "{
    \"Upgrade\": {
      \"repository_version\": \"${TARGET_VERSION}\",
      \"upgrade_type\": \"ROLLING\"
    }
  }" \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/upgrades

echo "=========================================="
echo "  升级请求已提交"
echo "  请在 Ambari UI 中监控升级进度"
echo "=========================================="
