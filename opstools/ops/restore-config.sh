#!/bin/bash
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: restore-config.sh
# 文件功能: 配置恢复脚本
#   从备份目录恢复配置文件，
#   用于配置回滚或灾难恢复。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

set -e

if [ -z "$1" ]; then
  echo "用法: $0 <BACKUP_DIR>"
  echo "示例: $0 /backup/hadoop-config-20260401120000"
  exit 1
fi

BACKUP_DIR=$1
INSTANCES="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"

echo "==> HodoopForge: 恢复配置"
echo "=========================================="
echo "备份目录: ${BACKUP_DIR}"

if [ ! -d "${BACKUP_DIR}" ]; then
  echo "    [ERROR] 备份目录不存在"
  exit 1
fi

for i in $INSTANCES; do
  echo "恢复节点: $i"
  
  NODE_DIR="${BACKUP_DIR}/${i}"
  
  if [ ! -d "${NODE_DIR}" ]; then
    echo "    [SKIP] 节点 $i 备份不存在"
    continue
  fi
  
  # 恢复 Hadoop 配置
  if [ -f "${NODE_DIR}/hadoop-conf.tar.gz" ]; then
    docker compose exec -T $i bash -c \
      "tar -xzf - -C /" < ${NODE_DIR}/hadoop-conf.tar.gz
    echo "    [OK] Hadoop 配置已恢复"
  fi
  
  # 恢复 Hive 配置
  if [ -f "${NODE_DIR}/hive-conf.tar.gz" ]; then
    docker compose exec -T $i bash -c \
      "tar -xzf - -C /" < ${NODE_DIR}/hive-conf.tar.gz
    echo "    [OK] Hive 配置已恢复"
  fi
  
  # 恢复 YARN 配置
  if [ -f "${NODE_DIR}/yarn-conf.tar.gz" ]; then
    docker compose exec -T $i bash -c \
      "tar -xzf - -C /" < ${NODE_DIR}/yarn-conf.tar.gz
    echo "    [OK] YARN 配置已恢复"
  fi
  
  # 恢复 Ambari Agent 配置
  if [ -f "${NODE_DIR}/ambari-agent-conf.tar.gz" ]; then
    docker compose exec -T $i bash -c \
      "tar -xzf - -C /" < ${NODE_DIR}/ambari-agent-conf.tar.gz
    echo "    [OK] Ambari Agent 配置已恢复"
  fi
done

# 恢复 Ambari Server 配置
if [ -f "${BACKUP_DIR}/ambari-server-conf.tar.gz" ]; then
  echo "恢复 Ambari Server 配置..."
  docker compose exec -T bigtop_hostname0 bash -c \
    "tar -xzf - -C /" < ${BACKUP_DIR}/ambari-server-conf.tar.gz
  echo "    [OK] Ambari Server 配置已恢复"
fi

echo "=========================================="
echo "  配置恢复完成"
echo "  请重启相关服务使配置生效"
echo "=========================================="
