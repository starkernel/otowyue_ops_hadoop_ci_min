# 04 · 用户使用指南（场景化实操）

> 版本：v3.0 · 2026-11-09  
> 读者：数据开发、业务分析、算法工程师  
> **v3.0 更新**：Spark catalog `newice` + warehouse `hdfs://qixuandata/iceberg-warehouse-ha`；Kafka 三 broker 接入；实时链路 ≤25s。

---

## 1. 快速上手（5 分钟）

### 1.1 连接入口

| 用途 | 连接串 | 账号 |
|---|---|---|
| **交互查询（推荐）** | `jdbc:hive2://192.168.0.60:10016/default;transportMode=binary` | 无 |
| Hive SQL | `jdbc:hive2://192.168.0.60:10000/default` | hive |
| HDFS | `hdfs dfs -ls /` | — |
| Kafka | `bigtop-hostname0.bigtop.apache.org:9092,bigtop-hostname2.bigtop.apache.org:9092,bigtop-hostname3.bigtop.apache.org:9092` | — |
| Flink UI | `http://192.168.0.60:8081` | — |
| Ambari | `http://192.168.0.60:20609` | admin/admin |

> `192.168.0.60` 是宿主机 NAT 别名；生产客户端建议直接使用三 broker FQDN，避免单点。

### 1.2 第一条查询

```bash
beeline -u 'jdbc:hive2://192.168.0.60:10016/default;transportMode=binary' -n spark

0: jdbc:hive2://...> SHOW DATABASES;
0: jdbc:hive2://...> SELECT count(*) FROM newice.edulake_ai.ods_llm_inference_log;
```

---

## 2. 场景一：查询实时数据

```sql
-- 按日期统计
SELECT dt, count(*) AS cnt
FROM newice.edulake_ai.ods_llm_inference_log
GROUP BY dt ORDER BY dt DESC;

-- 最近 1 小时（按 Asia/Shanghai）
SELECT *
FROM newice.edulake_ai.ods_llm_inference_log
WHERE request_at >= current_timestamp() - INTERVAL 1 HOUR
ORDER BY request_at DESC LIMIT 20;

-- 模型性能
SELECT model_name,
       avg(latency_ms) AS avg_latency,
       avg(tok_per_sec) AS avg_tps,
       count(*) AS calls
FROM newice.edulake_ai.ods_llm_inference_log
WHERE dt = date_format(current_date(),'yyyy-MM-dd')
GROUP BY model_name;
```

> 查询走 Spark ThriftServer，比 Hive 快；大表加 `dt` 分区过滤。

---

## 3. 场景二：建 DWD 表

```sql
-- 1) 建表（Iceberg，按 dt 分区）
CREATE TABLE IF NOT EXISTS newice.edulake_ai.dwd_llm_inference_clean
USING iceberg
PARTITIONED BY (dt)
AS
SELECT log_id, user_id_hash, session_id, model_name,
       request_at, token_in, token_out, latency_ms, ttft_ms,
       tok_per_sec, temperature, response_ok, error_msg, etl_time, dt
FROM newice.edulake_ai.ods_llm_inference_log
WHERE response_ok = true AND log_id IS NOT NULL;

-- 2) 增量覆盖（按分区）
INSERT OVERWRITE newice.edulake_ai.dwd_llm_inference_clean
SELECT ... FROM newice.edulake_ai.ods_llm_inference_log
WHERE dt = '2026-11-03';
```

> 规范：DWD 只由 Spark 写；ODS 只由 Flink 写。

---

## 4. 场景三：新增实时接入

```mermaid
flowchart LR
    A["1. 建 Kafka topic"] --> B["2. 建 Iceberg ODS 表"]
    B --> C["3. 编写 Flink SQL"]
    C --> D["4. 提交作业"]
    D --> E["5. 验证"]
```

### 4.1 建 Topic

```bash
kafka-topics.sh --bootstrap-server 192.168.0.60:9092 \
  --create --topic my_event --partitions 3 --replication-factor 1
```

### 4.2 建 ODS 表

```sql
CREATE TABLE newice.edulake_meta.ods_my_event (
  event_id STRING,
  user_id STRING,
  payload STRING,
  request_at TIMESTAMP,
  dt STRING
) USING iceberg PARTITIONED BY (dt);
```

### 4.3 Flink SQL 模板

```sql
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '20s';
SET 'state.checkpoints.dir' = 'hdfs://qixuandata/flink-checkpoints/edulake';
SET 'table.local-time-zone' = 'Asia/Shanghai';

CREATE CATALOG iceberg WITH (
  'type'='iceberg','catalog-type'='hadoop',
  'warehouse'='hdfs://qixuandata/iceberg-warehouse-ha',
  'hadoop-conf-dir'='/etc/hadoop/conf');

CREATE TEMPORARY TABLE src (
  user_id STRING, payload STRING, ts BIGINT,
  kafka_partition INT METADATA FROM 'partition' VIRTUAL,
  kafka_offset BIGINT METADATA FROM 'offset' VIRTUAL
) WITH (
  'connector'='kafka','topic'='my_event',
  'properties.bootstrap.servers'='bigtop-hostname0.bigtop.apache.org:9092',
  'properties.group.id'='edulake_flink_my_event_v1',
  'scan.startup.mode'='group-offsets',
  'format'='json','json.ignore-parse-errors'='true');

INSERT INTO iceberg.edulake_meta.ods_my_event
SELECT CONCAT('evt_', CAST(kafka_partition AS STRING), '_', CAST(kafka_offset AS STRING)),
       user_id, payload,
       CAST(TO_TIMESTAMP_LTZ(ts,3) AS TIMESTAMP),
       DATE_FORMAT(CAST(TO_TIMESTAMP_LTZ(ts,3) AS TIMESTAMP),'yyyy-MM-dd')
FROM src WHERE ts IS NOT NULL;
```

### 4.4 提交

```bash
docker cp my_job.sql bigtop_hostname0:/tmp/my_job.sql
docker exec bigtop_hostname0 bash -c 'su -s /bin/bash flink -c "
  export HADOOP_HOME=/usr/bigtop/current/hadoop-client
  export HADOOP_CONF_DIR=/etc/hadoop/conf
  export HADOOP_CLASSPATH=\$(\$HADOOP_HOME/bin/hadoop classpath)
  /usr/lib/flink/bin/sql-client.sh -Dexecution.target=remote \
    -Drest.address=localhost -Drest.port=8081 -f /tmp/my_job.sql"'
```

---

## 5. 场景四：HBase 点查

```bash
hbase shell
> create 'user_profile', 'info'
> put 'user_profile','u001','info:name','Alice'
> get 'user_profile','u001'
> scan 'user_profile', {LIMIT=>10}
```

> RowKey 设计避免热点；预分区。

---

## 6. 场景五：Kafka 生产消费

```bash
# 生产
kafka-console-producer.sh --bootstrap-server 192.168.0.60:9092 --topic my_event

# 消费（最新）
kafka-console-consumer.sh --bootstrap-server 192.168.0.60:9092 --topic my_event

# 查看 lag
kafka-consumer-groups.sh --bootstrap-server 192.168.0.60:9092 \
  --describe --group edulake_flink_ai_v3
```

---

## 7. 场景六：Iceberg 时间旅行

```sql
-- 查看快照
SELECT snapshot_id, committed_at, operation FROM newice.edulake_ai.ods_llm_inference_log.snapshots;

-- 查询历史版本
SELECT * FROM newice.edulake_ai.ods_llm_inference_log VERSION AS OF 8615725578376075883;

-- 文件统计
SELECT count(*) files, sum(file_size_in_bytes) FROM newice.edulake_ai.ods_llm_inference_log.files;
```

---

## 8. 开发规范清单

| 项 | 规范 |
|---|---|
| 库命名 | `edulake_<域>` |
| 表前缀 | ods_/dwd_/dws_/ads_ |
| 分区 | `dt`（yyyy-MM-dd，Asia/Shanghai） |
| 主键 | 业务前缀+partition+offset |
| 写入 | ODS=Flink；DWD+=Spark |
| 压缩 | Parquet + zstd |
| 时间 | 统一 Asia/Shanghai |
| 用户标识 | 哈希（不存原始 ID） |

---

## 9. 常见错误

| 错误 | 原因 | 解决 |
|---|---|---|
| `Table not found` | 表不在 hadoop catalog 路径 | 确认 catalog/warehouse |
| `Schema not found` | HiveCatalog 不可用 | 用 hadoop catalog |
| 查询慢 | 未加 dt 过滤 | 加分区条件 |
| 数据重复 | 双写 | 停 bridge |
| `Connection refused` | 端口/服务 | 查端口、服务状态 |
| Kafka `localhost` 超时 | advertised listener | 用 FQDN |

---

## 10. 权限申请

1. 明确库/表/操作（SELECT/INSERT/ALL）
2. Ranger Admin（6080）提交策略
3. 平台审核
4. 生效后验证

> 当前 Ranger 为 allow-all（待收敛），申请流程先行登记。
