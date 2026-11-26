# HodoopForge 数据湖操作、数据治理与业务对接手册

> 适用集群:HodoopForge(4 容器 / Hadoop 3.3.6 / Spark 3.5.6 / Flink 1.20.1 / Kafka 3.4.1 / Iceberg 双引擎)
>
> 姊妹文档:
> - `USER-GUIDE.md` —— 部署、安装、服务启停、修复(运维向)
> - `OPERATIONS-GUIDE.md` —— 组件级操作与 REST 速查(运维向)
> - **本文档 —— 数据面:怎么做数、管数、供数、治数(业务/数据向)**

---

## 0. 文档定位与阅读对象

本文档从"**业务数据怎么进来、怎么加工、怎么治理、怎么被其他业务用出去**"四个问题出发,
给出在本集群上可直接落地的操作手册。适合以下场景:

- **教学**:数据接入 → 数据湖建设 → 加工计算 → 数据输出 的完整链路演示;
- **业务对接**:外部系统/数据库/应用通过 Kafka、Spark、Flink、JDBC、WebHDFS 与本集群交换数据;
- **数据治理**:元数据、权限、质量、生命周期、血缘的统一管理办法。

凡**实测过**的命令都会标注出处(HiveServer2/Spark JDBC、Kafka、Spark+Flink 两端 Iceberg 均已实测);
标注 ⚠ 的为**进阶方案**,执行前需先补齐相应组件(见对应章节)。

---

## 1. 集群能力地图

### 1.1 节点角色(实测核实)

| 容器 | 核心角色 | 数据面端点 |
|------|---------|-----------|
| bigtop_hostname0 | NameNode、ResourceManager、Hive Metastore 9083、HiveServer2 10000、HBase Master 16010、**Ranger Admin 6080**、**Kafka 9092**、ZooKeeper 2181、**Flink JobManager 8081/6123**、Spark History 18081、Ambari 8080 | JDBC 入口、湖仓中枢 |
| bigtop_hostname1 | **Spark ThriftServer 10016**、NodeManager、DataNode、Timeline Server、ZooKeeper | Spark JDBC 入口 |
| bigtop_hostname2 | **Flink TaskManager**(1 slot)、NodeManager、DataNode、ZooKeeper | 计算节点 |
| bigtop_hostname3 | NodeManager、DataNode、HBase RegionServer、ZooKeeper | 计算节点 |

> 说明:容器 IP 随启动顺序变化,请始终使用 **FQDN**(`bigtop-hostname0.bigtop.apache.org`)
> 而非 IP;恢复步骤见 USER-GUIDE §9.1。

### 1.2 版本矩阵(数据面关键组件)

| 组件 | 版本 | 说明 |
|------|------|------|
| Hadoop / YARN / HDFS | 3.3.6 | 3 个 NodeManager 在线(hostname1/2/3) |
| Hive | 4.0.1 | Tez 0.10.4 执行引擎,HS2 10000 / Metastore 9083 |
| Spark | 3.5.6 | **JDK8 + Iceberg 1.6.1**(YARN 容器也是 JDK8,勿升 1.7+) |
| Flink | 1.20.1 | **JDK17 + Iceberg flink runtime 1.11.0** |
| Iceberg | Spark 1.6.1 / Flink 1.11.0 | 版本分叉原因见 §4.1 |
| Kafka | 3.4.1 | PLAINTEXT://bigtop-hostname0...:9092,单 broker |
| HBase | 2.6.2 | Master 16010,RS 在 hostname3 |
| Ranger | 2.7.0 | UI 6080;**HDFS/YARN/Hive 三插件已启用** |
| ZooKeeper | 3.8.4 | 2181 |

⚠ 未内置(如需可后装):Sqoop、Trino/Presto、DataHub/Atlas、Debezium、Zeppelin、Livy。
本文档用 Spark/Flink JDBC、mysqldump、CDC 方案补齐这些能力。

### 1.3 数据面目录约定

| 数据 | 位置(HDFS) | 说明 |
|------|-----------|------|
| Hive 受管表仓库 | `/warehouse/tablespace/managed/hive` | Hive4 默认 warehouse,由 metastore.uris 指向 hs2 |
| Iceberg 仓库 | `/iceberg-warehouse` | Hadoop Catalog,`demo` 库在此:`/iceberg-warehouse/demo` |
| 用户目录 | `/user/<user>` | hdfs/hive/spark/flink |
| 临时/交换区 | `/tmp、/data/exchange`(建议自建) | 业务文件落地后再 LOAD |

---

## 2. 数仓与数据湖架构定位(教学视角)

### 2.1 分层模型(建议)

| 层 | 命名前缀 | 内容 | 引擎 |
|----|---------|------|------|
| ODS(操作数据存储) | `ods_*` | 原样贴源,不加工 | Hive/Iceberg 原生落盘 |
| DWD(明细宽表) | `dwd_*` | 清洗、去重、维度补齐、分区规整 | Spark/Flink |
| DWS(汇总宽表) | `dws_*` | 按主题轻度汇总(日/时粒度) | Spark SQL / Hive |
| ADS(应用集市) | `ads_*` | 面向报表/标签,轻表 | Spark SQL |
| 维表/码表 | `dim_*` / `code_*` | 维度、字典 | Hive/MySQL 双写 |

### 2.2 为什么是 "Kafka 当总线、Iceberg 当湖"

- **Kafka**:解耦生产端与消费端,天然削峰、多消费者、可回放 —— 用作业务与湖之间的**统一缓冲**;
- **Iceberg**:ACID、时间旅行、隐式分区演进、跨引擎(Spark/Flink)同读 —— 用作**统一存储层**;
- 推荐拓扑:`业务系统 → Kafka → (Spark/Flink) → Iceberg → (JDBC/报表/Kafka 回吐)`。

### 2.3 命名/字段规范(治理第一件事)

- 库名小写;表名 `层_主题_粒度`(如 `dwd_order_daily`);
- 必须含 `dt`(分区日,`YYYY-MM-DD`)与 `etl_time`(加工时间戳);
- Iceberg 表统一 `PARTITIONED BY (dt)`;

---

## 3. 数据接入(汇数)

### 3.1 HDFS 文件接入

```bash
# 1) CLI 直传(在任一台容器,以 hdfs 用户)
docker exec bigtop_hostname0 bash -c '
  sudo -u hdfs hdfs dfs -mkdir -p /data/exchange/orders
  sudo -u hdfs hdfs dfs -put /tmp/orders_20260910.csv /data/exchange/orders/
  sudo -u hdfs hdfs dfs -ls /data/exchange/orders'

# 2) WebHDFS REST(外部系统免 SSH,只需 HTTP;端口 50070)
curl -s -X PUT \
  "http://bigtop-hostname0.bigtop.apache.org:50070/webhdfs/v1/data/exchange/orders/orders.csv?op=CREATE&user.name=hdfs&overwrite=true" \
  -H "Content-Type: application/octet-stream" --data-binary @orders.csv
curl -s "http://bigtop-hostname0.bigtop.apache.org:50070/webhdfs/v1/data/exchange/orders?op=LISTSTATUS&user.name=hdfs"
```

> 外部系统建议用 WebHDFS(HTTP,可走防火墙,NAT 后加转发即可),不要直开 SSH。

### 3.2 Hive 批量接入(贴源建表)

```bash
docker exec bigtop_hostname0 beeline --silent=true -u "jdbc:hive2://localhost:10000/" -n hive -f - <<'EOF'
-- 外部表指向 HDFS 交换区,不做物理拷贝,便于重跑
CREATE EXTERNAL TABLE IF NOT EXISTS ods_orders (
  order_id BIGINT, user_id BIGINT, amount DECIMAL(12,2), city STRING
) PARTITIONED BY (dt STRING)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE LOCATION '/data/exchange/orders';
ALTER TABLE ods_orders ADD PARTITION (dt='2026-09-10');
-- 也可直接物理拷贝进受管表:
-- CREATE TABLE ods_orders_bak LIKE ods_orders;
-- INSERT INTO ods_orders_bak PARTITION(dt) SELECT * FROM ods_orders;
EOF
```

### 3.3 Kafka 实时接入

```bash
# 生产端(任意容器,验证连通)
docker exec bigtop_hostname0 bash -c '
  /usr/lib/kafka/bin/kafka-topics.sh --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 --create --topic ods_orders_json --partitions 1 --replication-factor 1
  echo "{\"order_id\":1,\"user_id\":11,\"amount\":199.9,\"city\":\"shanghai\"}" | \
    /usr/lib/kafka/bin/kafka-console-producer.sh \
      --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 --topic ods_orders_json'

# 消费端验证
docker exec bigtop_hostname0 bash -c '
  /usr/lib/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
    --topic ods_orders_json --from-beginning --max-messages 3'
```

外部业务侧生产:Kafka 客户端基于 Java/Scala,Kafka 3.4.1 配套 `kafka-clients` 3.4.1;也可用任何语言生态。

### 3.4 HBase 接入(低延迟点查)

```bash
docker exec bigtop_hostname0 bash -c '
  hbase shell <<EOF
create "tx_detail", "c"
put "tx_detail", "20260910_001", "c:order_id", "1"
scan "tx_detail"
EOF'
```

### 3.5 关系型数据库(MySQL)↔ 集群 —— 三条路

MySQL 就部署在 hostname0:3306(root/ambarirootpass;业务库建议新建专用账号)。

**路线一:全量文件搬运(最简单,无需额外组件)**

```bash
docker exec bigtop_hostname0 bash -c '
  mysqldump -u<账号> -p<密码> --databases yourdb --skip-lock-tables \
    --default-character-set=utf8mb4 > /tmp/yourdb.sql'
# ⚠ 使用有对应库读写权限的业务账号(不要用 root);再用 3.1/3.2 的办法落到 HDFS / Hive。适合历史一次性迁移。
```

**路线二:Spark JDBC 全量/增量同步(推荐日常)**

```bash
# 需 mysql-connector-j;落地后置于 /usr/lib/spark/jars/ 或 --jars 引用
docker exec bigtop_hostname0 bash -c '
  curl -sL -o /tmp/mysql-connector-j-8.3.0.jar \
    https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.3.0/mysql-connector-j-8.3.0.jar'
# 提交脚本(python)
cat > /tmp/sync_mysql.py <<'PY'
from pyspark.sql import SparkSession
spark = SparkSession.builder.appName("mysql_sync").config("spark.sql.catalog.iceberg","org.apache.iceberg.spark.SparkCatalog").config("spark.sql.catalog.iceberg.type","hadoop").config("spark.sql.catalog.iceberg.warehouse","hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse").config("spark.sql.extensions","org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions").getOrCreate()
jdbc = {"url":"jdbc:mysql://bigtop-hostname0.bigtop.apache.org:3306/yourdb","user":"hive","password":"hive","driver":"com.mysql.cj.jdbc.Driver"}
# 全量:整表覆盖
spark.read.format("jdbc").options(**jdbc, dbtable="orders").load() \
     .writeTo("iceberg.demo.ods_orders_all").createOrReplace()
# 增量:按 update_time 拉取
spark.read.format("jdbc").options(**jdbc, dbtable="orders",
      predicates=["update_time > \"2026-09-10 00:00:00\""]).load() \
     .writeTo("iceberg.demo.ods_orders_inc").append()
PY
docker exec bigtop_hostname1 bash -c '
  export HADOOP_USER_NAME=hdfs
  spark-submit --master yarn --deploy-mode client --num-executors 1 \
    --executor-memory 1024m --executor-cores 1 \
    --jars /usr/lib/spark/jars/mysql-connector-j-8.3.0.jar /tmp/sync_mysql.py'
```

**路线三:CDC 实时(进阶,见 §8.4)**

---

## 4. Iceberg 数据湖实操(两引擎均实测通过)

### 4.1 Catalog 与版本约定(必读)

| 引擎 | Catalog | 类型 | Runtime jar | JDK |
|------|---------|------|-------------|-----|
| Spark | `iceberg` | hadoop | `iceberg-spark-runtime-3.5_2.12-1.6.1.jar` | **8** |
| Flink | `demoicb`(湖)/ `demohive`(Hive) | hadoop / hive | `iceberg-flink-runtime-1.20-1.11.0.jar` | **17** |

**为什么 Spark 与 Flink 的 Iceberg 版本不一样?**
YARN 容器默认是 JDK8(class 52),Iceberg 1.11 是 JDK17(class 61)编译,
executor 一写就抛 `UnsupportedClassVersionError: SparkWrite$WriterFactory ... up to 52.0`。
因此 Spark 侧必须用 1.6.1(1.7 起要求 JDK11+);Flink 的 JM/TM 进程本身跑在 JDK17,
可以继续用 1.11.0。已按此部署并验证,请勿擅自更换 jar(详见 USER-GUIDE §8.7.1、§11.9)。

### 4.2 Spark 侧读写与表维护

```bash
docker exec bigtop_hostname1 bash -c '
  export HADOOP_USER_NAME=hdfs
  spark-sql --master yarn --deploy-mode client --num-executors 1 \
    --executor-memory 1024m --executor-cores 1 <<EOF
USE iceberg;
CREATE TABLE IF NOT EXISTS demo.users (id INT, name STRING, city STRING, ts TIMESTAMP)
  USING iceberg PARTITIONED BY (days(ts));
INSERT INTO demo.users VALUES
  (1, 'alice', 'beijing',   current_timestamp()),
  (2, 'bob',   'shanghai',  current_timestamp());
MERGE INTO demo.users t USING (SELECT 2 AS id, 'bobby' AS name) s ON t.id = s.id
  WHEN MATCHED THEN UPDATE SET name = s.name;     -- ACID upsert
SELECT * FROM demo.users.snapshots ORDER BY committed_at DESC;  -- 快照
SELECT * FROM demo.users VERSION AS OF <填写snapshot_id>;          -- 时间旅行(上一句查询结果)
CALL iceberg.system.expire_snapshots('demo.users');                -- 回收历史快照
CALL iceberg.system.rewrite_data_files('demo.users');              -- 小文件合并
CALL iceberg.system.remove_orphan_files('demo.users');             -- 清孤儿文件
EOF'
```

### 4.3 Flink 侧读写(HiveCatalog + connector=hive;demoicb 湖)

```bash
# 前置:导出 HADOOP_CLASSPATH,否则 ClassNotFound(Configuration);加 --add-opens(J17)
docker exec -u flink bigtop_hostname0 bash -c '
  export HADOOP_HOME=/usr/bigtop/current/hadoop-client HADOOP_CONF_DIR=/etc/hadoop/conf
  export HADOOP_CLASSPATH=$($HADOOP_HOME/bin/hadoop classpath)
  timeout 300 /usr/lib/flink/bin/sql-client.sh \
    -Dexecution.target=remote -Drest.address=localhost -Drest.port=8081 \
    -Denv.java.opts="--add-opens=java.base/java.lang=ALL-UNNAMED \
       --add-opens=java.base/java.net=ALL-UNNAMED \
       --add-opens=java.base/java.util=ALL-UNNAMED" \
    -f /tmp/flink_test.sql'

# /tmp/flink_test.sql —— Catalog 是会话级,新会话必须重建
SET 'sql-client.execution.result-mode' = 'tableau';
SET 'execution.runtime-mode' = 'batch';
CREATE CATALOG demohive WITH ('type'='hive','hive-conf-dir'='/etc/hive/conf','default-database'='default');
USE CATALOG demohive;
CREATE TABLE flink_hive_t1 (id INT, name STRING, ts TIMESTAMP(9)) WITH ('connector'='hive');
INSERT INTO flink_hive_t1 VALUES (1,'apple',TIMESTAMP '2026-09-10 10:00:00');
SELECT id,name,ts FROM flink_hive_t1;
CREATE CATALOG demoicb WITH ('type'='iceberg','catalog-type'='hadoop',
  'warehouse'='hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse');
USE CATALOG demoicb;
SHOW DATABASES;                                    -- demo(与 Spark 同仓库)
SELECT city, dt, cnt FROM demo.metrics ORDER BY city, dt;  -- 读 Spark 写的数据
```

### 4.4 跨引擎一致性与权限

- Spark 与 Flink 共用 **同一 Hadoop Catalog**(warehouse 相同),库里表互认、无需迁移;
- Iceberg 文件布局:`/iceberg-warehouse/demo/users/metadata/`(快照/manifest)+ `data/`(parquet);
- 目录属主为 `hdfs`,Spark 以 `HADOOP_USER_NAME=hdfs` 提交、Flink 以 `flink` 用户(HDFS 组授权)
  写;跨用户写同一表注意 HDFS 写权限(Ranger 策略见 §7.4)。

---

## 5. 数据计算与加工

### 5.1 Spark(批)

```bash
# spark-sql 交互
docker exec bigtop_hostname1 bash -c 'export HADOOP_USER_NAME=hdfs; spark-sql --master yarn --deploy-mode client --num-executors 1 --executor-memory 1024m --executor-cores 1'

# spark-submit(python,含 Iceberg catalog,免额外配置)
docker exec bigtop_hostname1 bash -c '
  export HADOOP_USER_NAME=hdfs
  spark-submit --master yarn --deploy-mode client --num-executors 1 --executor-memory 1024m --executor-cores 1 /tmp/my_job.py'
```

### 5.2 Spark Structured Streaming → Iceberg(实时入湖)

```bash
# 需先补 spark-sql-kafka(Sqoop 等未内置,离线时下载 jar 放入 /usr/lib/spark/jars)
# curl -sL -o /usr/lib/spark/jars/spark-sql-kafka-0-10_2.12-3.5.6.jar \
#   https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.5.6/spark-sql-kafka-0-10_2.12-3.5.6.jar
cat > /tmp/k2ice.py <<'PY'
from pyspark.sql import SparkSession, functions as F
spark = (SparkSession.builder.appName("kafka2iceberg")
  .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog")
  .config("spark.sql.catalog.iceberg.type", "hadoop")
  .config("spark.sql.catalog.iceberg.warehouse", "hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse")
  .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
  .getOrCreate())
df = (spark.readStream.format("kafka")
  .option("kafka.bootstrap.servers", "bigtop-hostname0.bigtop.apache.org:9092")
  .option("subscribe", "ods_orders_json")
  .option("startingOffsets", "earliest")
  .load()
  .select(F.from_json(F.col("value").cast("string"), "order_id BIGINT, user_id BIGINT, amount DOUBLE, city STRING").alias("v"))
  .select("v.*", F.current_timestamp().alias("etl_time"), F.current_date().alias("dt")))
def write_iceberg(mdf, epoch_id):
    mdf.writeTo("iceberg.demo.ods_orders_json").append()
q = (df.writeStream.outputMode("append").trigger(processingTime="10 seconds")
  .foreachBatch(write_iceberg).option("checkpointLocation", "/tmp/k2ice_cp").start())
q.awaitTermination()
PY
```

### 5.3 Flink(批流一体)

```bash
# 流式跑 Iceberg(与 §4.3 相同脚本,去掉 batch SET 即 streaming)
# 需补齐 Kafka/JDBC connector 才能接外部系统(以 Maven Central 实际坐标为准):
docker exec bigtop_hostname0 bash -c '
  cd /usr/lib/flink/lib
  # 举例(版本须匹配 flink 1.20.x,封装的 fat jar):
  # org/apache/flink/flink-sql-connector-kafka/1.20.1/flink-sql-connector-kafka-1.20.1.jar
  # org/apache/flink/flink-connector-jdbc/3.2.0-1.20/flink-connector-jdbc-3.2.0-1.20.jar
  chown flink:flink *.jar
  # 注意:JM/TM 也从该目录取 jar,放好后必须重启 FLINK 服务才生效'
```

### 5.4 Hive/Tez 查询(轻量/临时分析)

```bash
docker exec bigtop_hostname0 beeline --silent=true -u "jdbc:hive2://localhost:10000/" -n hive \
  -e "SET hive.exec.dynamic.partition=true; SET hive.exec.dynamic.partition.mode=nonstrict; SELECT city, count(*) FROM ods_orders GROUP BY city;"
```

---

## 6. 数据服务与出口(供业务系统使用)

### 6.1 HiveServer2 JDBC(标准 BI 出口)

```
JDBC URL : jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/
驱动     : org.apache.hive.jdbc.HiveDriver(hive-jdbc 4.0.1)
```

```bash
# Beeline 冒烟(集群内)
docker exec bigtop_hostname0 beeline --silent=true -u "jdbc:hive2://localhost:10000/" -n hive -e "SELECT 1"
```

### 6.2 Spark ThriftServer JDBC(Spark SQL 出口,hostname1)

```
JDBC URL : jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/
驱动     : org.apache.hive.jdbc.HiveDriver
```
相同协议,引擎是 Spark —— 适合把 Iceberg 的 SQL 查询以 JDBC 暴露给业务/报表。

### 6.3 HDFS 文件出口(数据/报表文件下沉)

```bash
sudo -u hdfs hdfs dfs -mkdir -p /data/exchange/export
# Spark 落地
spark-sql --master yarn -e "INSERT OVERWRITE DIRECTORY '/data/exchange/export/ads_daily' USING parquet SELECT ..."
# 业务系统拉取:WebHDFS GET
curl -s "http://bigtop-hostname0.bigtop.apache.org:50070/webhdfs/v1/data/exchange/export/ads_daily?op=OPEN&user.name=hdfs" -o ads_daily.parquet
```

### 6.4 Kafka 出口(结果回吐给业务)

```bash
/usr/lib/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --topic dws_daily_sellout --from-beginning
```

### 6.5 权限出口(Ranger)

HDFS/YARN/Hive 三个插件已启用。UI:`http://bigtop-hostname0.bigtop.apache.org:6080`(admin/admin)。
给业务建"只读"服务账号并授权,见 §7.4。

---

## 7. 数据治理

### 7.1 元数据管理

- **Hive 表/分区、权限** → 由 Hive Metastore(9083)统一管;
- **Iceberg 表** → 元数据即文件(Hadoop Catalog:`/iceberg-warehouse/<库>/<表>/metadata/`),
  `v1.metadata.json` 记录 schema 与历史快照 —— 天然可审计、可回放;
- 教学建议:重要宽表用 `spark.sql.catalog.iceberg`(文件 Catalog)供跨引擎互读;
  需要与 Hive 生态(JDBC 审计/分权)深度融合时,可把 Catalog 换成 `type=hive`(HMS 注册),换型前务必先确认版本兼容(Spark 1.6.1 + Hive 3.1 有 `NoSuchFieldError: out` 的坑,见 USER-GUIDE §8.7.1)。

### 7.2 数据质量与对账

```bash
# 1) DDL 约束:主键/非空/检查约束(Iceberg 原生支持,Spark SQL 建表时声明)
CREATE TABLE ... USING iceberg (
  order_id BIGINT NOT NULL CONSTRAINT pk PRIMARY KEY,
  amount DECIMAL(12,2) CHECK (amount > 0)
);

# 2) 每批落库后跑"行数/金额对账"
SELECT count(*), sum(amount) FROM iceberg.demo.dwd_order_daily WHERE dt='2026-09-10';
# 与源 Kafka/MySQL 同口径核对,异常则回看 snapshot: SELECT * FROM ... VERSION AS OF ...

# 3) 空值/重复扫描
SELECT dt, count(*) FROM ... WHERE key IS NULL;
SELECT key, count(*) FROM ... GROUP BY key HAVING count(*) > 1;
```

### 7.3 生命周期与冷热管理

```bash
-- Spark 侧周期维护(建议 crontab 每日凌晨):
CALL iceberg.system.expire_snapshots('demo.users', TIMESTAMP '2026-09-03 00:00:00');
CALL iceberg.system.remove_orphan_files('demo.users');
CALL iceberg.system.rewrite_data_files('demo.users');
-- Flink 等价的 CALL demoicb.system.* 参数为字符串表名
```
- 分区裁剪优先保证 `dt` 在 WHERE 中;
- 冷数据:`hdfs dfs -mv` 到 `/data/cold` 或延长 expire 周期。

### 7.4 安全与权限(Ranger 实际操作)

1. 打开 Ranger UI(`...:6080`),HDFS 服务下新建 Policy:
   - 资源:`/iceberg-warehouse/demo/**`
   - 授权用户:`spark`、`flink`(Read/Write);
   - 业务只读账号(如 `bi_read`):Read / Execute。
2. HDFS 侧最小权限兜底(即使 Ranger 未覆盖到的路径):

```bash
sudo -u hdfs hdfs dfs -chmod -R 750 /iceberg-warehouse
sudo -u hdfs hdfs dfs -setfacl -m user:bi_read:r-x /iceberg-warehouse
```
3. 禁止用 root 跑作业;统一走 `hdfs/hive/spark/flink` + Ranger 授权,保留审计。

### 7.5 血缘与数据字典(未内建 Atlas 时的落地做法)

- **表级字典**:每张表建一句话注释 `COMMENT` + 文档表(仓库根建 `dict.md`,记录事实表/维度/字段口径);
- **字段级**:DDL 必写 `COMMENT`;JBDC `SELECT * FROM ...  LIMIT 1` 抽查;
- **血缘**:以"工程 + 脚本 + 目标表"登记表(`data_lineage.md`:上游→加工作业→下游),配合
  Iceberg 快照时间戳做反查;Kafka 最终一致血缘靠 topic 命名(`ods_* → dwd_* → dws_* → ads_*`)约定;
- **审计**:Ranger Access Audit + HDFS audit 日志 + Iceberg 快照日志,可追溯"谁在何时改了哪张表"。

### 7.6 监控与运维视图

| 视图 | 地址 | 用途 |
|------|------|------|
| Ambari 告警 | hostname0:8080 | 服务级健康/alerts |
| YARN RM | hostname0:8088 | 作业队列、NM、资源 |
| Spark History | hostname0:18081 | 作业诊断 |
| Flink UI | hostname0:8081 | 作业/checkpoint/TM |
| 日志 | /var/log/{hadoop*/hive/spark/flink/kafka/hbase} | 排障 |

---

## 8. 业务对接实战(重点)

### 8.1 对接总览

```
                ┌─────────────────────────────────────────────┐
                │           HodoopForge 数据集群                │
 业务系统(OLTP)──┤  Kafka 9092  ← 生产/消费                     │
    (MySQL 3306)┼  JDBC/HiveServer2 10000  ← 报表/BI           │
     应用/服务 ──┼  JDBC/Spark ThriftServer 10016              │
     文件系统 ───┼  WebHDFS 50070 ← HTTP 上传/下载              │
                │  Ranger 6080 → 授权 → HDFS/YARN/Hive          │
                └───────┬────────────────┬─────────────────────┘
                        │                │
                    Iceberg 湖        Hive 仓
                (/iceberg-warehouse)  (/warehouse/tablespace/managed/hive)
```

### 8.2 业务系统 ↔ JDBC(应用直连,推荐只读)

给业务只读账号 `bi_read`(Ranger 授权,Hive 只读),连接串:

```
jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/;user=bi_read  (Spark 引擎,查 Iceberg)
jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/;user=bi_read  (Hive 引擎)
```
规范:连接池、只读事务、超时 30s;重活一律交给数据侧"生成结果表",业务只读结果表 —— 避免 OLTP 直连湖上大查询。

### 8.3 MySQL ↔ 数据湖的三种温度

| 模式 | 方式 | 适用 |
|------|------|------|
| 全量 | mysqldump → HDFS → Hive/Iceberg(§3.5 路线一) | 初始化、小表 |
| 增量(时间戳) | Spark JDBC 按 `update_time` 拉取(§3.5 路线二) | 每天批同步 |
| 实时(CDC) | MySQL binlog → Debezium → Kafka → Flink → Iceberg | 时效性要求高 |

### 8.4 Kafka 总线方案(Kafka → Flink → Iceberg,全链路示例)

> ⚠ 执行前先按 §5.3 补齐 `flink-sql-connector-kafka-1.20.1.jar` 并重启 FLINK。

```sql
-- flink_sql_kafka2iceberg.sql
SET 'sql-client.execution.result-mode' = 'tableau';
CREATE CATALOG demoicb WITH ('type'='iceberg','catalog-type'='hadoop',
  'warehouse'='hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse');
USE CATALOG demoicb;

CREATE TABLE ods_orders_json_flink (order_id BIGINT, user_id BIGINT, amount DOUBLE, city STRING, dt STRING);  -- 湖表(由 demoicb catalog 决定格式,批模式开发)

-- 流式跑这段(去掉 batch SET):
CREATE TABLE kafka_orders (order_id BIGINT, user_id BIGINT, amount DOUBLE, city STRING)
  WITH ('connector'='kafka',
        'topic'='ods_orders_json',
        'properties.bootstrap.servers'='bigtop-hostname0.bigtop.apache.org:9092',
        'properties.group.id'='flink2iceberg',
        'scan.startup.mode'='earliest-offset',
        'format'='json');

INSERT INTO ods_orders_json_flink
SELECT order_id, user_id, amount, city, DATE_FORMAT(now(),'yyyy-MM-dd') FROM kafka_orders;
-- 作业提交后到 Flink UI(8081)看 RUNNING;两分钟后回查湖表即可见数据
```

要点:
- topic 分区数 ≥ 下游并行度;检查点建议 30s(checkpoint interval);
- 失败重放:重跑 MISSING 窗口时用 Kafka offset(见 `--from-beginning` 或 reset group)或 Iceberg 时间旅行回退。

### 8.5 批流一体教学模式

- **Lambda(简化)**:实时链路(§8.4)与批链路(每天全量重算)并行 → 结果表合并,对账取并集;
- **Kappa(推荐教学)**:全部走 Kafka + 流式作业,小改动即可支持回放(重放 = 重提交 offset);
- 落库都写 Iceberg:既有 ACID 又有时间旅行,回刷用 `CREATE TABLE ... AS SELECT ... VERSION AS OF ...`。

### 8.6 结果回写(数仓结果 → 业务系统)

```sql
-- 回写 Kafka(供业务/准实时订阅)
-- 在 Flink SQL 里建 kafka sink:
CREATE TABLE kafka_dws_out (...)
  WITH ('connector'='kafka','topic'='dws_daily_sellout','properties.bootstrap.servers'='...:9092','format'='json');
INSERT INTO kafka_dws_out SELECT city, sum(amount) FROM demo.dwd_orders GROUP BY city;

-- 回写 MySQL(供应用 CRUD)
-- Spark JDBC(目标库/表在 MySQL 侧预建):
spark.read.table("iceberg.demo.dws_order_summary")
    .write.mode("overwrite").format("jdbc")
    .option("url", "jdbc:mysql://bigtop-hostname0.bigtop.apache.org:3306/bi")
    .option("dbtable", "dws_order_summary")
    .option("user", "hive").option("password", "hive")
    .option("driver", "com.mysql.cj.jdbc.Driver")
    .save()
```

---

## 9. 教学沙箱场景(三个可跑 Demo)

**场景 A — 订单分析(批流一体闭环)**
1. §3.3 造 Kafka topic `ods_orders_json`;
2. §8.4 Flink Kafka→Iceberg 入湖;
3. spark-sql 按城市汇总生成 `dws_order_city`;
4. §6.2 Spark ThriftServer 供 BI 查。

**场景 B — 日志 ETL**
1. WebHDFS 上传 `access.log` 到 `/data/exchange/logs`;
2. Hive 建外部表 + 正则 `serde` 清洗 → 写 Iceberg 明细;
3. §7.3 演示快照过期与小文件合并,并对比前后文件数。

**场景 C — 时间旅行与数据回刷演示**
1. 对 `demo.users` 做 3 次 INSERT/UPDATE;
2. `SELECT snapshot_id, operation FROM demo.users.snapshots` 看版本;
3. `SELECT * FROM demo.users VERSION AS OF <snapshot>` 对比历史,验证回刷流程。

---

## 10. 资源约束与排障速查

| 现象 | 原因与解法 |
|------|-----------|
| Spark 写 Iceberg 报 `UnsupportedClassVersionError ... 61.0 ... 52.0` | 用了 1.7+ jar。Spark 必须 1.6.1(J8),见 §4.1 |
| Flink 建 HiveCatalog 报 `ClassNotFoundException: Configuration` | 未导出 HADOOP_CLASSPATH,见 §4.3 |
| Flink 报 `InaccessibleObjectException: java.net.URI.string` | 缺 `--add-opens`(已固化在 flink-conf,勿手改),见 USER-GUIDE §8.7.1 |
| Flink HiveCatalog 报 `only supports timestamp of precision 9` | timestamp 用 `TIMESTAMP(9)`,见 USER-GUIDE §8.7.1 |
| SELECT 输出为空、结果迟迟不出 | 非交互需 `result-mode='tableau'`;INSERT 是异步作业,先等 commit |
| 作业卡在 "ACCEPTED" 不分配 | 内存不够(宿主机约 28G):缩小 executor:`--num-executors 1 --executor-memory 1024m --executor-cores 1` |
| Flink 无 Kafka/JDBC connector | 按 §5.3 补 jar 并重启 FLINK |
| 容器重启后服务没起来 | 先看 USER-GUIDE §9.1 判定"重启 vs 重建",再按 Ambari 顺序起服务 |

---

## 附录 A:端口速查(容器内)

| 服务 | 端口 | 位置 |
|------|------|------|
| Ambari Web | 8080 | hostname0 |
| NameNode Web/RPC | 50070 / 8020 | hostname0 |
| YARN RM | 8088 | hostname0 |
| WebHDFS REST | 50070 | hostname0 |
| Hive Metastore | 9083 | hostname0 |
| HiveServer2 | 10000 | hostname0 |
| Spark ThriftServer | 10016 | hostname1 |
| Spark History | 18081 | hostname0 |
| Flink JobManager REST / RPC | 8081 / 6123 | hostname0 |
| Kafka | 9092 | hostname0 |
| ZooKeeper | 2181 | hostname0 |
| HBase Master | 16010 | hostname0 |
| Ranger Admin | 6080 | hostname0 |
| MySQL | 3306 | hostname0 |

## 附录 B:常用命令速查

```bash
# 进入容器(宿主机)
docker exec -it bigtop_hostname0 bash
# 冒烟三连
docker exec bigtop_hostname0 beeline --silent=true -u "jdbc:hive2://localhost:10000/" -n hive -e "SELECT 1"
docker exec bigtop_hostname1 bash -c 'echo "SELECT 1" | beeline --silent=true -u "jdbc:hive2://localhost:10016/" -n spark'
docker exec bigtop_hostname0 curl -s http://localhost:8081/overview | python3 -m json.tool | grep -E "taskmanagers|slots-available"
# 一条命令 Spark 冒烟(写+读 Iceberg)
docker exec bigtop_hostname1 bash -c 'export HADOOP_USER_NAME=hdfs; spark-sql --master yarn --deploy-mode client --num-executors 1 --executor-memory 1024m --executor-cores 1 -e "SHOW CATALOGS; SELECT * FROM iceberg.demo.users"'
```

## 附录 C:可选演进清单(后续可按需引入)

| 需求 | 推荐引入 | 说明 |
|------|---------|------|
| 表间血缘/仪表盘 | Apache Atlas / DataHub | 读 HDFS/Hive audit,自动建血缘 |
| 增量同步 MySQL | Debezium(→ Kafka) | 配合 Flink CDC 实现实时同步 |
| 一库多查 Hive/Iceberg/Presto | Trino | 统一 SQL 入口,PDI 直连 |
| Web Notebook 教学 | Zeppelin | 交互式 SQL/Python/Markdown |
| 应用直查湖 | Livy(→ Spark) | REST 提交 Spark Job |

---

*本文档内容均基于当前集群实测;若服务迁移/版本变更,以各绪论章节的"版本约定"与 USER-GUIDE §8.7.1 为准。*