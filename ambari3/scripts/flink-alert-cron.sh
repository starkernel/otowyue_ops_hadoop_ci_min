#!/usr/bin/env bash
# ============================================================
# Flink 链路轻量告警（cron 友好）
# 文件: ambari3/scripts/flink-alert-cron.sh
# 用途: 定期执行 health-check，异常时写告警日志（可扩展 webhook）
# 建议 crontab: */10 * * * * bash <此脚本>
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${FLINK_ALERT_LOG:-/tmp/flink-health.log}"
WEBHOOK="${FLINK_ALERT_WEBHOOK:-}"   # 可选：企业微信/钉钉/Slack webhook

OUT=$(bash "$SCRIPT_DIR/flink-health-check.sh" 2>&1)
RC=$?
TS=$(date '+%F %T')

if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "RESULT: HEALTHY"; then
  echo "$TS OK" >> "$LOG"
  exit 0
fi

{
  echo "$TS ALERT (rc=$RC)"
  echo "$OUT"
  echo "----------------------------------------"
} >> "$LOG"

if [ -n "$WEBHOOK" ]; then
  MSG=$(echo "$OUT" | grep -E "FAIL|RESULT" | head -10 | tr '\n' ';')
  curl -s -m 10 -H 'Content-Type: application/json' \
    -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"[Flink ALERT] $TS $MSG\"}}" \
    "$WEBHOOK" >/dev/null 2>&1 || true
fi

exit 1
