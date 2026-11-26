# Flink 实时链路需求 —— 平台视角综合答复（v2）

> **答复编号**：HODOOPFORGE-FLINK-REQ-001-RESP-V2  
> **对应需求**：WQ-HODOOPFORGE-FLINK-REQ-001（业务方 2026-11-03 补充版）  
> **答复方**：HodoopForge 大数据平台运维组  
> **答复日期**：2026-11-03  
> **核心目标**：不止"Hlink 作业能跑"，而是确保 **Kafka → Flink → Iceberg → Spark/Hive → 下游** 全链路数据融汇贯通

---

## 一、总体判断

业务方补充的 Q1~Q6 信息质量较高，**但视角集中在"Flink 作业能否提交"**。从大数据底座整体看，这条链路目前存在 **5 个跨引擎断点**，若不解决，Flink 作业即使 `RUNNING`，数据也无法被下游（Spark/Hive/BI）正确消费。

**一句话结论**：Flink 单点可上线，但**数据流尚未贯通**。必须先统一 Catalog 架构、时区与读取链路。

---

## 二、数据融汇贯通的 5 个关键断点（业务方未覆盖）

### 断点 1：元数据架构断裂（最严重）

| 事实 | 实测证据 |
|---|---|
| Spark 使用 **hadoop catalog**，不是 HiveCatalog | `spark-defaults.conf`：`spark.sql.catalog.iceberg.type hadoop` |
| **HMS 中 edulake_* 库全部没有表** | `SHOW TABLES IN edulake_ai/knowledge/learning/meta` 均返回空 |
| Spark 写的表只在 HDFS，未注册 HMS | `/iceberg-warehouse/edulake_ai/ods_llm_inference_log/metadata/*.avro` 存在 |
| **Hive 查询直接失败** | `SELECT * FROM edulake_ai.ods_llm_inference_log` → `Table not found 'ods_llm_inference_log'` |

**与需求 R-03 的矛盾**：需求称"Spark 侧表元数据存于 Hive Metastore"——**这是错误的**。
Spark 是 hadoop catalog，HMS 里只有空库，没有表。

**后果**：
- Flink 若直接用 `HiveCatalog`，**看不到**现有 Spark 表 → `INSERT INTO` 失败
- 若 Flink `CREATE TABLE` 同名表，会与现有 HDFS 表冲突或产生"双胞胎表"
- 下游 Hive/BI 依然读不到

### 断点 2：Hive 读取链路断裂

| 事实 | 证据 |
|---|---|
| 集群 Hive 4.0.1 **无 Iceberg runtime** | `/usr/bigtop/current/hive-client/lib/` 无 iceberg-* |
| Spark 只有 `iceberg-spark-runtime` | 无 `iceberg-hive-runtime` |

**后果**：即使把表注册进 HMS，**Hive 也读不了 Iceberg 表**。若业务期望"Hive/BI 直接查 ODS"，需要额外部署 Hive Iceberg 集成（`iceberg-hive-runtime` + Hive auxlib），或用 Spark ThriftServer 作为统一 SQL 入口。

### 断点 3：时区不一致（会产生错分区）

| 组件 | 当前时区 |
|---|---|
| 操作系统 / Flink | **UTC**（无 `table.local-time-zone` 配置） |
| Spark | **UTC**（`spark-defaults.conf` 无时区配置） |
| 需求要求 | Flink 改 `Asia/Shanghai` |

**后果**：若只改 Flink 为 Asia/Shanghai，而 Spark 仍 UTC，则同一时刻的数据：
- Flink 写入 `dt=2026-11-03`
- Spark 批处理按 UTC 读 `dt=2026-11-02`
→ **跨引擎分区错位，数据对不上**。

**必须统一**：要么全部 `Asia/Shanghai`，要么全部 UTC（查询层转换）。

### 断点 4：版本口径仍错误

| 项 | 需求文档（含更新版） | 实测 |
|---|---|---|
| Iceberg | **1.6.1** | **1.11.0**（Flink `iceberg-flink-runtime-1.20-1.11.0.jar`，Spark `iceberg-spark-runtime-3.5_2.12-1.11.0.jar`） |

两端已对齐在 1.11.0。**若按 1.6.1 安装会与 Spark 1.11.0 元数据不兼容**（Iceberg 格式版本/属性差异）。需求 R-02、第四章仍写 1.6.1，需更正。

### 断点 5：交付物缺失

| 业务方声称 | 实测 |
|---|---|
| `datalake/pipelines/phase2_flink_jobs.sql` | 仓库中**不存在** |
| `doc/function/attachments/phase2_flink_jobs.sql` | **不存在** |
| `ods_realtime_tables.sql` | **不存在** |
| `kafka_to_iceberg_bridge.py` | 仓库中**不存在**（在 192.168.0.168 上） |

**结论**：SQL 与表结构仍需业务方实际提供，当前无法审阅其正确性。

---

## 三、端到端数据流架构建议

```
业务应用（EduLake，192.168.0.168）
   │  写入
   ▼
Kafka: ai_inference_log / rag_query_log（3 分区, RF=1, lz4）
   │  消费（Exactly-Once）
   ▼
Flink 1.20.1（Standalone, 2 TM）
   │  写 ODS（Flink 负责）
   ▼
Iceberg ODS: /iceberg-warehouse/edulake_ai/ods_llm_inference_log
             /iceberg-warehouse/edulake_knowledge/ods_rag_query_log
   │  ★ 统一 Catalog（HiveCatalog + HMS 注册）
   ▼
Spark（批处理，写 DWD/DWS/ADS）
   │
   ├──► Spark ThriftServer（JDBC/BI）
   └──► Hive（需补 iceberg runtime，可选）
```

### 分层职责边界（建议明确）

| 层 | 写入方 | 读取方 | Catalog |
|---|---|---|---|
| ODS | **Flink**（流式） | Spark / Hive | HiveCatalog |
| DWD/DWS/ADS | **Spark**（批处理） | BI / Spark | HiveCatalog |
| 元数据 | HMS | 全部引擎 | — |

> 原则：**同一张表只有一个写入引擎**。Flink 只写 ODS，Spark 只写下游层，避免并发写冲突。

---

## 四、Catalog 统一方案（三选一，推荐方案 A）

### 方案 A：全部迁移到 HiveCatalog（推荐）

**步骤**：
1. Spark 增加 `iceberg-hive-runtime`（或改用 `SparkCatalog` + HMS）
2. 用 Iceberg `register_table` 把现有 hadoop catalog 表注册到 HMS：
   ```sql
   -- Spark 中执行
   CALL iceberg.system.register_table(
     table => 'edulake_ai.ods_llm_inference_log',
     metadata_file => '<HDFS 上最新 metadata.json 路径>'
   );
   ```
3. Flink 使用 HiveCatalog（需求 R-03 的配置即可）
4. 验证 Spark/Hive/Flink 三端都能看到同一张表

**优点**：统一元数据、支持多引擎并发锁、下游 Hive/BI 可发现表
**代价**：需要一次性迁移现有表（表很小，风险低）

### 方案 B：Flink 也用 hadoop catalog

**配置**：`catalog-type=hadoop`，warehouse 相同
**优点**：与 Spark 现状一致，零迁移
**缺点**：hadoop catalog **无分布式锁**，Flink 流写 + Spark 批读/写并发时有冲突风险；Hive 仍读不到

### 方案 C：双写过渡

Flink 同时写新 HiveCatalog 表与旧表，验证后再切换。**不推荐**（复杂、易重复）。

> **平台建议**：采用 **方案 A**。当前表数据量极小（ODS 仅 7 行），迁移成本最低，且能一次性解决 Hive/BI 读取和多引擎并发问题。

---

## 五、逐项技术核验结果（更新版）

| 项 | 需求/业务方说法 | 实测 | 结论 |
|---|---|---|---|
| Iceberg 版本 | 1.6.1 | **1.11.0**（Flink/Spark 对齐） | ❌ 更正为 1.11.0 |
| Kafka connector | 1.20.1 | `3.4.0-1.20`（已装） | ✅ 可用 |
| Hive connector | 3.1.3（EduLake 不需要） | 已装 `flink-sql-connector-hive-3.1.3` | ✅ 按业务方口径，EduLake 不依赖 |
| **RocksDB state backend** | 要求 `state.backend=rocksdb` | `flink-dist` 内置 `RocksDBStateBackend` + `librocksdbjni-linux64.so` | ✅ **可用**（无需额外 JAR） |
| TM 资源 | 2×2 slots×2GB | 2×1 slot×1GB，均在 h2 | ⚠️ 需扩容 |
| `taskmanager.host` | 称已移除 | 仍硬编码 h2 | ❌ 需修复 |
| checkpoint 目录 | `/flink-checkpoints/edulake` | **不存在** | ❌ 需创建 |
| Flink 时区 | 需 Asia/Shanghai | UTC | ❌ 需配置（且需与 Spark 统一） |
| Spark catalog | 称在 HMS | **hadoop catalog，HMS 无表** | ❌ 核心断点 |
| Hive 读 Iceberg | 未提及 | **无 iceberg runtime，读不了** | ❌ 断点 |
| HDFS 写权限 | — | flink 属 hadoop 组，对 `/iceberg-warehouse` **可写** | ✅ 无权限问题 |
| 业务主机 192.168.0.168 | bridge 运行于此 | ping 通，SSH 22 不可连 | ⚠️ 平台侧 NAT 已配置（见下），仅需确认业务出站 |
| **平台侧 NAT 转发** | 192.168.0.168 → 192.168.0.60 | 脚本 V2.6 已定义 `9092/9083/8020`；**实测从容器访问 `192.168.0.60:9092/9083/8020` 全部成功** | ✅ **平台已完成，非业务方确认项** |
| Kafka 访问 | 192.168.0.60:9092 | 容器内 localhost 超时，须用 FQDN | ⚠️ 作业配置须用 FQDN |
| `edulake_dlq` | 建议新增 | 不存在 | ⏳ 待建 |
| Prometheus | 要求接入 | 未部署 | ⏳ 待建 |

---

## 六、实施步骤（按数据流贯通排序）

| 阶段 | 内容 | 预计 | 负责 |
|---|---|---|---|
| ⓪ NAT 与网络 | 确认 `hodoopforge-nat.service` 已 start（当前 enabled 但 inactive）；复核 9092/9083/8020 DNAT | 10 min | 平台 |
| ① 统一时区 | Spark + Flink 均设 `Asia/Shanghai`（或均 UTC）；验证 `dt` 一致 | 20 min | 平台 |
| ② Catalog 迁移 | 用 `register_table` 把现有 edulake 表注册到 HMS；Spark 切 HiveCatalog | 1 h | 平台 |
| ③ Flink 资源 | TM 扩至 2×2 slots×2GB，分散 h1/h2；修复 `taskmanager.host`；建 checkpoint 目录 | 30 min | 平台 |
| ④ Hive 读取（可选） | 部署 `iceberg-hive-runtime`，或确认以 Spark ThriftServer 为统一入口 | 1-2 h | 平台 |
| ⑤ 作业联调 | 业务方提供 SQL；测试表验证 30 min（含幂等/重复消费） | 1 h | 双方 |
| ⑥ 切换 | 停 bridge → 观察 ODS 增长与去重 → 保留回滚 | 30 min | 双方 |
| ⑦ 观测（P1） | Prometheus + Grafana + lag/DLQ 告警 + 小文件治理 | 1-2 天 | 平台 |

---

## 七、需要业务方进一步确认（新增）

1. **下游查询入口**：ODS 是给 Spark SQL 用，还是也需要 Hive/BI 直接查？决定是否部署 Hive Iceberg runtime。
2. **Catalog 方案**：是否同意方案 A（统一 HiveCatalog + 注册现有表）？这是数据贯通的前提。
3. **时区口径**：统一 `Asia/Shanghai` 还是 `UTC`？（需与现有 Spark 任务对齐）
4. **实际 SQL 文件**：请提供 `phase2_flink_jobs.sql` 与 `ods_realtime_tables.sql` 实体文件。
5. **~~bridge 网络放通~~（平台自查项，已确认）**：`9092/9083/8020` 已由平台 NAT 脚本 V2.6 配置并实测生效，**无需业务方确认**；业务方仅需确认 192.168.0.168 **出站**策略未被自身防火墙拦截（SSH 22 不通属正常，不影响 Flink 数据流）。
6. **ODS 表归属**：现有 ODS 表 owner 为 `spark`，Flink 写入后是否需要统一 owner/权限策略（Ranger）？
7. **并发写约束**：确认 DWD/DWS/ADS 仅由 Spark 写，不参与 Flink 写入。

---

## 八、风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| Catalog 不统一 | Flink 写入的表下游看不到，数据流断裂 | 方案 A 迁移 |
| 时区不一致 | dt 分区错位，跨引擎数据对不上 | 统一时区 |
| Hive 无 Iceberg runtime | Hive/BI 无法查询 | 补 runtime 或统一走 Spark |
| hadoop catalog 无锁 | 并发写冲突 | 切 HiveCatalog |
| TM 单节点（h2） | 节点故障作业全停 | 分散 TM |
| Kafka RF=1 | broker 故障丢消息 | 生产建议 RF≥2 |
| 小文件膨胀 | 查询变慢、HDFS 压力 | 定期 rewrite + snapshot 过期 |
| 版本误用 1.6.1 | 与 Spark 1.11.0 不兼容 | 统一 1.11.0 |
| NAT persist 服务 inactive | 宿主机重启后规则可能未自动重建 | 平台 start 一次并验证 |

---

## 九、附：平台侧 NAT 转发说明（针对业务方疑问）

业务方访问 `192.168.0.60:9092/9083/8020` 的链路，由**平台 NAT 脚本**负责，**不属于业务方配置项**：

```
192.168.0.168 ──► 192.168.0.60:9092  (宿主机 PREROUTING DNAT)
                       │
                       ▼
                 172.19.0.2:9092  (bigtop_hostname0 容器)
```

| 端口 | 服务 | 脚本定义（`setup-nat-forward.sh` V2.6） |
|---|---|---|
| 9092 | Kafka Broker | `9092:${H0_IP}:9092` ✅ |
| 9083 | Hive Metastore | `9083:${H0_IP}:9083` ✅ |
| 8020 | HDFS NameNode RPC | `8020:${H0_IP}:8020` ✅ |

**实测验证**：从容器 h3 访问 `192.168.0.60:9092/9083/8020` 全部成功，证明 DNAT 规则生效。

**待平台自查**：`hodoopforge-nat.service` 当前为 `enabled` 但 `inactive`，建议执行一次
`sudo systemctl start hodoopforge-nat`，确保宿主机重启后规则可自动重建。

---

## 九、结论

1. **需求方向正确，业务方补充有价值**，但视角止于"Flink 作业提交"。
2. **真正的数据贯通前提是 Catalog 统一**——当前 Spark 用 hadoop catalog、HMS 无表、Hive 读不到，这是必须优先解决的地基问题。
3. **平台建议**：按第六节 ①→⑦ 推进，先打通"元数据 + 时区 + 资源"，再提交作业。
4. 当前表数据量极小（ODS 7 行），**现在做 Catalog 迁移成本最低**，越晚成本越高。

---

**答复方**：HodoopForge 大数据平台运维组  
**日期**：2026-11-03
