# TC-AMS-001 AMS 指标采集与上报

- 级别：P1
- 前置：AMS Collector@h0:6188，Monitor@h0-h3，ams-hbase
- 关联：IT-AMS-001/002，BUG-017~022

## 步骤

```bash
# 1. Collector metadata
docker exec bigtop_hostname0 bash -c \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:6188/ws/v1/timeline/metrics/metadata"
# 2. 各主机上报（proc_run）
NOW=$(date +%s); START=$(( (NOW-600)*1000 )); END=$(( NOW*1000 ))
for i in 0 1 2 3; do
  H=bigtop-hostname$i.bigtop.apache.org
  docker exec bigtop_hostname0 bash -c \
    "curl -s 'http://localhost:6188/ws/v1/timeline/metrics?metricNames=proc_run&hostname=$H&appId=HOST&startTime=$START&endTime=$END&precision=seconds'" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print('$H', len(d.get('metrics',[])))"
done
# 3. Monitor 进程
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  echo -n "$h monitor: "; docker exec $h pgrep -f 'resource_monitoring/main.py' | wc -l
done
```

## 期望

- 步骤 1 返回 `200`
- 步骤 2 四台主机均有 `metrics` 数据
- 步骤 3 每台 monitor 进程 ≥ 1

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | ✅ PASS | 6188 HTTP 200；4 主机 proc_run 有数据点 |
