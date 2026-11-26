# TC-SPARK-001 Spark on YARN 作业

- 级别：P1
- 前置：YARN RM@h0:8088，NM@h1/h2/h3；Spark HistoryServer@h0:18081
- 关联：IT-SPARK-001/003

## 步骤

```bash
docker exec bigtop_hostname0 bash -c "
  spark-submit --master yarn --deploy-mode client \
    --class org.apache.spark.examples.SparkPi \
    /usr/bigtop/current/spark-client/examples/jars/spark-examples*.jar 10
"
# 作业后检查历史
docker exec bigtop_hostname0 bash -c "curl -sf http://localhost:18081/api/v1/applications | head -c 200"
```

## 期望

- 输出 `Pi is roughly 3.14...`
- HistoryServer 能列出应用

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | ⏳ 待执行 | 18081 正常 |
