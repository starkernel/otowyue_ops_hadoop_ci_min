#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: clean-cluster.sh
# 文件功能: 集群清理脚本
#   清理集群临时文件、日志、缓存等，
#   释放磁盘空间，保持集群整洁。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

INSTANCES="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"

echo "==> HodoopForge: 清理集群"
echo "=========================================="

for i in $INSTANCES; do
  echo "清理节点: $i"
  
  # 清理 YARN 临时目录
  docker compose exec -T $i bash -c \
    "rm -rf /data/hadoop/yarn/nm/usercache/*/appcache/application_*" \
    2>/dev/null || true
  
  # 清理 Spark 临时目录
  docker compose exec -T $i bash -c \
    "rm -rf /tmp/spark-*" 2>/dev/null || true
  
  # 清理 Hive 临时文件
  docker compose exec -T $i bash -c \
    "rm -rf /tmp/hive/*" 2>/dev/null || true
  
  # 清理旧日志（保留最近7天）
  docker compose exec -T $i bash -c \
    "find /var/log -name '*.log' -mtime +7 -delete" 2>/dev/null || true
  
  # 清理系统临时文件
  docker compose exec -T $i bash -c \
    "rm -rf /tmp/*" 2>/dev/null || true
  
  echo "    [OK] 节点 $i 清理完成"
done

# 清理 HDFS 临时目录
echo "清理 HDFS 临时目录..."
if command -v hdfs &> /dev/null; then
  hdfs dfs -rm -r /tmp/hive/* 2>/dev/null || true
  hdfs dfs -rm -r /tmp/spark/* 2>/dev/null || true
  echo "    [OK] HDFS 临时目录清理完成"
fi

echo "=========================================="
echo "  集群清理完成"
echo "=========================================="
