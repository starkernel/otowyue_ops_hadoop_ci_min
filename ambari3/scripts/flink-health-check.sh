#!/usr/bin/env bash
# ============================================================
# Flink 实时链路健康检查（EduLake）
# 文件: ambari3/scripts/flink-health-check.sh
# 用途: 检查 Flink 作业、checkpoint、Kafka lag、bridge 状态、ODS 重复
# 用法: bash flink-health-check.sh
# ============================================================
set -u

H0=bigtop_hostname0
H1=bigtop_hostname1
JM=http://localhost:8081
KAFKA_BIN=/usr/bigtop/current/kafka-broker/bin
BOOTSTRAP=bigtop-hostname0.bigtop.apache.org:9092
SPARK_JDBC='jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/default;transportMode=binary'
PASS=0; FAIL=0
ok(){ echo "  PASS  $*"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

echo "=============================================="
echo " Flink 实时链路健康检查  $(date '+%F %T')"
echo "=============================================="

# 1) Flink 作业
echo "[1] Flink 作业"
JOBS=$(docker exec $H0 bash -c "curl -s --max-time 5 $JM/jobs/overview" 2>/dev/null)
RUNNING=$(echo "$JOBS" | python3 -c "import sys,json;print(sum(1 for j in json.load(sys.stdin).get('jobs',[]) if j['state']=='RUNNING'))" 2>/dev/null || echo 0)
[ "$RUNNING" -ge 2 ] && ok "RUNNING 作业数=$RUNNING (期望 2)" || bad "RUNNING 作业数=$RUNNING (期望 2)"

# 2) TaskManager / slots
echo "[2] 资源"
OV=$(docker exec $H0 bash -c "curl -s --max-time 5 $JM/overview" 2>/dev/null)
TM=$(echo "$OV" | python3 -c "import sys,json;print(json.load(sys.stdin).get('taskmanagers',0))" 2>/dev/null || echo 0)
SL=$(echo "$OV" | python3 -c "import sys,json;print(json.load(sys.stdin).get('slots-total',0))" 2>/dev/null || echo 0)
[ "$TM" -ge 2 ] && ok "TaskManager=$TM" || bad "TaskManager=$TM (期望 >=2)"
[ "$SL" -ge 4 ] && ok "slots=$SL" || bad "slots=$SL (期望 >=4)"

# 3) checkpoint
echo "[3] Checkpoint"
for JID in $(echo "$JOBS" | python3 -c "import sys,json;[print(j['jid']) for j in json.load(sys.stdin).get('jobs',[]) if j['state']=='RUNNING']" 2>/dev/null); do
  CP=$(docker exec $H0 bash -c "curl -s --max-time 5 $JM/jobs/$JID/checkpoints" 2>/dev/null)
  C=$(echo "$CP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('counts',{}).get('completed',0))" 2>/dev/null || echo 0)
  F=$(echo "$CP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('counts',{}).get('failed',0))" 2>/dev/null || echo 0)
  [ "$C" -ge 1 ] && ok "job ${JID:0:8} checkpoint completed=$C failed=$F" || bad "job ${JID:0:8} 无成功 checkpoint"
done

# 4) Kafka lag
echo "[4] Kafka 消费 lag"
for G in edulake_flink_ai_v3 edulake_flink_rag_v3; do
  LAG=$(docker exec $H0 bash -c "$KAFKA_BIN/kafka-consumer-groups.sh --bootstrap-server $BOOTSTRAP --describe --group $G 2>/dev/null" | awk 'NR>1{sum+=$6} END{print sum+0}')
  [ "$LAG" -eq 0 ] && ok "group $G lag=0" || bad "group $G lag=$LAG"
done

# 5) bridge 是否停止（只看是否有活跃 CONSUMER-ID，忽略 lag）
echo "[5] Python bridge 状态"
ACT=$(docker exec $H0 bash -c "$KAFKA_BIN/kafka-consumer-groups.sh --bootstrap-server $BOOTSTRAP --describe --group edulake_bridge_ai_inference_log 2>/dev/null" \
  | awk -F'\t' 'NR>1 {gsub(/ +$/,"",$7); if ($1 ~ /edulake_bridge/ && $7!="-" && $7!="") c++} END{print c+0}')
[ "$ACT" -eq 0 ] && ok "bridge 已停止（无活跃 consumer）" || bad "bridge 仍有 $ACT 个活跃 consumer"

# 6) ODS 重复主键
echo "[6] ODS 主键重复"
DUP=$(docker exec $H1 bash -c "beeline -u '$SPARK_JDBC' -n spark -e \"
SELECT count(*) FROM (
  SELECT log_id FROM iceberg.edulake_ai.ods_llm_inference_log GROUP BY log_id HAVING count(*)>1
) t;\"" 2>/dev/null | grep -oE '^\| [0-9]+' | head -1 | tr -d '| ')
if [ -z "$DUP" ]; then
  echo "  SKIP  无法连接 Spark ThriftServer"
else
  [ "$DUP" -eq 0 ] && ok "llm 重复主键=0" || bad "llm 重复主键=$DUP"
fi

echo "=============================================="
echo " PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ] && echo " RESULT: HEALTHY" || echo " RESULT: ATTENTION NEEDED"
exit $([ $FAIL -eq 0 ] && echo 0 || echo 1)
