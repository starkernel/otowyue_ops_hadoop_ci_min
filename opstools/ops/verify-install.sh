#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: verify-install.sh
# 文件功能: 安装验证脚本
#   验证集群各组件是否正确安装和运行，
#   输出验证报告。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

AMBARI_HOST="localhost"
AMBARI_PORT="20609"
AMBARI_USER="admin"
AMBARI_PASS="admin"
CLUSTER_NAME="c1"

echo "==> HodoopForge: 安装验证"
echo "=========================================="

# 验证1: Ambari Server
echo "[1/10] 验证 Ambari Server..."
if curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/stacks > /dev/null; then
  echo "    [OK] Ambari Server 运行正常"
else
  echo "    [FAIL] Ambari Server 无法访问"
fi

# 验证2: 集群状态
echo "[2/10] 验证集群状态..."
CLUSTER_STATE=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME} \
  | jq -r '.Clusters.provisioning_state')
echo "    集群状态: ${CLUSTER_STATE}"

# 验证3: HDFS
echo "[3/10] 验证 HDFS..."
if command -v hdfs &> /dev/null; then
  if hdfs dfs -ls / > /dev/null 2>&1; then
    echo "    [OK] HDFS 运行正常"
  else
    echo "    [FAIL] HDFS 无法访问"
  fi
else
  echo "    [SKIP] hdfs 命令不可用"
fi

# 验证4: YARN
echo "[4/10] 验证 YARN..."
if command -v yarn &> /dev/null; then
  if yarn node -list > /dev/null 2>&1; then
    echo "    [OK] YARN 运行正常"
  else
    echo "    [FAIL] YARN 无法访问"
  fi
else
  echo "    [SKIP] yarn 命令不可用"
fi

# 验证5: Hive
echo "[5/10] 验证 Hive..."
if command -v beeline &> /dev/null; then
  echo "    [OK] Hive 客户端已安装"
else
  echo "    [SKIP] beeline 命令不可用"
fi

# 验证6: Spark
echo "[6/10] 验证 Spark..."
if command -v spark-submit &> /dev/null; then
  echo "    [OK] Spark 客户端已安装"
else
  echo "    [SKIP] spark-submit 命令不可用"
fi

# 验证7: 节点注册
echo "[7/10] 验证节点注册..."
NODE_COUNT=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/hosts \
  | jq -r '.items | length')
echo "    已注册节点: ${NODE_COUNT}/4"

# 验证8: 服务状态
echo "[8/10] 验证服务状态..."
RUNNING_SERVICES=$(curl -s -u ${AMBARI_USER}:${AMBARI_PASS} \
  http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_NAME}/services \
  | jq -r '.items[] | select(.State=="STARTED") | .ServiceName' | wc -l)
echo "    运行中服务: ${RUNNING_SERVICES}"

# 验证9: 端口监听
echo "[9/10] 验证端口监听..."
if netstat -tlnp | grep :8080 > /dev/null; then
  echo "    [OK] Ambari 端口 8080 监听中"
fi
if netstat -tlnp | grep :8020 > /dev/null; then
  echo "    [OK] HDFS 端口 8020 监听中"
fi

# 验证10: 日志检查
echo "[10/10] 验证日志..."
if [ -f /var/log/ambari-server/ambari-server.log ]; then
  ERROR_COUNT=$(grep -i error /var/log/ambari-server/ambari-server.log | wc -l)
  echo "    Ambari Server 错误数: ${ERROR_COUNT}"
fi

echo "=========================================="
echo "  安装验证完成"
echo "=========================================="
