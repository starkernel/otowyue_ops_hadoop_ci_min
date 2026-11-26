# 冒烟测试（SMOKE TEST）

> 快速健康检查，每次变更后执行。全部 PASS 方可继续。
> 更新：2026-10-29

## 1. 主机与服务探活脚本

```bash
#!/usr/bin/env bash
# quick-smoke.sh — 在宿主机执行
set -u
AMB="http://localhost:20609/api/v1/clusters/qixuandata"
AUTH="admin:admin"
HDR="X-Requested-By: ambari"
PASS=0; FAIL=0
chk() { # chk <name> <cmd>
  if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; PASS=$((PASS+1));
  else echo "FAIL  $1"; FAIL=$((FAIL+1)); fi
}

# --- 容器 ---
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  chk "container $h running" "docker ps --filter name=$h --filter status=running | grep -q $h"
done

# --- h0 端口 ---
for p in 2181 8020 50070 8088 16000 16010 10000 9083 6080 9292 8886 9092 18081 8081 19888 8198 6188 3000; do
  chk "h0 port $p" "docker exec bigtop_hostname0 ss -ltn | grep -q ':$p '"
done

# --- h1 端口 ---
for p in 2181 50075 50090 8042 8188 10016; do
  chk "h1 port $p" "docker exec bigtop_hostname1 ss -ltn | grep -q ':$p '"
done

# --- h2 端口 ---
for p in 2181 50075 8042; do
  chk "h2 port $p" "docker exec bigtop_hostname2 ss -ltn | grep -q ':$p '"
done

# --- h3 端口 ---
for p in 16020 16030 50075 8042 20010 8111 50071; do
  chk "h3 port $p" "docker exec bigtop_hostname3 ss -ltn | grep -q ':$p '"
done

# --- HTTP 探活 ---
chk "Ambari API" "curl -sf -u $AUTH -H '$HDR' $AMB >/dev/null"
chk "AMS metadata" "docker exec bigtop_hostname0 curl -sf --max-time 5 http://localhost:6188/ws/v1/timeline/metrics/metadata >/dev/null"
chk "Grafana" "docker exec bigtop_hostname0 curl -sf --max-time 5 http://localhost:3000/login >/dev/null"
chk "Ranger Admin" "docker exec bigtop_hostname0 curl -sf --max-time 5 http://localhost:6080/login.jsp >/dev/null"
chk "NameNode UI" "docker exec bigtop_hostname0 curl -sf --max-time 5 http://localhost:50070/ >/dev/null"
chk "ResourceManager UI" "docker exec bigtop_hostname0 curl -sf --max-time 5 http://localhost:8088/ >/dev/null"

# --- 告警 ---
NONOK=$(curl -s -u $AUTH -H "$HDR" "$AMB/alerts?fields=*" | python3 -c "import sys,json;print(sum(1 for i in json.load(sys.stdin).get('items',[]) if i['Alert']['state']!='OK'))")
chk "alerts non-OK == 0 (actual=$NONOK)" "[ \"$NONOK\" = \"0\" ]"

# --- 主机健康 ---
for h in bigtop-hostname0 bigtop-hostname1 bigtop-hostname2 bigtop-hostname3; do
  st=$(curl -s -u $AUTH -H "$HDR" "$AMB/hosts/$h.bigtop.apache.org?fields=Hosts/host_state" | python3 -c "import sys,json;print(json.load(sys.stdin)['Hosts']['host_state'])" 2>/dev/null)
  chk "host $h HEALTHY (actual=$st)" "[ \"$st\" = \"HEALTHY\" ]"
done

echo "=============================="
echo "PASS=$PASS  FAIL=$FAIL"
[ $FAIL -eq 0 ] && echo "SMOKE: PASS" || echo "SMOKE: FAIL"
```

## 2. 资源健康检查

```bash
# Swap 使用率（阈值 < 80%）
docker exec bigtop_hostname0 free -m | awk '/Swap/{printf "Swap used: %.1f%%\n", $3/$2*100}'
# 内存可用（> 8GB）
docker exec bigtop_hostname0 free -m | awk '/Mem/{printf "Available: %d MB\n", $7}'
# Load
docker exec bigtop_hostname0 uptime
```

## 3. 检查项汇总

| # | 检查项 | 期望 | 结果 |
|---|---|---|---|
| 1 | 4 容器 running | 全部 | |
| 2 | h0 端口（18 项） | 全部 LISTEN | |
| 3 | h1 端口（6 项） | 全部 LISTEN | |
| 4 | h2 端口（3 项） | 全部 LISTEN | |
| 5 | h3 端口（7 项） | 全部 LISTEN | |
| 6 | Ambari/AMS/Grafana/Ranger/NN/RM HTTP | 200 | |
| 7 | 非 OK 告警 | 0 | |
| 8 | 4 主机状态 | HEALTHY | |
| 9 | Swap 使用率 | < 80% | |
| 10 | Mem available | > 8GB | |

## 4. 最近执行记录

| 日期 | 执行人 | PASS/FAIL | 备注 |
|---|---|---|---|
| 2026-10-29 | — | 待执行 | 内存调优后首轮 |
