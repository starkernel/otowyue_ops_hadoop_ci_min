# 性能测试方案（PERFORMANCE TEST）

> 更新：2026-10-29

## 1. 测试环境

| 项 | 值 |
|---|---|
| 集群 | qixuandata，4 节点（h0 16g / h1 8g / h2 7g / h3 7g） |
| 宿主机 | 约 40GB 内存 / 8GB Swap |
| 模式 | 非安全（无 Kerberos） |
| 数据规模 | 小规模（1-10GB） |

## 2. 指标定义

| 指标 | 定义 | 采集方式 |
|---|---|---|
| 吞吐 | MB/s 或 ops/s | 计时 + 数据量 |
| 延迟 | P50/P95/P99 | 多次采样 |
| 资源 | CPU/内存/GC | `ps`, `jstat`, AMS |
| 并发 | 线程/连接数 | 压测工具 |

## 3. 测试项

### 3.1 HDFS

```bash
# 写吞吐（1GB）
dd if=/dev/zero of=/tmp/1g bs=1M count=1024
time hdfs dfs -put /tmp/1g /test/1g
# 读吞吐
time hdfs dfs -cat /test/1g > /dev/null
# 清理
hdfs dfs -rm /test/1g
```

目标：写 > 100 MB/s，读 > 150 MB/s。

### 3.2 YARN / MapReduce

```bash
time yarn jar /usr/bigtop/current/hadoop-mapreduce-client/hadoop-mapreduce-examples.jar \
  pi 4 1000
```

目标：5 分钟内完成。

### 3.3 Hive

```bash
beeline -u jdbc:hive2://h0:10000 -e "
  create table if not exists perf_t(id int) stored as orc;
  insert into perf_t select /*+ REPARTITION(1) */ 1;
  select count(*) from perf_t;"
```

目标：简单查询 < 60s。

### 3.4 HBase

```bash
# 写入 10 万行（YCSB 或 shell）
hbase shell <<'EOF'
create 'perf','f'
EOF
# 使用 org.apache.hadoop.hbase.PerformanceEvaluation
hbase org.apache.hadoop.hbase.PerformanceEvaluation --rows=100000 randomWrite perf
hbase org.apache.hadoop.hbase.PerformanceEvaluation --rows=100000 randomRead perf
```

目标：随机读 P99 < 50ms。

### 3.5 Kafka

```bash
kafka-producer-perf-test.sh --topic perf --num-records 100000 \
  --record-size 1024 --throughput -1 \
  --producer-props bootstrap.servers=h0:9092
kafka-consumer-perf-test.sh --topic perf --messages 100000 \
  --bootstrap-server h0:9092
```

目标：生产 > 5 MB/s。

### 3.6 Spark

```bash
time spark-submit --master yarn --deploy-mode client \
  --class org.apache.spark.examples.SparkPi \
  /usr/bigtop/current/spark-client/examples/jars/spark-examples*.jar 10
```

目标：< 2 min。

### 3.7 Flink

```bash
flink run -c org.apache.flink.streaming.examples.wordcount.WordCount \
  /usr/lib/flink/examples/streaming/WordCount.jar --input /etc/hosts --output /tmp/out
```

目标：作业正常完成，无背压。

## 4. 资源基线采集

```bash
# JVM GC（示例）
jstat -gc <pid> 1000 5
# 进程内存
ps -eo pid,rss,comm --sort=-rss | head -15
# 系统
free -m; uptime; cat /proc/swaps
```

## 5. 结果记录表

| 日期 | 用例 | 指标 | 结果 | 目标 | 达标 |
|---|---|---|---|---|---|
| 2026-10-29 | HDFS 写 1GB | MB/s | 待测 | >100 | ⏳ |
| 2026-10-29 | HDFS 读 1GB | MB/s | 待测 | >150 | ⏳ |
| 2026-10-29 | MR Pi | s | 待测 | <300 | ⏳ |
| 2026-10-29 | Hive 查询 | s | 待测 | <60 | ⏳ |
| 2026-10-29 | HBase 随机读 | ms(P99) | 待测 | <50 | ⏳ |
| 2026-10-29 | Kafka 生产 | MB/s | 待测 | >5 | ⏳ |
| 2026-10-29 | Spark Pi | s | 待测 | <120 | ⏳ |
