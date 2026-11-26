# TC-FLINK-001 Flink Standalone 作业

- 级别：P1
- 前置：Flink JobManager@h0:8081/6123，TaskManager@h2
- 关联：IT-FLINK-001/002/003

## 步骤

```bash
# 1. 查看 TaskManager 注册
docker exec bigtop_hostname0 bash -c "curl -sf http://localhost:8081/taskmanagers | head -c 300"
# 2. 提交 WordCount
docker exec bigtop_hostname0 bash -c "
  flink run -c org.apache.flink.streaming.examples.wordcount.WordCount \
    /usr/lib/flink/examples/streaming/WordCount.jar \
    --input /etc/hosts --output /tmp/flink_wc_out
"
# 3. 检查输出
docker exec bigtop_hostname0 bash -c "head -5 /tmp/flink_wc_out* 2>/dev/null || echo 'no output'"
```

## 期望

- 步骤 1 返回 1 个 TaskManager
- WordCount 作业完成后输出词频

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | ⏳ 待执行 | 8081 监听 |
