# 功能支持矩阵（FEATURE MATRIX）

> 状态枚举：`✅ 已支持` / `🟡 部分支持` / `🔧 手工支持` / `❌ 未支持` / `⏳ 规划中`
> 最后更新：2026-10-29

## 1. 大数据服务功能矩阵

| 服务 | 组件 | 节点分布 | 状态 | 关键端口 | 说明 |
|---|---|---|---|---|---|
| **HDFS** | NameNode | h0 | ✅ | 8020 RPC / 50070 UI | `stack_root=/usr/bigtop` 已修正 |
| | DataNode | h1/h2/h3 | ✅ | 50010 / 50075 | 3 副本 |
| | SecondaryNameNode | h1 | ✅ | 50090 | checkpoint 正常 |
| | Router (Federation) | h3 | ✅ | 20010 RPC / 8111 Admin / 50071 UI | 挂载表为空，HBase 已绕开 |
| **YARN** | ResourceManager | h0 | ✅ | 8088 UI / 8050 RPC | |
| | NodeManager | h1/h2/h3 | ✅ | 8042 | |
| | AppTimelineServer(V1) | h1 | ✅ | 8188 / 10200 | |
| | TimelineReader(V2) | h0 | ✅ | 8198 | 依赖外部 HBase，已通过预置 service-dep 修复 |
| | RegistryDNS | h0 | ✅ | 8670 | jsvc 双进程 |
| **HBase** | Master | h0 | ✅ | 16000 / 16010 | |
| | RegionServer | h3 | ✅ | 16020 / 16030 | |
| **Hive** | HiveServer2 | h0 | ✅ | 10000 / 10002 | 元数据库=**MySQL**（非 Derby） |
| | HiveMetaStore | h0 | ✅ | 9083 | |
| | WebHCat | h0 | ✅ | 50111 | |
| | HCAT | h1/h2/h3 | ✅ | — | 客户端 |
| **Kafka** | Broker | h0 | ✅ | 9092 / 9093 | Ranger Kafka 插件 |
| **Spark** | JobHistoryServer | h0 | ✅ | 18081 | |
| | ThriftServer | h1 | ✅ | 10016 | |
| **Flink** | JobManager | h0 | ✅ | 8081 / 6123 | Standalone Session |
| | TaskManager | h2 | ✅ | 动态 | |
| | HistoryServer | h0 | ✅ | 8082 | |
| **ZooKeeper** | ZK Server | h0/h1/h2 | ✅ | 2181 | 3 节点仲裁 |
| **Ranger** | Admin | h0 | ✅ | 6080 / 6182 | |
| | Usersync | h0 | ✅ | 5151 | |
| | Tagsync | h3 | ✅ | — | 拉取型 |
| **Ranger KMS** | KMS Server | h0 | ✅ | 9292 / 9393 | |
| **Infra Solr** | Solr | h0 | ✅ | 8886 | SolrCloud 单节点 |
| **MapReduce2** | HistoryServer | h0 | ✅ | 19888 / 10020 | |
| **TEZ** | Client | h0-h3 | ✅ | — | 仅客户端（INSTALLED 正常） |

## 2. AMS（手工部署，未纳入 Ambari）

| 能力 | 组件 | 节点 | 状态 | 端口 | 说明 |
|---|---|---|---|---|---|
| 指标采集 | AMS HBase | h0 | 🔧 | ZK 61181 / master 61300 / RS 61320 | 内嵌 HBase |
| 指标汇聚 | Metrics Collector | h0 | 🔧 | 6188 | `metadata` HTTP 200 |
| 主机监控 | Metrics Monitor | h0-h3 | 🔧 | — | python2 + 自编译 psutil |
| 可视化 | Grafana | h0 | 🔧 | 3000 | 数据源/仪表盘未配置 |

## 2.5 Flink 实时链路（EduLake，2026-11-03 上线）

| 能力 | 组件/配置 | 状态 | 说明 |
|---|---|---|---|
| 实时接入 | LLM: ai_inference_log → ods_llm_inference_log | ✅ RUNNING | job f37bed15 |
| 实时接入 | RAG: rag_query_log → ods_rag_query_log | ✅ RUNNING | job 9c6fd7f3 |
| Catalog | hadoop catalog（共享 warehouse） | ✅ | HiveCatalog 因 HMS 4.0.1 不可用 |
| 时区 | Flink/Spark Asia/Shanghai | ✅ | 两端一致 |
| Checkpoint | 60s, EXACTLY_ONCE, RocksDB | ✅ | 持续成功 |
| 幂等 | log_id=ai_<p>_<o> / query_id=rag_<p>_<o> | ✅ | 无重复 |
| 单写者 | ODS 仅 Flink 写；bridge 已停 | ✅ | 双写已消除 |

## 3. 平台能力矩阵

| 能力域 | 能力项 | 状态 | 备注 |
|---|---|---|---|
| 部署 | Ambari 服务部署 | ✅ | blueprints + 手工修复 |
| 部署 | 栈版本管理 | ✅ | BIGTOP 3.2.0/3.3.0 缓存并存 |
| 运维 | 端口 NAT 转发 | ✅ | V2.4，含 systemd 持久化（persist） |
| 运维 | 告警治理 | ✅ | 82 告警全 OK |
| 运维 | 内存调优 | ✅ | 见 sessions/2026-10-29-memory-tuning.md |
| 运维 | 组件自愈/看护 | ⏳ | 建议增加 watchdog（P1） |
| 安全 | Ranger 策略管理 | ✅ | HDFS/Hive/HBase/Kafka 插件 |
| 安全 | Ranger KMS | ✅ | |
| 安全 | Kerberos | ❌ | 当前非安全模式 |
| 多租户 | YARN 队列 | 🟡 | 默认队列 |
| 数据湖 | Iceberg | 🔧 | Flink runtime 已带，未集成 |
| 监控 | AMS 指标 | 🔧 | 手工部署，未纳入 Ambari |
| 监控 | Flink Prometheus reporter | ✅ | 9249，JM/TM 已暴露；Prometheus 已抓取 |
| 运维 | Flink 健康检查脚本 | ✅ | flink-health-check.sh |
| 运维 | Iceberg 小文件治理 | ✅ | iceberg-maintenance.sh |
| 监控 | Grafana 仪表盘 | ✅ | Prometheus-Flink 数据源 + Flink Dashboard |
| 消息 | 死信队列 edulake_dlq | ✅ | 3 分区，retention 7d |
| 高可用 | NameNode HA | ❌ | 单 NN |
| 高可用 | ResourceManager HA | ❌ | 单 RM |
| 高可用 | HBase HA | ❌ | 单 Master |

## 4. 客户端工具矩阵

| 工具 | 节点 | 状态 | 说明 |
|---|---|---|---|
| hadoop / hdfs / yarn | h0-h3 | ✅ | `/usr/bigtop/current/*-client` |
| hbase shell | h0-h3 | ✅ | |
| hive / beeline | h0-h3 | ✅ | |
| spark-submit / spark-sql | h0-h3 | ✅ | |
| flink run | h1/h2/h3 | ✅ | FLINK_CLIENT |
| kafka-topics / console | h0 | ✅ | |

## 5. 已知功能缺口（详见 ROADMAP）

1. AMS 未纳入 Ambari 管理（手工启停），Grafana 数据源/仪表盘未配置。
2. 无组件 watchdog，HBase 因 ZK 会话过期 Abort 后不会自愈。
3. 无 HA（NN/RM/HBase Master 均单点）。
4. 依赖 AMS 的 12 个 HDFS 指标告警当前处于禁用状态（可随 AMS 就绪后重新启用）。
5. Iceberg/Flink SQL 集成尚未端到端验证。
