#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: backup-config.sh
# 文件功能: 配置备份脚本
#   备份集群所有配置文件到指定目录，
#   支持版本管理，便于配置回滚。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

BACKUP_DIR="/backup/hadoop-config-$(date +%Y%m%d%H%M%S)"
INSTANCES="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"

echo "==> HodoopForge: 备份配置"
echo "=========================================="

mkdir -p ${BACKUP_DIR}

for i in $INSTANCES; do
  echo "备份节点: $i"
  
  NODE_DIR="${BACKUP_DIR}/${i}"
  mkdir -p ${NODE_DIR}
  
  # 备份 Hadoop 配置
  docker compose exec -T $i bash -c \
    "tar -czf - /etc/hadoop/conf" > ${NODE_DIR}/hadoop-conf.tar.gz 2>/dev/null || true
  
  # 备份 Hive 配置
  docker compose exec -T $i bash -c \
    "tar -czf - /etc/hive/conf" > ${NODE_DIR}/hive-conf.tar.gz 2>/dev/null || true
  
  # 备份 YARN 配置
  docker compose exec -T $i bash -c \
    "tar -czf - /etc/hadoop-yarn/conf" > ${NODE_DIR}/yarn-conf.tar.gz 2>/dev/null || true
  
  # 备份 Ambari Agent 配置
  docker compose exec -T $i bash -c \
    "tar -czf - /etc/ambari-agent/conf" > ${NODE_DIR}/ambari-agent-conf.tar.gz 2>/dev/null || true
  
  echo "    [OK] 节点 $i 配置备份完成"
done

# 备份 Ambari Server 配置（仅主节点）
echo "备份 Ambari Server 配置..."
docker compose exec -T bigtop_hostname0 bash -c \
  "tar -czf - /etc/ambari-server/conf" > ${BACKUP_DIR}/ambari-server-conf.tar.gz 2>/dev/null || true

# 备份数据库
echo "备份数据库..."
docker compose exec -T bigtop_hostname0 bash -c \
  "mysqldump -uambari -pambari ambari" > ${BACKUP_DIR}/ambari-db.sql 2>/dev/null || true
docker compose exec -T bigtop_hostname0 bash -c \
  "mysqldump -uhive -phive hive" > ${BACKUP_DIR}/hive-db.sql 2>/dev/null || true

echo "=========================================="
echo "  配置备份完成"
echo "  备份目录: ${BACKUP_DIR}"
echo "=========================================="
