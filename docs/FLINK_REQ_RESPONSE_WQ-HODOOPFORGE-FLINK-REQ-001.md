# 关于《HodoopForge Flink 实时链路需求清单》的答复

> **答复编号**：HODOOPFORGE-FLINK-REQ-001-RESP  
> **对应需求**：WQ-HODOOPFORGE-FLINK-REQ-001 v1.0（2026-11-03）  
> **答复方**：HodoopForge 大数据平台运维组  
> **答复日期**：2026-11-03  
> **核实环境**：qixuandata 集群（Ambari 3.1.0 / BIGTOP 3.5.0，192.168.0.60）

---

## 一、总体结论

1. **需求方向正确**：以 Flink 原生流式作业替换 Python 微批桥接、实现 Kafka→Iceberg 的 Exactly-Once 接入，是合理且必要的演进。
2. **但需求文档中多处"集群现状"与实测不一致**，若按文档中的版本/资源直接实施会产生兼容性问题。**请以本答复第二节的实测结果为准**。
3. **当前集群尚不具备直接上线条件**，主要缺口：
   - TaskManager 资源不足（每 TM 仅 1 slot / 1GB，且两个 TM 都在 h2 单节点）
   - `/flink-checkpoints` 目录未创建
   - Flink 时区未配置（UTC）
   - 作业 SQL 文件（`phase2_flink_jobs.sql`）未在集群/仓库中
4. 建议按第四节"落地步骤"分阶段推进，P0 项完成后再切换流量。

---

## 二、需求 vs 实测 核对表（重点）

| # | 需求文档描述 | 集群实测（2026-11-03） | 结论/调整建议 |
|---|---|---|---|
| 1 | Iceberg **1.6.1**（Flink/Spark 对齐） | Flink：`iceberg-flink-runtime-1.20-1.11.0.jar`；Spark：`iceberg-spark-runtime-3.5_2.12-1.11.0.jar` | ❌ **版本应为 1.11.0**，两端已对齐；按 1.6.1 安装会与 Spark 不兼容 |
| 2 | `flink-sql-connector-kafka-1.20.1.jar` | 已装 `flink-sql-connector-kafka-3.4.0-1.20.jar`、`flink-connector-kafka-3.4.0-1.20.jar` | ✅ **无需重装**，命名不同但可用 |
| 3 | `flink-connector-hive_2.12-1.20.1.jar` | 已装 `flink-sql-connector-hive-3.1.3_2.12-1.20.1.jar` | ⚠️ 实际为 **Hive 3.1.3 connector**；集群 Hive 为 **4.0.1**，存在兼容性风险，需联调验证 |
| 4 | `flink-shaded-hadoop-3-uber-*.jar`（如未内置） | `/usr/lib/flink/lib/` **无** shaded-hadoop | ⚠️ 需确认 HDFS 访问方式（Iceberg runtime 已含部分 Hadoop 依赖；实测 HDFS 可访问） |
| 5 | TM：2 个，每个 ≥2 slots、内存 ≥2GB | **2 个 TM，均 1 slot、`taskmanager.memory.process.size=1024m`**，均在 **h2** | ⚠️ 资源不满足需求自述；需扩容（建议 2 TM × 2 slots × 2GB，并分散到不同节点） |
| 6 | `taskmanager.host` 硬编码已移除 | `flink-conf.yaml` 中仍为 **`taskmanager.host: bigtop-hostname2.bigtop.apache.org`** | ❌ **仍硬编码**，需改为动态/按节点配置 |
| 7 | Kafka `192.168.0.60:9092` | broker `advertised.listeners=bigtop-hostname0.bigtop.apache.org:9092`；容器内用 `localhost:9092` 查询**超时** | ⚠️ **Flink 作业在容器内应使用 FQDN** `bigtop-hostname0.bigtop.apache.org:9092`，勿用 localhost |
| 8 | topic 建议 6 分区 | `ai_inference_log` / `rag_query_log` / `learning_events` 均为 **3 分区**，RF=1 | ⚠️ 可按需扩至 6 分区（需评估重分区成本） |
| 9 | checkpoint `/flink-checkpoints/edulake` | **目录不存在** | ❌ 需创建并授权 |
| 10 | 时区需改 `Asia/Shanghai` | 系统 UTC，Flink **无时区配置** | ❌ 需配置 `table.local-time-zone: Asia/Shanghai` |
| 11 | 当前实时链路仍由 Python bridge 承担 | `kafka_to_iceberg_bridge` **未运行**（进程不存在） | ⚠️ 需确认 bridge 实际状态（可能已停/崩溃） |
| 12 | 建议新增 `edulake_dlq` | topic **不存在** | ⏳ 待创建（P1） |
| 13 | Kafka topic 已有真实消息 | `ai_inference_log`、`rag_query_log`、`learning_events` 均存在；消费组 `edulake_bridge_*` 存在 | ✅ 正确 |
| 14 | Hive Metastore 4.0.1 | Hive **4.0.1**，HMS 9083 可连 | ✅ 正确 |
| 15 | Iceberg warehouse 与 Spark 共用 | `/iceberg-warehouse` 存在，含 `edulake_ai/knowledge/learning/meta/governance/models/pronunciation/user` 等 | ✅ 正确（库数量比需求列出的更多） |
| 16 | 安全：Kerberos / Ranger | **非 Kerberos**（无 keytab）；**Ranger 已启用（STARTED）** | ✅ 需求"若启用 Kerberos"分支不适用；Ranger 授权需配置 |
| 17 | 作业 SQL `datalake/pipelines/phase2_flink_jobs.sql` | 集群 `/tmp` 与代码仓库中均**未找到** | ❌ 需业务方提供文件 |
| 18 | Python bridge 文件 `datalake/pipelines/kafka_to_iceberg_bridge.py` | 仓库中**未找到** | ⚠️ 需确认文件位置 |

---

## 三、逐条回应（P0）

### R-01 启动 TaskManager 并确认资源 —— **部分完成**

- ✅ 已启动 2 个 TM，`/overview` 返回 `taskmanagers=2, slots-total=2, slots-available=2`。
- ⚠️ 但资源**未达需求自述标准**：每 TM 仅 **1 slot / 1GB**，且两个 TM 都在 **h2**。
- **建议**：扩容为 `2 TM × 2 slots × 2GB`，并至少分散到 h1/h2 两个节点，避免单节点故障导致作业全停。此调整需修改 `flink-conf.yaml` 并重启 TM，约需 10 分钟。

### R-02 安装连接器 JAR —— **需按实测版本调整，不要按文档版本安装**

当前 `/usr/lib/flink/lib/` 已具备：

| 需求 JAR | 实测已装 | 处理 |
|---|---|---|
| `flink-sql-connector-kafka-1.20.1` | `flink-sql-connector-kafka-3.4.0-1.20.jar` | ✅ 无需安装 |
| `iceberg-flink-runtime-1.20-1.6.1` | `iceberg-flink-runtime-1.20-1.11.0.jar` | ✅ 使用 **1.11.0**，与 Spark 对齐 |
| `flink-connector-hive_2.12-1.20.1` | `flink-sql-connector-hive-3.1.3_2.12-1.20.1.jar` | ⚠️ 沿用 3.1.3 connector，需验证 Hive 4.0.1 兼容 |
| Hive 依赖 | 已随上方 Hive connector 提供 | 需联调确认 |
| `flink-shaded-hadoop-3-uber` | 未装 | ⚠️ 先验证 HDFS 读写；若失败再补 |

> **重要**：JM 与 TM 必须在**同一镜像/同一 JAR 版本**。当前 TM 在 h2，需确认 h2 的 `/usr/lib/flink/lib/` 与 h0 一致。

### R-03 使用 HiveCatalog —— **方案正确，需联调**

- 配置写法正确（`catalog-type=hive` + HMS URI + warehouse）。
- ⚠️ **风险点**：Flink 的 Hive connector 为 **3.1.3**，而集群 Hive 为 **4.0.1**。官方兼容矩阵中 Hive 4.x 支持有限，可能出现 `NoSuchMethod`/序列化差异。建议先做连通性验证：
  ```sql
  CREATE CATALOG iceberg WITH (...);
  SHOW DATABASES;  -- 期望看到 edulake_ai/knowledge/learning/meta/governance/models/pronunciation/user
  ```

### R-04 准备 checkpoint / state 目录 —— **未完成**

- `/flink-checkpoints` **不存在**。需执行：
  ```bash
  hdfs dfs -mkdir -p /flink-checkpoints/edulake
  hdfs dfs -chown flink:hadoop /flink-checkpoints/edulake
  hdfs dfs -chmod 775 /flink-checkpoints/edulake
  ```
- SQL 中 `state.checkpoints.dir = hdfs:///flink-checkpoints/edulake` 需与实际路径一致（注意 `hdfs:///` 使用默认 FS）。

### R-05 提交两个实时作业 —— **待业务方提供 SQL**

- 集群中未找到 `phase2_flink_jobs.sql`，仓库中也没有。
- 需求中的关键约束合理：
  - `log_id/query_id` 用 partition+offset 生成 → 幂等 ✅
  - `scan.startup.mode=group-offsets` ✅
  - consumer group `edulake_flink_ai_v3` / `edulake_flink_rag_v3` 与现有 `edulake_bridge_*` **不冲突** ✅
  - ⚠️ 时区需显式设置（当前 UTC）
- **建议**：提交前先在测试表验证 30 分钟，再切生产表。

### R-06 停用 Python bridge —— **当前 bridge 已不在运行**

- 实测 `kafka_to_iceberg_bridge` 进程**不存在**，可能已停止或异常退出。
- 因此"二选一"的重复写入风险当前较低，但需确认：
  - bridge 是否会由定时任务/守护进程自动拉起？
  - `edulake_bridge_ai_inference_log` / `edulake_bridge_rag_query_log` 消费组是否还有活跃成员？
- 建议保留脚本与回滚流程，明确"默认停用"。

---

## 四、P1 建议的现状回应

| 编号 | 需求 | 运维回应 |
|---|---|---|
| R-07 | Flink 指标接入 Prometheus | 当前**未部署 Prometheus**。需先选型（pushgateway / exporter），建议纳入平台监控统一规划 |
| R-08 | 消费积压告警 | 依赖 R-07；可先用 Kafka `kafka-consumer-groups --describe` 做定时巡检 |
| R-09 | 脏数据死信队列 | `edulake_dlq` 不存在，可按需求创建；当前 `json.ignore-parse-errors=true` 会静默丢弃，建议改为记录 DLQ + 监控差值 |
| R-10 | Kafka topic 规划 | 现有 3 分区 / RF=1 / retention 30 天（learning_events 7 天）。扩至 6 分区可行，需评估重分区与顺序性影响；RF=1 无副本冗余，生产建议至少 RF=2（需增加 broker 或接受单点风险） |
| R-11 | Iceberg 小文件治理 | 建议在 Spark 侧配置每日 `rewrite_data_files` 调度；Flink 侧可调 `write.parquet.compression-codec` 与 checkpoint 间隔平衡文件数 |
| R-12 | 高可用 | 当前 Flink 为 **Standalone**，JM 单点、无 HA。建议后续切换 YARN 模式（集群已有 YARN）或配置 JM HA |
| R-13 | 安全 | **非 Kerberos**，无需 keytab。**Ranger 已启用**，需为 Flink 写入的库表配置 HDFS/Hive 策略 |
| R-14 | 监控大盘 | 依赖 R-07；Grafana 已运行（:3000），但数据源/仪表盘未配置 |

---

## 五、运维可提供的信息（回应需求第四章）

| 项 | 运维答复 |
|---|---|
| Flink 提交入口 | `http://192.168.0.60:8081`（实测 HTTP 200 ✅） |
| TaskManager 数量/slots/内存 | **当前 2 × 1 slot × 1GB（均在 h2）**；计划扩容为 2 × 2 slots × 2GB 并分散节点 |
| Kafka bootstrap（容器内） | **`bigtop-hostname0.bigtop.apache.org:9092`**（⚠️ 勿用 localhost，实测超时） |
| HMS URI | `thrift://bigtop-hostname0.bigtop.apache.org:9083`（实测可连 ✅） |
| HDFS checkpoint 路径 | `/flink-checkpoints/edulake`（**待创建**） |
| Iceberg 版本 | **1.11.0**（Flink 与 Spark 已对齐） |
| 是否启用 Kerberos/Ranger | Kerberos：**否**；Ranger：**是（已启用）** |
| 监控接入方式 | Prometheus **未部署**，待选型 |

---

## 六、验收清单调整建议

原验收清单基本合理，建议补充/修正：

- [ ] `/usr/lib/flink/lib/` 在 **JM 与所有 TM 节点**版本一致（重点核对 h2）
- [ ] Iceberg 版本确认为 **1.11.0**（非 1.6.1）
- [ ] Flink SQL `SHOW DATABASES` 可见 `edulake_*` 库（含 governance/models 等）
- [ ] `table.local-time-zone = Asia/Shanghai` 已生效（`dt` 分区正确）
- [ ] `/flink-checkpoints/edulake` 可写，checkpoint 连续 3 次成功
- [ ] 两个作业 `RUNNING`，无重启循环
- [ ] 测试消息 30 秒内可查；重复 offset 不产生重复行
- [ ] 确认 Python bridge **确实停止**且无自动拉起
- [ ] TM 单节点故障演练（当前 2 TM 均在 h2，演练会暴露单点风险）
- [ ] Ranger 策略已授权（若走 Hive 表权限）

---

## 七、建议落地步骤

| 阶段 | 内容 | 预计耗时 | 负责方 |
|---|---|---|---|
| ① 资源与配置 | TM 扩容（2×2 slots×2GB，分散 h1/h2）、修复 `taskmanager.host`、配置时区、创建 checkpoint 目录 | 30 分钟 | 运维 |
| ② 连接器联调 | 验证 Hive connector 3.1.3 + HMS 4.0.1；验证 HDFS 读写；确认 JM/TM JAR 一致 | 1 小时 | 运维 + 业务 |
| ③ 作业测试 | 业务方提供 `phase2_flink_jobs.sql`；在测试表提交，观察 30 分钟 | 1 小时 | 业务 + 运维 |
| ④ 切换 | 停 bridge（确认无自动拉起）→ 切生产表 → 观察 10 分钟 ODS 增长与去重 | 30 分钟 | 双方 |
| ⑤ 监控（P1） | Prometheus 选型与部署、Grafana 大盘、lag 告警 | 1-2 天 | 运维 |

---

## 八、风险提示

1. **Hive 4.0.1 与 Flink Hive connector 3.1.3 的兼容性**是最大不确定项，建议阶段②优先验证。
2. **TM 单节点（h2）**：当前两个 TM 都部署在 h2，h2 故障将导致所有 Flink 作业中断。
3. **Kafka RF=1**：无副本，broker 故障会丢消息；生产环境建议 RF≥2。
4. **局部地址陷阱**：容器内必须用 FQDN 访问 Kafka（`bigtop-hostname0.bigtop.apache.org:9092`），`localhost` 会因 advertised listener 超时。
5. **时区**：不配置会导致 `dt` 分区按 UTC 落盘，与业务"本地日期"预期不符。

---

## 九、需业务方补充/确认的事项

1. 提供 `phase2_flink_jobs.sql`（或确认其内容）。
2. 确认 `kafka_to_iceberg_bridge.py` 的当前位置与当前运行方式（为何进程不存在）。
3. 确认目标 ODS 表结构（`ods_llm_inference_log`、`ods_rag_query_log`）与主键定义。
4. 确认是否接受 Flink Hive connector 3.1.3 与 Hive 4.0.1 的兼容性风险，或需评估升级 connector。
5. 确认 TM 扩容的资源窗口（需重启 Flink，作业短暂中断）。
6. 确认是否需要保留 `edulake_bridge_*` 消费组 offset 以便回滚。

---

**答复方**：HodoopForge 大数据平台运维组  
**日期**：2026-11-03
