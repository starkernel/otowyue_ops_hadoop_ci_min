# HDFS NameNode HA 交接单平台侧评审

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


> 历史评审。文中“70 表”为 2026-11-09 窗口范围；最终迁移范围为 **77 表**，并已在 2026-11-19 完成 `-ha` 对齐，见 [`WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md`](WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md)。

> **文档编号**：HODOOPFORGE-HA-HDFS-REVIEW-001  
> **日期**：2026-11-08  
> **对应交接单**：`ambarirpm/37-data-lake-platform-ha-handoff-2026-11-08.md`  
> **结论**：应用侧交接单质量高，配置/迁移/回滚/验收设计基本完整；平台预检通过。**但 30 分钟窗口只能覆盖应用侧切换，平台启用 NN HA + Spark/Hive 配置同步必须前置。**

---

## 〇、窗口变更（2026-11-09 09:30 CST）

> 原建议平台窗口 **2026-11-08 21:00–23:00** 未执行；应用窗口 **2026-11-09 04:00–04:30** 已错过。
> 当前 HDFS HA **仍未启用**，Flink 仍使用旧 JAR/旧仓库；HDFS HEALTHY、Kafka RF3 正常。
>
> **新建议**：平台窗口 **2026-11-09 21:00–23:00 CST**；应用窗口 **2026-11-10 04:00–04:30 CST**。
> 另：2026-11-09 09:30 发现 HBase Master Abort（ZK 连接异常），已重启恢复；当前仅剩 4 条磁盘使用 WARNING。

---

## 〇.1 执行结果（2026-11-09 03:20 CST）

> **HDFS NN HA 已完成并验收通过**：NN1 h0 Active / NN2 h3 Standby，3 JN（h0/h1/h3），2 ZKFC，nameservice `hdfs://qixuandata` 可读写，双向 failover 成功；旧/新仓库路径均可读；Spark/Hive 配置已同步；全服务 STARTED，仅 4 条磁盘 WARNING。
>
> 详细证据与问题处置见 [`HA_PROGRESS_REPORT_2026-11-09_HDFS_HA.md`](HA_PROGRESS_REPORT_2026-11-09_HDFS_HA.md)。

---

## 一、结论先行

| 项 | 结论 |
|---|---|
| 应用侧交接单 | ✅ 覆盖 nameservice、2NN+3JN+ZKFC、70 表双 catalog 重建、回滚、验收 |
| 平台预检 | ✅ HDFS HEALTHY；0 损坏/缺失/欠副本；3 DN；JN 端口空闲；快照已建 |
| 30 分钟窗口 | ⚠️ 仅够应用侧切换；**平台 HA 启用需另排 90–120 分钟** |
| 建议平台窗口 | **2026-11-08 21:00–23:00 CST**（今晚） |
| 应用窗口 | **2026-11-09 04:00–04:30 CST**（保持交接单） |
| 缓冲/回滚 | 2026-11-09 04:30–05:00 |

---

## 二、交接单做得好的地方

1. **目标明确**：2 NN + 3 JN + ZKFC + `hdfs://qixuandata`，自动 failover。
2. **识别了关键约束**：hadoop catalog 不支持 `SET LOCATION` / `RENAME`，旧 metadata 硬编码旧 authority，因此采用 **oldice → newice 双 catalog 重建 70 表**，而不是简单改字符串。
3. **回滚设计完整**：旧表/旧 JAR 保留，迁移不删除旧 catalog，回滚不需要反向搬数据。
4. **责任边界清晰**：平台负责 nameservice/HA/快照/Spark·Hive 配置；应用负责 70 表迁移/新 JAR/探针。
5. **验收具体**：A1–A10 可直接执行。

---

## 三、平台预检结果（2026-11-08）

| 检查项 | 结果 |
|---|---|
| HDFS 健康 | **HEALTHY**；33801 blocks；0 corrupt / 0 missing / 0 under-replicated；平均副本 3.0 |
| DataNode | **3**（h1/h2/h3），全部 Normal |
| JournalNode 端口 8485 | h0/h2/h3 均 **free** |
| NameNode 目录 | `/hadoop/hdfs/namenode` |
| 当前 `fs.defaultFS` | `hdfs://bigtop-hostname0.bigtop.apache.org:8020` |
| `dfs.nameservices` | **空**（未启用 HA） |
| JN / ZKFC 实例 | **0 / 0** |
| Iceberg warehouse 大小 | 实际 **12.5 GB**，含副本 **37.6 GB** |
| HDFS 剩余空间 | **589 GB**（足够 70 表重建） |
| 快照能力 | `/iceberg-warehouse` 已 snapshottable |
| HA 前快照 | ✅ 已创建 `pre_nn_ha_20261109` |
| 旧仓库可读 | ✅ `hdfs://bigtop-hostname0...:8020/iceberg-warehouse` |
| 新 nameservice | ❌ `hdfs://qixuandata` 暂不可解析（待启用） |
| Spark warehouse | 仍为旧 authority（待同步） |
| ZooKeeper | 3 节点（HA 基础已具备） |

---

## 四、对交接单三项请求的确认

### 4.1 `qixuandata` nameservice 生效

**确认**：平台负责。当前未生效，将在平台窗口内完成：

- 2 NN：NN1 h0（现有）、NN2 h1（新增）；
- 3 JN：h0/h2/h3；
- 2 ZKFC：h0/h1；
- nameservice `qixuandata`，自动 failover；
- 预计 **90–120 分钟**（含 HDFS 重启与 failover 演练）。

### 4.2 Spark/Hive 配置同步

**确认**：平台负责，在 NN HA 完成后、应用窗口前完成：

- `spark.sql.catalog.iceberg.warehouse = hdfs://qixuandata/iceberg-warehouse`
- `spark.hadoop.fs.defaultFS = hdfs://qixuandata`
- Hive `fs.defaultFS = hdfs://qixuandata`
- 需重启 Spark ThriftServer / HiveServer2，预计 **5–10 分钟**。
- 同步后，旧 authority 仍可通过 NN1 读取（NN1 保持 Active/健康）。

### 4.3 窗口与快照

**确认**：应用窗口 2026-11-09 04:00–04:30 可保持，但**前置条件**是平台在 11-08 晚完成 HA 与配置同步。

- 平台窗口：**2026-11-08 21:00–23:00 CST**；
- 应用窗口前（03:30）平台再取一次新鲜快照；
- 旧仓库保留，不删除；
- 回滚时旧 catalog/旧 JAR 可用。

---

## 五、风险与调整建议

| # | 风险 | 说明 | 建议 |
|---|---|---|---|
| 1 | **30 分钟窗口不够平台 HA** | 2 NN + 3 JN + ZKFC + HDFS 重启 + failover 测试至少 90 分钟 | 平台 HA 前置到 11-08 晚；应用窗口只做迁移 |
| 2 | **70 表重建可能超 10 分钟** | 37.6 GB 含副本，`INSERT SELECT` 受并发/小文件影响 | 先迁核心表（RAG/LLM/answer/chunks/learning）；其余可延长到 60 分钟或下次补齐 |
| 3 | **旧 authority 在 failover 后不可用** | 旧路径指向 NN1；NN1 故障时旧 catalog 不可读 | 窗口内保持 NN1 健康；快照兜底；回滚窗口内完成 |
| 4 | **Spark/Hive 重启影响查询** | 配置同步需重启 HS2/ThriftServer | 放在应用窗口前，避开业务高峰 |
| 5 | **Flink 当前作业仍用旧 JAR/旧路径** | 平台 HA 启用会导致 1–2 次 checkpoint 失败 | 应用可在平台窗口暂停 Flink，或接受自动恢复 |
| 6 | **H8 监控告警未在交接单细化** | 需 NN active/standby、JN、ZKFC、failover 事件 | 平台补 Prometheus/Ambari 告警 |
| 7 | **应用脚本/证据不在本仓库** | 37 号单引用 `scripts/`、`datalake/`、`doc/review/evidence/` | 请应用侧提供共享路径，窗口前联合预演 |
| 8 | **迁移路径冲突（2026-11-09 发现）** | `oldice`/`newice` 均指向 `/iceberg-warehouse` 同一物理目录；`DROP newice` 会作用到旧表 | 新 warehouse 改用 `hdfs://qixuandata/iceberg-warehouse-ha`，旧路径保留回滚 |

---

## 六、建议时间表

| 时间（CST） | 动作 | 责任 |
|---|---|---|
| 11-08 20:00–20:30 | 配置备份、快照复核、JN/ZKFC 预检 | 平台 |
| 11-08 21:00–22:30 | 启用 NN HA（2 NN + 3 JN + ZKFC）、HDFS 重启 | 平台 |
| 11-08 22:30–23:00 | failover 演练、Spark/Hive 配置同步、checkpoint 目录、监控 | 平台 |
| 11-09 03:30 | 新鲜快照、最终预检、应用 standby | 平台 + 应用 |
| 11-09 04:00–04:30 | 应用侧 70 表迁移 + 新 JAR + 探针 | 应用（平台观察） |
| 11-09 04:30–05:00 | 缓冲/回滚窗口 | 双方 |

---

## 七、验收映射

| 交接单编号 | 平台/应用 | 平台侧动作 |
|---|---|---|
| H1 nameservice 可读 | 平台 | 启用后 `hdfs dfs -ls hdfs://qixuandata/` |
| H2 2 NN + 3 JN + ZKFC | 平台 | Ambari/手工启用，`hdfs haadmin -getServiceState` |
| H3 自动 failover | 平台 | 停 Active NN，<30s 切换 |
| H4 checkpoint 目录 | 平台 | 创建 `/flink-checkpoints/edulake`，1777 |
| H5 旧仓库可读 | 平台 | 保持 NN1 健康，验证旧路径 |
| H6 HDFS 快照 | 平台 | `pre_nn_ha_20261109` 已建；窗口前再建一次 |
| H7 Spark/Hive 配置 | 平台 | 更新 warehouse/fs.defaultFS 并重启 |
| H8 监控告警 | 平台 | NN/JN/ZKFC/failover 指标与告警 |
| A1–A10 | 应用为主 | 平台提供 nameservice/配置/快照/回滚支持 |

---

## 八、需要应用侧确认

- [ ] 平台窗口 **2026-11-08 21:00–23:00 CST** 是否可用？
- [ ] 平台窗口内是否暂停 Flink（避免 checkpoint 抖动）？
- [ ] 应用脚本/证据的共享路径（`scripts/hdfs_ha_cutover.sh`、`migrate_iceberg_warehouse.py`、evidence JSON）——当前平台仓库未找到，需应用侧提供。
- [ ] 70 表迁移预计耗时；核心表清单与顺序。
- [ ] 04:00–04:30 窗口是否保持；回滚决策人。

---

## 九、关联文档

- `ambarirpm/37-data-lake-platform-ha-handoff-2026-11-08.md` — 应用侧交接单
- `ambarirpm/36-hdfs-nn-ha-cutover-runbook-2026-11-08.md` — 应用侧 30 分钟手册
- `docs/HDFS_NN_HA_PLATFORM_RUNBOOK.md` — 平台侧执行手册
- `docs/PRODUCTION_HA_UPGRADE_PLAN.md` — 总体 HA 方案
- `docs/HA_PROGRESS_REPORT_2026-11-08.md` — Kafka RF3 进展
