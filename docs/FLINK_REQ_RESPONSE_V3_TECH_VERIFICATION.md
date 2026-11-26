# Flink 数据链路 —— 平台技术验证与方案调整（v3）

> **编号**：HODOOPFORGE-FLINK-REQ-001-RESP-V3  
> **日期**：2026-11-03  
> **背景**：业务方审阅意见（`11-flink-platform-response-review-2026-11-03.md`）接受方案 A（统一 HiveCatalog）。  
> **平台实测结论**：**方案 A 在当前环境技术不可行**，已通过 staging 验证；建议调整为**方案 D（统一 hadoop catalog）**。

---

## 一、核心结论

| 项 | 结论 |
|---|---|
| 方案 A（HiveCatalog） | ❌ **不可行**（Hive 4.0.1 移除所需 Thrift 方法） |
| 方案 D（hadoop catalog 统一） | ✅ **可行**（已实测 Flink 可读写现有表） |
| 数据链路 | ✅ 可贯通（Flink↔Spark 通过共享 warehouse 互见） |
| Hive/BI 直连 | ⏳ P1（业务方确认非本期必需） |

---

## 二、方案 A 不可行的证据链（staging 实测）

### 2.1 环境

| 组件 | 版本 |
|---|---|
| HMS | Hive **4.0.1** |
| Spark | 3.5（内置 Hive client **2.3.9**，`hive-metastore-2.3.9.jar` + `libthrift-0.12.0.jar`） |
| Iceberg | 1.11.0（Spark/Flink 一致） |

### 2.2 实测过程

**① `SHOW DATABASES IN hcat` → 成功**

```
default
edulake_ai
edulake_knowledge
edulake_learning
edulake_meta
edulake_pronunciation
edulake_user
```
说明 `get_all_databases` 可用。

**② `SHOW TABLES IN hcat.edulake_ai` → 失败**

```
java.lang.RuntimeException: Failed to list all tables under namespace edulake_ai
  at org.apache.iceberg.hive.HiveCatalog.listTables(HiveCatalog.java:186)
Caused by: org.apache.thrift.TApplicationException:
  Invalid method name: 'get_table_objects_by_name'
```

**③ `CALL hcat.system.register_table(...)` → 失败**

```
java.lang.RuntimeException: Failed to check table existence of edulake_ai.ods_llm_inference_log
  at org.apache.iceberg.hive.HiveCatalog.tableExists(HiveCatalog.java:455)
```

**④ 静态确认**

- Hive 2.3.9 client 的 `ThriftHiveMetastore` 含 `get_table_objects_by_name`
- **Hive 4.0.1 服务端的 Thrift 接口已不含该方法**

### 2.3 根因

Hive 4.0 对 Metastore Thrift API 做了不兼容变更，移除了 `get_table_objects_by_name`。
Iceberg 1.11 的 `HiveCatalog` 的 `listTables` / `tableExists` / `registerTable` 均依赖该方法。
Spark 3.5 内置 Hive client 2.3.9，无法在不破坏 Spark Hive 集成的前提下升级到 4.0 client。

> **这不是配置问题，是版本协议不兼容。** 换 `uri`、加 `capability` 配置均无法绕过。

---

## 三、替代方案 D 的实测验证（已通过）

### 3.1 Flink 使用 hadoop catalog

```sql
CREATE CATALOG iceberg WITH (
  'type'          = 'iceberg',
  'catalog-type'  = 'hadoop',
  'warehouse'     = 'hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse',
  'hadoop-conf-dir' = '/etc/hadoop/conf'
);
```

### 3.2 实测结果

**`SHOW TABLES IN iceberg.edulake_ai` → 成功**

| table |
|---|
| ads_model_health_report |
| dwd_llm_inference_log |
| dws_llm_performance_daily |
| ods_llm_inference_log |

**`SELECT COUNT(*)` → 7 行；`SELECT * LIMIT 2` → 字段完整**

实测样例：
```
log_id=log_1793683917773, request_at=2026-11-03 13:31:57, dt=2026-11-03
```

### 3.3 为什么 hadoop catalog 能满足 EduLake

| 需求 | hadoop catalog 是否满足 |
|---|---|
| Flink 写 ODS | ✅ 直接写 warehouse 路径 |
| Spark 读 Flink 写的表 | ✅ 同一 warehouse，目录扫描可见 |
| Spark 写 DWD/DWS/ADS，Flink 不写下游 | ✅ 无冲突 |
| 业务查询入口 = Spark ThriftServer | ✅ 保持不变 |
| Hive/BI 直连 | ❌ 不支持（业务方已确认 P1） |
| 多引擎元数据统一 | ❌ 无 HMS 注册（但数据通过路径共享，功能上贯通） |

> **关键**：hadoop catalog 的"元数据"就是 HDFS 上的 `metadata/*.json`，Spark 与 Flink 指向同一 warehouse 即可互见。实测已证明 Flink 能看到 Spark 创建的表并读取数据。

---

## 四、方案调整：A → D

| 项 | 方案 A（HiveCatalog） | 方案 D（hadoop catalog，推荐） |
|---|---|---|
| 元数据 | HMS | HDFS `metadata/` |
| Spark 改动 | 改 catalog 类型 + 重启 ThriftServer | **无** |
| 现有 70 张表迁移 | 需 register_table（**实测失败**） | **无需迁移** |
| Flink 配置 | `catalog-type=hive` | `catalog-type=hadoop` |
| 并发写锁 | HMS 锁 | 无（需约定单写者） |
| Hive/BI | ✅（但缺 runtime） | ❌ |
| 落地风险 | **高（不可行）** | **低（已验证）** |

**平台建议：采用方案 D。** 在"Spark 为唯一查询入口、ODS 仅 Flink 写、下游仅 Spark 写"的约束下，hadoop catalog 完全满足数据贯通要求。

---

## 五、调整后的实施计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| ⓪ NAT | 9092/9083/8020 已通（实测） | ✅ |
| ① checkpoint | `/flink-checkpoints/edulake` 已建（1777） | ✅ |
| ② Catalog | **改为 hadoop catalog**（Flink），Spark 保持不动 | ✅ 已验证 |
| ③ 时区 | Spark + Flink 统一 `Asia/Shanghai` | ⏳ 待执行（需重启） |
| ④ 资源 | TM 扩至 2×2 slots×2GB，分散 h1/h2 | ⏳ 待执行（需重启） |
| ⑤ 作业 | 用 hadoop catalog 的 SQL 提交 | ⏳ 待业务方 SQL |
| ⑥ 切换 | 停 bridge → 观察 → 回滚保留 | ⏳ |
| ⑦ 观测 | Prometheus/DLQ | ⏳ P1 |

### 时区说明

现有 ODS 数据 `request_at=2026-11-03 13:31:57`、`dt=2026-11-03`，而系统 UTC 为 08:xx，**说明历史数据已按 Asia/Shanghai 落盘**。
因此统一为 `Asia/Shanghai` 是正确方向，且不会破坏历史分区。

---

## 六、对业务方审阅意见的逐条回应

| 业务方意见 | 平台回应 |
|---|---|
| 接受方案 A（HiveCatalog） | ❌ **技术不可行**（证据见第二节），改为方案 D |
| Hive runtime 作为 P1 | ✅ 同意，不阻塞 |
| 时区统一 Asia/Shanghai | ✅ 同意，平台执行 |
| 版本 1.11.0 | ✅ 已确认 |
| 交付物在 `ref/FLINK_REQ_ATTACHMENTS/` | ⚠️ 本仓库仍无此目录，请确认同步路径 |
| 61 张表注册 | ❌ 无需注册（方案 D 直接路径可见） |
| Spark ThriftServer 需改 spark-defaults 并重启 | ❌ **无需改动**（方案 D 保持 hadoop catalog） |
| checkpoint 已建 1777 | ✅ 已确认 |
| ODS 仅 Flink 写、下游仅 Spark 写 | ✅ 同意，作为并发约束 |

---

## 七、待业务方确认

1. **是否接受方案 D**（hadoop catalog）？这是当前环境下唯一可行且已验证的方案。
2. 提供 `phase2_flink_jobs.sql` 实际文件（本仓库 `ref/` 不存在）——需将 `catalog-type` 改为 `hadoop`。
3. 确认时区切换窗口（需重启 Spark ThriftServer，约 1-3 分钟）。
4. 确认 TM 扩容窗口（当前无 Flink 作业，可立即执行）。

---

## 八、结论

1. **平台原判断的"Catalog 不统一"成立，但解决方案需调整**：HiveCatalog 在 Hive 4.0.1 上不可用。
2. **hadoop catalog 已实测可行**：Flink 可列出并读取现有 ODS 表，与 Spark 共享 warehouse。
3. **数据链路可以贯通**，前提是采用方案 D + 统一时区 + 单写者约束。
4. 建议业务方**接受方案 D**，平台随后完成时区与 TM 调整，即可进入联调。

---

## 九、平台已完成的实际调整（2026-11-03）

### 9.1 Flink 资源配置

| 项 | 调整前 | 调整后 | 状态 |
|---|---|---|---|
| TM 数量 | 2（均在 h2） | **2（h2 + h3）** | ✅ |
| 每 TM slots | 1 | **2** | ✅ |
| TM 内存 | 1024m | **2048m** | ✅ |
| 总 slots | 2 | **4** | ✅ |
| `taskmanager.host` | 硬编码 h2 | **已移除** | ✅ |

> 注意：Ambari 的 `flink-conf` 中 `content` 为**硬编码模板**，仅改 properties 不生效，必须同时修改 `content` 内对应行。

### 9.2 时区统一

| 组件 | 调整前 | 调整后 | 验证 |
|---|---|---|---|
| Flink | UTC | **Asia/Shanghai** | `flink-conf.yaml` 已渲染 |
| Spark | UTC | **Asia/Shanghai** | `SET spark.sql.session.timeZone` → Asia/Shanghai |

### 9.3 checkpoint

- `/flink-checkpoints/edulake` 已存在，权限 1777 ✅

### 9.4 端到端验证结果（关键）

**① Flink 读取现有 ODS（读取方向）**

```sql
-- Flink SQL (hadoop catalog)
SELECT COUNT(*) FROM iceberg.edulake_ai.ods_llm_inference_log;
-- 结果：7 行
```

**② Flink 写入 → Spark 读取（写入方向）**

```sql
-- Flink 写入
CREATE TABLE iceberg.flink_val.e2e_test (id BIGINT, msg STRING, ts TIMESTAMP);
INSERT INTO iceberg.flink_val.e2e_test VALUES (1, 'flink-e2e-ok', TIMESTAMP '2026-11-03 12:00:00');

-- Spark 读取（ThriftServer 10016）
SELECT * FROM iceberg.flink_val.e2e_test;
-- 结果：1 | flink-e2e-ok | 2026-11-03 12:00:00.0
```

**③ 跨引擎 dt 一致性**

Spark 与 Flink 读取 `dt` 均得到：`2026-10-27(3行) / 2026-10-28(1行) / 2026-11-03(3行)`，**完全一致**。

### 9.5 当前集群状态

| 项 | 值 |
|---|---|
| Flink TM / slots | 2 / **4** |
| Flink 时区 | Asia/Shanghai |
| Spark 时区 | Asia/Shanghai |
| 两端 catalog | hadoop（warehouse 相同） |
| ODS 行数 | 7（未被测试污染，测试表已清理） |

---

## 十、下一步（待业务方）

1. **确认接受方案 D**（hadoop catalog）——当前环境唯一可行且已验证。
2. 提供 `phase2_flink_jobs.sql` 实际文件，并将 `catalog-type` 改为 `hadoop`。
3. 平台按该 SQL 提交两个作业并观察 checkpoint。
4. 切换 bridge（停 → 观察 → 保留回滚 7 天）。

---

**平台方**：HodoopForge 大数据平台运维组  
**日期**：2026-11-03
