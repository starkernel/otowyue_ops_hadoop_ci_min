# 大数据与 AI 业务场景案例手册(HodoopForge)

> 定位:在 HodoopForge(4 容器 / Spark 3.5.6 / Flink 1.20.1 / Kafka 3.4.1 / Iceberg
> 双引擎湖仓 / Ranger / HBase)上,把 **业界主流业务场景** 拆成"**痛点 → 架构 → 链路 →
> 可演示代码 → 指标/治理**"的案例手册。面向教学与业务方案设计。
>
> 前置阅读:`doc/DATA_LAKE_GOVERNANCE_AND_INTEGRATION.md`(操作层,含版本/端口/踩坑)。
> 约定:标注 ⚠ 表示"需要额外组件(会给坐标与对接契约,本集群默认未内置)";
> 其余命令可直接在本集群演示。

---

## 0. 手册地图

| # | 主题 | 关键范式 | 章节 |
|---|------|---------|------|
| 1 | 业务数据入湖 | 贴源层:全量/CDC/SCD + 幂等 | §1 |
| 2 | 过程记录入湖 | 事件流 + 状态机 + 审计 | §2 |
| 3 | 入湖数据读取 | 三读:BI / 应用 / 数据科学 | §3 |
| 4 | 文件资料入湖 | 对象归档 + 结构化解析 | §4 |
| 5 | AI 过程数据入湖 | 对话/推理轨迹 + 反馈标注 | §5 |
| 6 | AI × RAG | 知识库湖 + 离线 embedding + 检索回流 | §6 |
| 7 | AI 训练数据 | 语料清洗/样本版本化/评估回流 | §7 |
| 8 | 热门行业场景 | 金融/电商/新能源/制造IoT/车联网 | §8 |
| 9 | 入湖设计模式汇总 | 六套可复用模板 | §9 |

---

## 1. 业务数据入湖

### 1.1 贴源层(ODS)设计三个前提

1. **只增不改**:ODS 尽量"附属追加 + 主键幂等",避免直接覆盖历史;
2. **可重放**:失败批次可删后重跑(靠 `etl_batch_id` + 快照回溯);
3. **可对账**:每条链路保留"源行数 vs 湖行数"核对。

### 1.2 案例 A:订单/交易数据入湖(MySQL → 湖)

**模式① 批同步(已经在跑,见操作手册 §3.5 路线二)**:按 `update_time` 增量拉取 → Iceberg。

**模式② 实时 CDC(推荐业务对接,⚠ 需 Flink CDC jar)**

```bash
# 1) 补 Flink CDC connector(本集群 Flink 1.20.1)
docker exec bigtop_hostname0 bash -c '
  curl -sL -o /usr/lib/flink/lib/flink-connector-mysql-cdc-3.2.0.jar \
   "https://repo1.maven.org/maven2/org/apache/flink/flink-connector-mysql-cdc/3.2.0/flink-connector-mysql-cdc-3.2.0.jar"
  chown flink:flink /usr/lib/flink/lib/*.jar'   # ⚠ 重启 FLINK 后生效
```

```sql
-- flink_cdc_mysql2lake.sql(先 SET result-mode/不需要 batch,流式)
CREATE CATALOG demoicb WITH ('type'='iceberg','catalog-type'='hadoop',
  'warehouse'='hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse');
USE CATALOG demoicb;

CREATE TABLE cdc_orders_source (
  order_id BIGINT, user_id BIGINT, amount DECIMAL(12,2), status STRING,
  update_time TIMESTAMP(3), PRIMARY KEY (order_id) NOT ENFORCED
) WITH ('connector'='mysql-cdc',
  'hostname'='bigtop-hostname0.bigtop.apache.org','port'='3306',
  'username'='hive','password'='hive',
  'database-name'='yourdb','table-name'='orders',
  'scan.incremental.snapshot.enabled'='true');

CREATE TABLE lake_orders (
  order_id BIGINT, user_id BIGINT, amount DECIMAL(12,2), status STRING,
  update_time TIMESTAMP(9), PRIMARY KEY (order_id) NOT ENFORCED
);
INSERT INTO lake_orders
  SELECT order_id, user_id, amount, status,
         CAST(update_time AS TIMESTAMP(9)) FROM cdc_orders_source;
-- 提交后 Flink UI(8081)看 RUNNING;改一行 MySQL 数据,秒级反映到湖
```

**要点**
- Iceberg 主键表 + Flink CDC = 湖侧天然 upsert,落地即"ODS 最新一把"(保留历史快照);
- 同一 source 可同时喂 **Kafka**(供他方订阅)与 **Iceberg**(供分析),一次 CDC 多路复用;
- 对账:`SELECT count(*), sum(amount), max(etl) FROM lake_orders` vs MySQL 同口径。

### 1.3 案例 B:埋点/日志批量入湖(采集 → 湖)

```bash
# 采集器(任意外部系统)把 JSON 打进 Kafka topic app_events_raw
echo '{"uid":"1001","event":"click","page":"/home","ts_epoch":1789000000000}' | \
  timeout 15 /usr/lib/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 --topic app_events_raw
```

```sql
-- Flink SQL:解析埋点 → 湖(按天分区,秒级延迟)
CREATE TABLE kafka_events (raw STRING)
  WITH ('connector'='kafka','topic'='app_events_raw',
        'properties.bootstrap.servers'='bigtop-hostname0.bigtop.apache.org:9092',
        'properties.group.id'='lake_events','scan.startup.mode'='earliest-offset',
        'format'='raw');
CREATE TABLE lake_events (
  uid STRING, event STRING, page STRING, ts TIMESTAMP(9), dt STRING,
  PRIMARY KEY (uid, ts) NOT ENFORCED
);
INSERT INTO lake_events
SELECT JSON_VALUE(raw, '$.uid') AS uid,
       JSON_VALUE(raw, '$.event') AS event,
       JSON_VALUE(raw, '$.page') AS page,
       CAST(FROM_UNIXTIME(CAST(JSON_VALUE(raw, '$.ts_epoch') AS BIGINT)/1000) AS TIMESTAMP(9)) AS ts,
       DATE_FORMAT(FROM_UNIXTIME(CAST(JSON_VALUE(raw, '$.ts_epoch') AS BIGINT)/1000),'yyyy-MM-dd') AS dt
FROM kafka_events;
```

> 埋点入湖常见演进:原始 JSON 另存"原始层表"(便于回放)→ DWD 清洗层(去重/过滤 bot)→ DWS。
> 见 §9 模板③。

### 1.4 案例 C:第三方接口数据(定时拉取 → 湖)

```python
# 每天 02:00 由 spark-submit 执行
from pyspark.sql import SparkSession
spark = SparkSession.builder.appName("api_to_lake").config(
  "spark.sql.catalog.iceberg","org.apache.iceberg.spark.SparkCatalog").config(
  "spark.sql.catalog.iceberg.type","hadoop").config(
  "spark.sql.catalog.iceberg.warehouse","hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse").getOrCreate()
df = spark.read.format("json").option("multiLine","true") \
     .load("hdfs://bigtop-hostname0.bigtop.apache.org:8020/data/exchange/push/*.json")
df.writeTo("iceberg.demo.ods_third_party").append()
```
> 第三方数据一般落交换区(`/data/exchange`)再消费,便于审计来源与重放。

### 1.5 入湖红线(checklist)

- 主键/幂等列必须(PK + `etl_batch_id` + `etl_time`);
- 所有入湖都带 `dt` 分区与 `etl_time`;
- 保留 source 指纹(库/表/topic/文件路径)字段,便于血缘反查(§7.5 操作手册);
- 交付前跑"源 vs 湖"对账样例。**为源保留一个可回溯快照**:Iceberg 天然支持。

---

## 2. 过程记录入湖(流程/事件/审计)

### 2.1 概念

"过程"区别于"业务快照":它是**随时间推进的事件序列 + 状态机**:
订单(下单→支付→发货→签收)、工单、审批流、SLA 计时、资金流水、设备运行日志。

### 2.2 建模建议(两张表一套开)

```sql
-- 表1 事件明细(append-only,谁都不能改历史)
CREATE TABLE dwd_order_events (
  event_id      STRING,      -- uuid
  order_id      BIGINT,
  from_state    STRING,
  to_state      STRING,
  actor         STRING,      -- 操作人/系统
  action        STRING,      -- approve/reject/timeout...
  occurred_at   TIMESTAMP(9),
  payload       STRING,      -- 原始报文(json)
  dt            STRING
) USING iceberg PARTITIONED BY (dt);

-- 表2 状态演进(由事件聚合,支持"当前态"与"历史态回溯")
CREATE TABLE dwd_order_state_timeline (
  order_id BIGINT, seq BIGINT, state STRING, valid_from TIMESTAMP(9), valid_to TIMESTAMP(9),
  is_current BOOLEAN
) USING iceberg PARTITIONED BY (dt);
```

### 2.3 案例:订单 SLA 与漏斗 SQL(教学可直接跑)

```sql
-- 漏斗:各状态转化率(语句为 Flink SQL 风格,Spark 也支持 countIf 与日期函数)
SELECT
  countIf(to_state='create')                             AS create_cnt,
  countIf(to_state='paid')                               AS paid_cnt,
  countIf(to_state='shipped')                            AS ship_cnt,
  paid_cnt/create_cnt                                    AS pay_rate,
  ship_cnt/create_cnt                                    AS ship_rate
FROM dwd_order_events WHERE dt='2026-09-10';

-- SLA:从 create 到 paid 的小时数分布
SELECT round(avg(date_diff('hour', min_if(occurred_at, action='create'),
                                        max_if(occurred_at, action='paid'))),2) AS avg_hours
FROM dwd_order_events WHERE dt='2026-09-10' AND order_id IN (
  SELECT order_id FROM dwd_order_events GROUP BY order_id HAVING countIf(action='paid')>0);

-- 状态机迁移频次(热点路径/回退检测)
SELECT from_state, to_state, count() FROM dwd_order_events GROUP BY 1,2 ORDER BY 3 DESC;
```

> 大数据在"过程类"的价值:**批量算 SLA、漏斗、主链路耗时、误流程(回退/超时)检测**——
> 这类计算天然适合 `Spark/Flink` 批流结合,而不是 OLTP 库硬查。

### 2.4 审计场景(合规)

把"过程"当成**不可变账本**:审计 API 以
`SELECT * FROM dwd_order_events ORDER BY order_id, occurred_at` 提供证据链;
保留 Iceberg 快照使"任何历史时点"都可重放(监管要求)。

---

## 3. 入湖数据的读取(三种读法)

### 3.1 读法一:BI / 报表(JDBC)

- HiveServer2 `jdbc:hive2://bigtop-hostname0...:10000/`(读 Hive 表);
- Spark ThriftServer `jdbc:hive2://bigtop-hostname1...:10016/`(**读 Iceberg,推荐报表用**);
- 规范:报表 SQL 只查 `ads_*` 结果表,不查 ODS(避免大扫描 + 口径混乱)。

### 3.2 读法二:业务应用 / 微服务(低时延)

- **结果表 + 增量订阅**:数据侧把 `dws_*` 结果同时写 Kafka(见操作手册 §8.6),应用订阅增量;
- **HBase 点查**:对查询极快且要行级随机读的场景,数据侧把湖表物化到 HBase(`create "ads_ranking","c"` + 流式 put);
- 原则:应用不直查湖上大表,N 服务只读"给它准备的那张结果表"。

### 3.3 读法三:数据科学 / 训练

```python
df = spark.read.format("iceberg").load("iceberg.demo.dwd_order_daily")   # 全表
train = df.filter(df.dt >= '2026-08-01').select("user_id","is_hit","featx","featy")
train.write.mode("overwrite").parquet("/data/exchange/train/20260910")   # 供外部算法
# 版本化样本:写回 Iceberg(表 train_sample_v20260910),算法用快照时间旅行固定训练集
```
- 数据科学要的"快照一致性"恰是 Iceberg 强项:训练集 = 某个 snapshot;
- 大文件列存(parquet)对 DataFrame 读取最友好。

### 3.4 读法四:审计/对账(时间旅行)

```sql
-- 财务数据核对:跨天查"9月9日 23:00 时点的数据长什么样"
SELECT sum(amount) FROM iceberg.demo.dwd_order_daily
  TIMESTAMP AS OF TIMESTAMP '2026-09-09 23:00:00' WHERE dt='2026-09-09';
```

---

## 4. 文件资料入湖(非结构化 / 文档)

### 4.1 分层:对象存档 + 元数据表

- **原始文件**:HDFS `/data/lake/files/<业务>/<date>/xxx.pdf`(二进制,WebHDFS 上传见操作手册 §3.1);
- **元数据表**(Iceberg):路径、大小、md5、业务键、上传人、解析状态;
- **解析文本表**(可选):把 PDF/Office 抽文本 → 走 §6 RAG 知识库。

### 4.2 案例:合同/发票归档入湖

```bash
# 1) 上传原件(WebHDFS 幂等)
curl -s -X PUT "http://bigtop-hostname0.bigtop.apache.org:50070/webhdfs/v1/data/lake/files/contract/2026/09/10/ct_1001.pdf?op=CREATE&user.name=hdfs" --data-binary @ct_1001.pdf
```
```sql
-- 2) 元数据登记(Spark SQL)
INSERT INTO iceberg.demo.meta_files
VALUES ('hdfs://.../contract/2026/09/10/ct_1001.pdf', 204800, 'md5-<...>',
        '2026-09-10', 'finance', 'filled');
-- 3) 定期全量扫描,对账(缺失文件/孤儿文件) —— 类 §7.3 的 remove_orphan 思路
```
> ⚠ 需解析 PDF/Office/图片 OCR 时,可选引入 Apache Tika / PaddleOCR 服务化,把解析结果回写 `meta_files.parse_text`,再喂 RAG(§6)。

---

## 5. AI 过程数据入湖(对话/推理上下文)

### 5.1 为什么 AI 过程数据要进湖

LLM 应用(客服/写作/Agent)每次调用产生一份"过程数据":
prompt、completion、工具调用、token 数、延迟、评分/反馈。它们的价值:
**质量审计 · 成本核算 · 效果评估 · 安全合规 · 数据回流再训练。**

### 5.2 数据模型(直接给 DDL,教学可用)

```sql
CREATE TABLE ai_conversations (            -- 会话头
  conv_id STRING, user_id STRING, app STRING, channel STRING,
  started_at TIMESTAMP(9), ended_at TIMESTAMP(9),
  total_tokens BIGINT, cost_usd DECIMAL(10,6), dt STRING
) USING iceberg PARTITIONED BY (dt);

CREATE TABLE ai_messages (                 -- 消息明细(完整上下文)
  conv_id STRING, turn_no INT, role STRING,  -- user/assistant/tool
  content STRING, tool_name STRING, tool_args STRING, tool_result STRING,
  latency_ms INT, token_in BIGINT, token_out BIGINT,
  model STRING, temperature DOUBLE, dt STRING
) USING iceberg PARTITIONED BY (dt);

CREATE TABLE ai_feedback (                 -- 人工/自动标注
  conv_id STRING, turn_no INT, rater STRING, rating INT,
  verdict STRING,                          -- correct/hallucinated/refused...
  note STRING, dt STRING
) USING iceberg PARTITIONED BY (dt);
```

### 5.3 链路(生产侧 → 湖)

```
LLM 网关(App) → Kafka ai_log_events → Flink SQL(解析/脱敏/补 dt) → Iceberg 上述三张表
```

```sql
CREATE TABLE kafka_ai_log (raw STRING)
  WITH ('connector'='kafka','topic'='ai_log_events',
        'properties.bootstrap.servers'='bigtop-hostname0...:9092',
        'properties.group.id'='ai_lake','format'='raw');
-- INSERT ... SELECT 解析 json → ai_conversations / ai_messages / ai_feedback(同上 §1 模式)
```

### 5.4 直接在湖上做的分析(教学示例)

```sql
-- 成本和模型质量周报(Flink SQL 风格;Spark 有等价函数)
SELECT date_trunc('week', c.started_at) AS wk, c.app,
       sum(c.total_tokens) AS tokens, sum(c.cost_usd) AS cost,
       avg(r.rating) AS avg_rating, countIf(r.verdict='hallucinated') AS hallu
FROM ai_conversations c
LEFT JOIN ai_feedback r ON r.conv_id = c.conv_id
GROUP BY 1, 2;
-- Token 健康度:受理 + 温度 vs 幻觉率相关性(特征表,供算法用)
-- 单会话回溯:某次客服投诉 → 完整抽取该 conv 的上下文证据链
SELECT * FROM ai_messages WHERE conv_id='<投诉会话ID>' ORDER BY turn_no;
```

### 5.5 边界提示

- **脱敏先行**:入湖前在 Flink 侧对手机号/身份证做掩码(或 Vault/HMAC 字段级加密);
- **保留策略**:原文最多保留 N 天,之后只留脱敏+统计(配合 §7.3 生命周期)。

---

## 6. AI × RAG 与大数据结合

### 6.1 RAG 工作流与"湖"的职责

```
①文档/语料 ──> ②清洗/切分(chunk) ──> ③ embedding(向量化) ──> ④向量索引
                                                         ▲
  问题 ──> 检索(chunk) ──> 拼接 prompt ──> LLM ──> 答案              
                                                         └──> ⑤检索/反馈日志回流湖,持续调优
```
大数据平台担纲:**① 知识库湖存储、② 离线批清洗与切分(Spark)、④ 大向量集的管理与并行构建、
⑤ 检索日志/反馈的数据湖分析**;在线检索与 embedding 调用属应用层(可用 Milvus/ES/OpenAI API)。

### 6.2 落地模式 A:批量构建知识库(数据侧为主)

```bash
# ⚠ 需向量库/embedding 服务(外部),本集群聚焦"湖 + 批算"
# 方案:Spark 分布式做"清洗→切分→调 embedding API→写向量文件 parquet"
#   chunk 元数据存 Iceberg(doc_id, chunk_id, text, hash, version, dt)
#   向量文件存 /data/lake/embeddings/<model>/<version>/ (parquet,numpy array 列),交向量库导入
```

```python
# 脚本轮廓(伪码,依赖外部 embedding HTTP 服务)
def embed_batch(df_chunks):
    import requests, numpy as np
    out = []
    for row in df_chunks.collect():
        vec = requests.post("http://embed-svc:8080/v1/embeddings",
                            json={"input": row.text}).json()["data"][0]["embedding"]
        out.append((row.doc_id, row.chunk_id, row.text, bytes(np.asarray(vec, dtype="float32").tobytes())))
    return spark.createDataFrame(out).writeTo("iceberg.demo.rag_chunks_v2").append()
```

### 6.3 落地模式 B:检索 / 反馈日志回流(闭环)

```sql
-- 记录每次"问题→检索出来的 chunk→LLM 引用→用户反馈",回流湖
CREATE TABLE rag_logs (
  query_id STRING, query STRING, doc_ids ARRAY<STRING>,
  answer STRING, rating INT, click_pos INT, ts TIMESTAMP(9), dt STRING
) USING iceberg PARTITIONED BY (dt);
-- 分析:
--   命中率:docs 被引用比例;负样本:低分且引用了 doc_ids 的 query → 提炼难例 → 再训练/调切片
-- 指标 SQL 示例:
SELECT dt, countIf(rating<=1) AS bad_cnt, round(avg(rating),2) AS avg_rating
FROM rag_logs GROUP BY dt ORDER BY dt;
```

### 6.4 范式总结(教学一张图)

| 环节 | 本集群(实测/可做) | 外部组件(⚠) |
|------|------------------|-------------|
| 语料存储/版本 | Iceberg 湖 + 快照 | — |
| 文档解析 | 原始文件 HDFS | Tika / PaddleOCR |
| 切分 + 清洗 | Spark(规则/正则/去重) | — |
| 向量化 | 批量调 embedding API | embedding 服务(本地 bge 或公云) |
| 向量检索 | 向量文件管理 + 元数据 | Milvus / Elasticsearch / FAISS |
| 反馈回流分析 | Iceberg + Spark SQL | — |

---

## 7. AI 训练原始数据与大数据交互

### 7.1 训练数据流水线在大数据侧的四大职责

1. **存**:海量 raw 语料(日志/文档/对白/代码)按天入湖,支持回溯;
2. **清**:去重(MinHash + Spark)、过滤(PII/低质)、切分、打标(Spark/规则/小模型);
3. **版**:每一版训练集 = 一个 Iceberg 快照(可复现可对比);
4. **送**:把选定版本的样本导出 parquet / jsonl 到共享目录,交给训练集群。

### 7.2 案例:a.语料入湖 b.样本版本化 c.评估回流

```sql
-- a) 语料:日志/文档统一入湖(§4 + §1 链路),原始层 raw_corpus
-- b) 训练集版本化:把选中样本"固化"成一个表版本
CREATE TABLE train_set_v1_20260910 USING iceberg AS
SELECT corpus_id, text, label, split
FROM raw_corpus WHERE quality_score > 0.9 AND split='train';
--   版本 = 快照:SELECT * FROM train_set_v1_20260910.snapshots;
-- c) 评估回流:线上评估指标(acc / reward)按版本回写
CREATE TABLE model_eval (model STRING, train_set_version STRING,
  metric STRING, value DOUBLE, eval_date DATE) USING iceberg;
```

```bash
# 导出给训练集群(Spark)
spark-sql --master yarn -e "
  INSERT OVERWRITE DIRECTORY '/data/exchange/train/20260910' USING parquet
  SELECT * FROM iceberg.demo.train_set_v1_20260910;"
hdfs dfs -ls /data/exchange/train/20260910        # 训练侧挂载/消费该目录
```

### 7.3 与训练侧交互的三种接口

| 接口 | 方式 | 适用 |
|------|------|------|
| 文件导出 | Spark 写 parquet/jsonl 到共享 HDFS | 常规训练 |
| 快照直读 | 训练框架直接读 Iceberg(如 Ray/PyTorch 经 pyiceberg ⚠) | 大规模/持续训练 |
| 特征回灌 | 训练产出特征/标签写回湖,供下游 | 排序模型 → 推荐 |

> 核心主张(名师点拨):**数据团队管"版本与元数据",训练团队管"模型与实验"**,
> 中间只隔一层"样本目录 + 版本号"。Iceberg 快照 = 天然的"数据集版本管理"。

---

## 8. 热门行业典型场景

### 8.1 金融:实时反欺诈 / 风控

**痛点**:卡交易/信贷申请秒级决策,欺诈率与拒真率平衡。
**链路**:
```
交易/申请事件 → Kafka event_stream → Flink(窗口聚合 + 特征) ─→ 规则引擎/模型打分 → 决策
                                        └→ 特征/样本入湖(Iceberg)
```
```sql
-- Flink SQL:5 分钟内同设备高频支付统计(特征)
SELECT device_id, count() AS cnt, sum(amount) AS amt, window_start
FROM TABLE(TUMBLE(TABLE tx, DESCRIPTOR(ts), INTERVAL '5' MINUTE))
GROUP BY device_id, window_start HAVING count() >= 5;
```
**湖侧**:历史特征宽表(`feat_user_30d`)+ 违规样本回流(正反例桶),离线重训 GBRT;
**治理**:交易数据主键幂等、审计快照(监管要求的"可回溯"),Ranger 限制读取。

### 8.2 金融:监管报送 / 数据资产入表(政策热点)

- **监管报送**:T+1 生成 `ads_report_xxx` 结果表 + 全程血缘 + 审计快照;数据口径以湖为准;
- **数据资产入表**(财政部《企业数据资源相关会计处理暂行规定》2024 起施行):
  数据资产要**成本归集 + 收益衡量 + 可溯源** → 平台须提供:
  1) 每条数据资产的 `cost`(存储/计算分摊,按表打点);2) `source`(哪条链路产生);
  3) `value`(服务调用/变现次数)。这些都可以在湖上建 `asset_register` 表沉淀。

### 8.3 电商:大促实时大屏 + 实时推荐特征

```
埋点/订单 → Kafka → Flink 实时聚合(GMV/转化漏斗/热销榜) → 大屏 + 结果表
                     └→ 用户实时行为塞 HBase(推荐系统实时特征)
```
```sql
-- GMV 滚动 1 分钟(教学可跑)
SELECT window_end, city, sum(amount) gmv
FROM TABLE(TUMBLE(TABLE orders_stream, DESCRIPTOR(ts), INTERVAL '1' MINUTE))
GROUP BY window_end, city;
```

### 8.4 制造 / 工业 IoT

- 设备传感器(温度/振动/电流)高频上报 → Kafka → 湖(时序分区:dt + device_id);
- 湖侧批算:**运行漂移/MAP 监控、故障班组对比、节拍分析**;
- 示例:单设备均值 +3σ 异常 `spark-sql` 统计,产线异常提前预警。

### 8.5 新能源(光伏/储能/风电)—— 数据平台经典题材

| 场景 | 链路 | 湖侧产出 |
|------|------|---------|
| 发电量预测 | 逆变器/气象 → Kafka → 湖 + 模型 | 预测=特征宽表 + 预测结果表 |
| 储能电池健康(SOH) | BMS 上报 → 湖 | 充放电曲线、衰减曲线(时序) |
| 补贴/绿证申报 | 电表数据 → 批入湖 → 报表 | 申报台账 + 审计证据链 |
| 场站负载均衡 | 并网统计 → 湖 | 调度建议 DWS |

SQL 示例(教学):某光伏电站日发电 vs 理论辐照利用率分析:
```sql
SELECT date_trunc('day', ts) d, station_id, sum(power_wh) gen,
       round(sum(power_wh)/sum(irradiance*eff_area),2) utilization_rate
FROM lake_pv_meter GROUP BY 1,2;
```

### 8.6 车联网 / 出行

- 轨迹(每 10s 一点)入湖 → 湖侧:OD 分析、常驻地识别、危险驾驶聚合;
- 网约车:高峰供给缺口、订单到派单延迟 SLA(过程记录入湖 → §2 漏斗);
- 注意:轨迹是典型大文件 + 地理空间列,建表建议 `dt + city` 分区。

### 8.7 游戏 / 社交

- 留存/漏斗/AB 实验(audience 明细 + 实验表,湖上算 uplift);
- 推荐特征每天回流(用户-物品交互表,Spark 批算);
- 冷启动:行为日志入湖建"跨游戏图特征"(可引 Graph 工具,⚠)。

### 8.8 数据要素 / 数据交易(新兴)

- **确权登记**:每个数据集在湖上 `dataset_register`(件数/时效/质量分/授权方);
- **质量保障**是交易前提:湖上质量检查 = 完整性/一致性/及时性(§7.2 操作手册);
- **沙箱导出**:把安全脱敏版本导出给买方(Watermark=MD5 溯源)。

---

## 9. 入湖设计模式汇总(六套可复用模板)

| 模板 | 适用 | 链路 | 关键设计 |
|------|------|------|---------|
| ① 批贴源 | 日批/小表 | SQL/脚本 → Iceberg | 幂等 + 对账 |
| ② CDC 实时 | 核心业务库 | MySQL CDC → Flink → Iceberg | 主键 upsert + 多路复用 |
| ③ 消息流 | 埋点/日志 | Kafka → Flink → Iceberg | JSON 解析 + dt 分区 + bot 过滤 |
| ④ 文件归档 | 文档/对象 | WebHDFS → HDFS → meta 表 | MD5 + 对账 + 解析回写 |
| ⑤ AI 过程 | LLM 服务 | Kafka → 脱敏 → 三张表 | 证据链 + 标注 + 成本 |
| ⑥ 特征/样本 | 训练/推荐 | 湖 ↔ 训练目录 | 快照版本化 + 评估回流 |

**每条模板的落地 checklist(直接抄 → 改表名即可)**
1. 上游是谁:DB/API/Kafka/文件?用什么采集(CDC jar / 生产者 / WebHDFS);
2. 表结构:主键、`etl_time`、`dt`、source 指纹;
3. 变换:解析/过滤/脱敏写在 Flink 或 Spark 的哪步;
4. 消费:BI (JDBC)/ 应用 (结果表+Kafka) / DS (导出);
5. 治理:质量对账、快照保留、Ranger 授权、成本打点。

---

## 附录 A:组件引入清单(都标注"本集群是否已有")

| 组件 | 用途 | 本集群 | 坐标/说明 |
|------|------|--------|----------|
| flink-connector-mysql-cdc | MySQL 实时入湖 | ⚠ 未装 | org.apache.flink:flink-connector-mysql-cdc:3.2.0 |
| flink-sql-connector-kafka | Flink 接 Kafka | ⚠ 未装 | org.apache.flink:flink-sql-connector-kafka:1.20.1 |
| spark-sql-kafka-0-10 | Spark 流读 Kafka | ⚠ 未装 | org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.6 |
| mysql-connector-j | Spark/JDBC 读写 MySQL | ⚠ 未装 | com.mysql:mysql-connector-j:8.3.0 |
| Apache Tika / PaddleOCR | 文档解析/OCR | ⚠ 未装 | 服务化部署,回写 meta_files |
| Milvus / ES / FAISS | 向量检索 | ⚠ 未装 | RAG 在线检索 |
| (核心) Iceberg 双引擎 | 湖仓底座 | ✅ 已装并用 | Spark 1.6.1 / Flink 1.11.0(勿换,见操作手册 §4.1) |
| Kafka / Flink / Spark / Hive / HBase / Ranger | 平台本体 | ✅ 已装 | — |

## 附录 B:术语表(教学用)

| 术语 | 说明 |
|------|------|
| ODS/DWD/DWS/ADS | 操作贴源 / 明细宽表 / 汇总 / 应用集市 |
| CDC | Change Data Capture,捕捉数据库变更(insert/update/delete) |
| Lambda / Kappa | 批+流双路 / 全量走流的两种实时架构 |
| SCD | 缓慢变化维(SCD2 保留历史版本) |
| RAG | 检索增强生成(文档检索辅助 LLM 作答) |
| Embedding | 文本→向量;向量相似度即语义相似度 |
| 数据资产入表 | 把数据作为无形资产计入会计报表(2024 起国内施行) |
| 湖仓一体 | 数据湖(存一切)+ 数仓(管理/性能)的融合(Iceberg 为载体) |

## 附录 C:推荐阅读/延伸

- Iceberg 官方 spec(快照/Manifest 机制)→ 湖内部原理;
- Flink CDC 官方手册(datastream / flink-sql 两种作业);
- LangChain / LlamaIndex(RAG、Agent)与 pyiceberg(Iceberg Python 生态 ⚠);
- Debezium(独立 CDC 进 Kafka,与 Flink CDC 互为替代);
- 财政部数据资产入表条文 + 各地数据交易所规范(上海数交所/贵阳数交所)。

---

*本文档为教学与方案设计集成资料;所有链路命令与表 DDL 以本集群实测为准,外接组件以作者提供的契约(坐标/接口)对接后再执行。*