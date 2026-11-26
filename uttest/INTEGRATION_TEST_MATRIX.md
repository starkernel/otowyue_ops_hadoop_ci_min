# 集成测试矩阵（INTEGRATION TEST MATRIX）

> 端到端服务链路验证。每个用例含前置、步骤、期望。
> 更新：2026-10-29

## 1. 存储层

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-HDFS-001 | HDFS 写入/读取 | HDFS 启动 | `hdfs dfs -mkdir -p /test && echo hi > /tmp/a && hdfs dfs -put /tmp/a /test/ && hdfs dfs -cat /test/a` | 输出 hi | ⏳ |
| IT-HDFS-002 | 副本与块 | 3 DN | `hdfs fsck /test/a -files -blocks` | 3 副本，无缺失 | ⏳ |
| IT-HDFS-003 | NameNode UI | — | `curl localhost:50070` | 200 | ✅ |
| IT-HDFS-004 | Router 转发 | h3 Router | `hdfs dfs -ls /` 经 Router | 正常 | ⏳ |

## 2. 资源调度

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-YARN-001 | 提交 MapReduce 示例 | YARN 启动 | `yarn jar hadoop-mapreduce-examples.jar pi 2 10` | SUCCEEDED | ⏳ |
| IT-YARN-002 | 队列与容器 | — | `yarn application -list` | 可查询 | ⏳ |
| IT-YARN-003 | Timeline 记录 | — | 作业后 `yarn application -status <appid>` | 有记录 | ⏳ |

## 3. 数据仓库

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-HIVE-001 | HiveServer2 连接 | Hive 启动 | `beeline -u jdbc:hive2://h0:10000 -e "select 1"` | 返回 1 | ⏳ |
| IT-HIVE-002 | 建表写入 | — | `create table t(id int); insert into t values(1); select * from t;` | 返回 1 | ⏳ |
| IT-HIVE-003 | Hive on Tez | Tez | `set hive.execution.engine=tez; select count(*) from t;` | 成功 | ⏳ |
| IT-HIVE-004 | WebHCat | — | `curl -u : -X GET 'http://h0:50111/templeton/v1/status'` | 返回版本 | ⏳ |
| IT-HIVE-005 | Derby 非默认 | — | 检查 `ConnectionURL` | 为 MySQL | ✅ |

## 4. 数据库

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-HBASE-001 | 建表读写 | HBase 启动 | `hbase shell` → `create 't','f'` `put` `get` | 值正确 | ⏳ |
| IT-HBASE-002 | Master/RS 状态 | — | `status` | 1 active master, 1 RS | ⏳ |
| IT-HBASE-003 | ZK 会话稳定 | — | 观察 10 分钟 | 无 Abort | ⏳ |

## 5. 消息

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-KAFKA-001 | 建 topic | Kafka 启动 | `kafka-topics.sh --create --topic t --partitions 1 --replication-factor 1` | 成功 | ⏳ |
| IT-KAFKA-002 | 生产/消费 | — | console producer + consumer | 消息一致 | ⏳ |
| IT-KAFKA-003 | Ranger 插件 | Ranger | 检查插件加载日志 | 无错误 | ⏳ |

## 6. 批处理

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-SPARK-001 | Spark Pi on YARN | YARN | `spark-submit --master yarn --class org.apache.spark.examples.SparkPi ...` | 输出 Pi | ⏳ |
| IT-SPARK-002 | ThriftServer JDBC | Spark Thrift | beeline 连 10016 | 可查询 | ⏳ |
| IT-SPARK-003 | History 记录 | — | 作业后访问 18081 | 可见应用 | ⏳ |

## 7. 流处理

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-FLINK-001 | 提交 WordCount | Flink 启动 | `flink run -c ... examples.jar` | 作业 RUNNING/FINISHED | ⏳ |
| IT-FLINK-002 | TaskManager 注册 | TM 启动 | Flink UI :8081 查看 | 1 TM | ⏳ |
| IT-FLINK-003 | HistoryServer | — | 访问 :8082 | 200 | ⏳ |

## 8. 安全

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-RANGER-001 | Admin 登录 | Ranger 启动 | `curl :6080/login.jsp` | 200 | ✅ |
| IT-RANGER-002 | KMS 健康 | KMS 启动 | `curl :9292/kms` | 200/可认证 | ⏳ |
| IT-RANGER-003 | HDFS 策略生效 | Ranger HDFS 插件 | 授权/拒绝验证 | 符合策略 | ⏳ |

## 9. 协调与搜索

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-ZK-001 | 三节点仲裁 | 3 ZK | `echo ruok | nc h0 2181` | imok | ✅ |
| IT-ZK-002 | 数据一致性 | — | 写后从不同节点读 | 一致 | ⏳ |
| IT-SOLR-001 | Solr 健康 | Infra Solr | `curl :8886/solr/admin/info/system` | 200 | ⏳ |

## 10. 监控

| ID | 用例 | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| IT-AMS-001 | Collector metadata | AMS | `curl :6188/ws/v1/timeline/metrics/metadata` | 200 | ✅ |
| IT-AMS-002 | 4 主机上报 | monitor | 查询 `proc_run` 各主机 | 有数据点 | ✅ |
| IT-AMS-003 | Grafana 登录 | Grafana | `curl :3000/login` | 200 | ✅ |

## 汇总

| 类别 | 用例数 | 已验证 | 待验证 |
|---|---|---|---|
| 存储 | 4 | 1 | 3 |
| 调度 | 3 | 0 | 3 |
| 数据仓库 | 5 | 2 | 3 |
| 数据库 | 3 | 0 | 3 |
| 消息 | 3 | 0 | 3 |
| 批处理 | 3 | 0 | 3 |
| 流处理 | 3 | 0 | 3 |
| 安全 | 3 | 1 | 2 |
| 协调/搜索 | 3 | 1 | 2 |
| 监控 | 3 | 3 | 0 |
| **合计** | **33** | **8** | **25** |
