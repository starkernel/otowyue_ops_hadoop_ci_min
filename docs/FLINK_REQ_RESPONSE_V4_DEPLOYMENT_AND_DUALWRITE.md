# Flink 作业上线结果与双写处置（v4）

> **文档属性**：📤 **面向业务方（EduLake）的答复文档**  
> **平台内部运维细节**（脚本、告警、巡检、故障恢复）见 `docs/FLINK_OPS_RUNBOOK.md`  
> **编号**：HODOOPFORGE-FLINK-REQ-001-RESP-V4  
> **日期**：2026-11-03  
> **结论**：**Flink 两作业已成功上线并稳定运行**；bridge 已由业务方停止，双写已消除，历史重复数据已清洗，幂等性验证通过。**数据链路已完全贯通（单写者）。**
>
> **最终更新（2026-11-03 21:40）**：bridge 已停、去重完成、新消息 45 秒内自动同步且仅 1 行。

---

## 一、上线结果

### 1.1 作业状态

| 作业 | Job ID | 状态 | 拓扑 |
|---|---|---|---|
| LLM 推理 | `f37bed156af3465b0b5b935172f3435e` | **RUNNING** | kafka_ai_inference_src → IcebergSink edulake_ai.ods_llm_inference_log |
| RAG 检索 | `9c6fd7f3ac2d666a1f3b57fba00463a0` | **RUNNING** | kafka_rag_query_src → IcebergSink edulake_knowledge.ods_rag_query_log |

### 1.2 Checkpoint

| 作业 | 完成 | 失败 | 恢复 | 间隔 |
|---|---|---|---|---|
| LLM | 6+ | 0 | 0 | 60s |
| RAG | 5+ | 0 | 0 | 60s |

### 1.3 数据写入验证

- `log_id` 格式正确：`ai_<partition>_<offset>`（如 `ai_1_2`、`ai_2_1`）
- `query_id` 格式正确：`rag_<partition>_<offset>`
- `dt` 与 `request_at` 一致（Asia/Shanghai）
- Kafka consumer group lag = 0（`edulake_flink_ai_v3` / `edulake_flink_rag_v3`）

### 1.4 提交过程中修复的问题

| 问题 | 根因 | 修复 |
|---|---|---|
| `ClassNotFoundException: OffsetResetStrategy` | h0 同时存在非 shaded `flink-connector-kafka` 与 shaded `flink-sql-connector-kafka`，类冲突 | 移除非 shaded 版本（`.bak`） |
| `Cannot load user class: KafkaSource` | **TM（h2/h3）的 `/usr/lib/flink/lib/` 没有 Kafka connector** | 从 h0 复制 `flink-sql-connector-kafka-3.4.0-1.20.jar` 到 h2/h3，重启 TM |

> **运维经验**：Flink Standalone 的 `lib/` 必须在 **JM 与所有 TM** 一致；仅 JM 有 connector 会导致 Task 部署失败。

---

## 二、发现的问题：bridge 双写

### 2.1 现象

同一 `log_id` 出现 2 行，例如：

| log_id | etl_time | 来源 |
|---|---|---|
| ai_1_2 | 19:05:52 | **spark**（bridge 经 ThriftServer） |
| ai_1_2 | 19:06:12 | **flink** |

### 2.2 证据

Iceberg `snapshots` 表中 `engine-name` 交替：

| committed_at | engine-name | added-records | job/app |
|---|---|---|---|
| 19:08:33 | **flink** | 1 | flink.job-id=f37bed15... |
| 19:08:27 | **spark** | 1 | app-name=Thrift JDBC/ODBC Server |
| 19:06:33 | **flink** | 1 | flink.job-id=f37bed15... |
| 19:06:24 | **spark** | 1 | app-name=Thrift JDBC/ODBC Server |

### 2.3 bridge 仍在运行

```
GROUP: edulake_bridge_ai_inference_log
CONSUMER-ID: kafka-python-2.2.3-...
HOST: /192.168.0.168
```

bridge 与 Flink 使用**相同的逻辑主键规则**（`ai_<partition>_<offset>`），因此两条路径各自写入一行，主键重复。

### 2.4 定性

- **Flink 侧正常**：每次 checkpoint 只提交 1 条（`added-records=1`），无自身重复
- **重复来自 bridge**：与交接文档"必须二选一"的约束完全吻合
- **不是 Exactly-Once 缺陷**

---

## 三、处置：停止 bridge —— ✅ 已完成

**业务方已执行停止操作**（2026-11-03）。验证结果：

```
GROUP: edulake_bridge_ai_inference_log
CONSUMER-ID: -     ← 无活跃成员
OFFSET 不再增长
```

原命令（供记录）：

```bash
# 在 192.168.0.168 上
pkill -f kafka_to_iceberg_bridge
pgrep -af kafka_to_iceberg_bridge || echo "已停止"
```

停止后平台验证：

1. 发送一条测试消息到 `ai_inference_log`
2. 等待 40 秒
3. 查询：同一 `log_id` 应只有 **1 行**，且 `etl_time` 来自 Flink
4. 持续观察 10 分钟，ODS 仅 Flink 增长

### 回滚预案（保留 7 天）

```bash
# 如需回滚：停 Flink 作业 → bridge 组重置到 latest → 启动 bridge
kafka-consumer-groups.sh --bootstrap-server 192.168.0.60:9092 \
  --group edulake_bridge_ai_inference_log --reset-offsets --to-latest --execute
kafka-consumer-groups.sh --bootstrap-server 192.168.0.60:9092 \
  --group edulake_bridge_rag_query_log --reset-offsets --to-latest --execute
```

> 注意：重置后 bridge 会从最新 offset 开始，切换期间 Flink 已写的数据不会重复。

---

## 四、重复数据清理 —— ✅ 已完成

已清理：`ai_1_2`、`ai_1_3`、`rag_0_2` 各 2 行。采用 Iceberg `MERGE WHEN MATCHED THEN DELETE`，每个主键保留最新 `etl_time`（Flink 行）。

清理后：`llm 16 行 / 16 唯一`，`rag 15 行 / 15 唯一`，**零重复**。

已执行的去重 SQL（存档）：

```sql
-- Spark 示例（需业务方确认口径）
-- 1) 确认重复主键
SELECT log_id, count(*) FROM iceberg.edulake_ai.ods_llm_inference_log
GROUP BY log_id HAVING count(*) > 1;

-- 2) 去重（Iceberg 支持 MERGE/DELETE；建议先备份 snapshot）
-- 或：创建清洗后新表 → 原子替换
```

> 平台建议：**先停 bridge，观察 10 分钟无新增重复，再做历史去重**，避免边清边写。

---

## 五、当前完整状态

| 项 | 状态 |
|---|---|
| Flink JM/TM | 2 TM × 2 slots（h2/h3），4 slots |
| Flink 作业 | 2 个 RUNNING |
| checkpoint | 成功，0 失败 |
| Kafka lag | 0 |
| Flink 写入 | ✅ 正确（主键/dt/时区） |
| Spark 读取 | ✅ 一致（hadoop catalog） |
| bridge | ✅ **已停止**（业务方执行） |
| 重复数据 | ✅ 已清洗，零重复 |
| 幂等验证 | ✅ 新消息 45s 内同步且仅 1 行 |

---

## 六、平台建议

1. ✅ bridge 已停止，双写已消除。
2. 停止后观察 10 分钟，确认 ODS 仅 Flink 增长、无新重复。
3. 历史重复数据按业务口径清洗（建议保留 Flink 行）。
4. bridge 消费组 offset 保留 7 天，用于回滚。
5. P1：监控（Prometheus/DLQ）、Ranger 权限收敛、Hive/BI 直连。

---

**平台方**：HodoopForge 大数据平台运维组  
**日期**：2026-11-03
