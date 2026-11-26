#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: log-collect.sh
# 文件功能: 日志收集脚本
#   收集集群所有节点的日志文件，打包归档，
#   用于故障分析和问题排查。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

# 配置参数
OUTPUT_DIR="/tmp/hadoop-logs-$(date +%Y%m%d%H%M%S)"
INSTANCES="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"

echo "==> HodoopForge: 收集集群日志"
echo "=========================================="

# 创建输出目录
mkdir -p ${OUTPUT_DIR}

# 收集每个节点的日志
for i in $INSTANCES; do
  echo "正在收集节点: $i"
  
  NODE_DIR="${OUTPUT_DIR}/${i}"
  mkdir -p ${NODE_DIR}
  
  # Ambari Agent 日志
  docker compose exec -T $i cat /var/log/ambari-agent/ambari-agent.log \
    > ${NODE_DIR}/ambari-agent.log 2>/dev/null || true
  
  # Ambari Server 日志（仅主节点）
  if [ "$i" = "bigtop_hostname0" ]; then
    docker compose exec -T $i cat /var/log/ambari-server/ambari-server.log \
      > ${NODE_DIR}/ambari-server.log 2>/dev/null || true
  fi
  
  # HDFS 日志
  docker compose exec -T $i bash -c \
    "find /var/log/hadoop -name '*.log' -exec cat {} \;" \
    > ${NODE_DIR}/hdfs.log 2>/dev/null || true
  
  # YARN 日志
  docker compose exec -T $i bash -c \
    "find /var/log/hadoop-yarn -name '*.log' -exec cat {} \;" \
    > ${NODE_DIR}/yarn.log 2>/dev/null || true
  
  # Hive 日志
  docker compose exec -T $i bash -c \
    "find /var/log/hive -name '*.log' -exec cat {} \;" \
    > ${NODE_DIR}/hive.log 2>/dev/null || true
  
  echo "    [OK] 节点 $i 日志收集完成"
done

# 打包归档
echo "正在打包归档..."
tar -czf ${OUTPUT_DIR}.tar.gz -C /tmp $(basename ${OUTPUT_DIR})
rm -rf ${OUTPUT_DIR}

echo "=========================================="
echo "  日志收集完成"
echo "  归档文件: ${OUTPUT_DIR}.tar.gz"
echo "=========================================="
