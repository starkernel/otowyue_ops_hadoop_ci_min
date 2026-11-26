#!/usr/bin/env bash
# 清理各容器内超过 N 天的轮转日志（默认 14 天），只删除带轮转后缀的文件，
# 不动当前正在写入的 *.log / *.out。
set -u
DAYS="${1:-14}"
CONTAINERS="${CONTAINERS:-bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3}"

for c in $CONTAINERS; do
  before=$(docker exec "$c" bash -c "df -P /var/log | awk 'NR==2{print \$3}'" 2>/dev/null)
  docker exec "$c" bash -c "
    find /var/log -type f -mtime +${DAYS} \
      \( -name '*.log.[0-9]*' -o -name '*.log.20*' -o -name '*.out.[0-9]*' \
         -o -name '*.out.20*' -o -name '*.gz' -o -name '*.log.*.gz' \) \
      -print -delete 2>/dev/null | wc -l" >/tmp/opencode/cleanup-$c.txt 2>&1
  after=$(docker exec "$c" bash -c "df -P /var/log | awk 'NR==2{print \$3}'" 2>/dev/null)
  n=$(cat /tmp/opencode/cleanup-$c.txt 2>/dev/null)
  freed=$(( (before - after) / 1024 ))
  echo "$c: 删除 ${n:-0} 个文件, 释放约 ${freed} MB"
done
