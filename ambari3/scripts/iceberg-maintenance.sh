#!/usr/bin/env bash
# ============================================================
# Iceberg ODS 小文件治理与快照清理
# 文件: ambari3/scripts/iceberg-maintenance.sh
# 用途: 对流式写入的 ODS 表执行 rewrite_data_files / expire_snapshots
# 用法: bash iceberg-maintenance.sh [--dry-run]
# 注意:
#   1) hadoop catalog 无分布式锁，执行前建议暂停 Flink 作业或选低峰期
#   2) 仅处理 ODS（Flink 写入）；DWD/DWS/ADS 由 Spark 侧维护
#   3) 先 --dry-run 查看文件数，再实跑
# ============================================================
set -u

H1=bigtop_hostname1
JDBC='jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/default;transportMode=binary'
USER=spark
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

TABLES=(
  "edulake_ai.ods_llm_inference_log"
  "edulake_knowledge.ods_rag_query_log"
)

run_sql() {
  docker exec "$H1" bash -c "beeline -u '$JDBC' -n $USER -e \"$1\" 2>&1" \
    | grep -vE "SLF4J|WARN|INFO|Beeline|Closing|Connected|Transaction"
}

echo "=============================================="
echo " Iceberg ODS 维护  $(date '+%F %T')  dry-run=$DRY"
echo "=============================================="

for T in "${TABLES[@]}"; do
  echo ""
  echo "── $T ──"

  # 1) 数据文件统计
  echo "[文件统计]"
  run_sql "SELECT count(*) AS files, sum(file_size_in_bytes) AS bytes FROM iceberg.$T.files;" | tail -6

  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] 跳过 rewrite/expire"
    continue
  fi

  # 2) 合并小文件（目标 128MB）
  echo "[rewrite_data_files]"
  run_sql "CALL iceberg.system.rewrite_data_files(table => '$T', options => map('target-file-size-bytes','134217728','min-input-files','5'));" | tail -8

  # 3) 清理旧快照（保留最近 3 个，7 天前）
  echo "[expire_snapshots]"
  run_sql "CALL iceberg.system.expire_snapshots(table => '$T', older_than => TIMESTAMPADD(DAY, -7, CURRENT_TIMESTAMP), retain_last => 3);" | tail -8
done

echo ""
echo "=============================================="
echo " 完成。建议随后执行 flink-health-check.sh 复核。"
echo "=============================================="
