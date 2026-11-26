# HDFS NameNode HA 完成报告（容器级）

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


> 历史报告。当前状态以 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准；迁移范围已由 70 表扩展到 **77 表**，并在 2026-11-19 完成 `-ha` Location 对齐。

> **文档编号**：HODOOPFORGE-HA-PROGRESS-002  
> **日期**：2026-11-09  
> **对应交接单**：`ambarirpm/37-data-lake-platform-ha-handoff-2026-11-08.md`  
> **结论**：**HDFS NN HA 已完成并验收通过**；nameservice `hdfs://qixuandata` 生效，2 NN + 3 JN + 2 ZKFC，双向 failover 成功；旧/新仓库路径均可读。应用侧 70 表迁移可开始。

---

## 一、当前 HA 拓扑

| 组件 | 部署 | 状态 |
|---|---|---|
| NameNode 1 | h0（bigtop-hostname0） | **Active** |
| NameNode 2 | h3（bigtop-hostname3） | **Standby** |
| JournalNode | h0 / h1 / h3 | 3/3 STARTED |
| ZKFC | h0 / h3 | 2/2 STARTED |
| DataNode | h1 / h2 / h3 | 3/3 STARTED |
| nameservice | `hdfs://qixuandata` | ✅ 可读写 |
| 自动 failover | `dfs.ha.automatic-failover.enabled=true` | ✅ |

---

## 二、验收证据

| 项 | 结果 |
|---|---|
| `hdfs haadmin -getAllServiceState` | nn1 **active** / nn2 **standby** |
| 手动 failover（nn2→nn1） | ✅ 成功，切换后读写正常 |
| 手动 failover（nn1→nn2） | ✅ 成功，切回正常 |
| `hdfs dfs -ls hdfs://qixuandata/` | ✅ 16 项 |
| `hdfs dfs -put` 到 nameservice | ✅ 成功 |
| 旧路径 `hdfs://bigtop-hostname0...:8020/iceberg-warehouse` | ✅ 可读（NN1 保持 Active） |
| 新路径 `hdfs://qixuandata/iceberg-warehouse` | ✅ 可读 |
| Flink checkpoint 目录 | ✅ `/flink-checkpoints/edulake` 1777 |
| 快照 | ✅ `pre_nn_ha_20261109`、`pre_app_cutover_20261109` |
| Spark `fs.defaultFS` | ✅ `hdfs://qixuandata` |
| Spark Iceberg warehouse | ✅ `hdfs://qixuandata/iceberg-warehouse` |
| Hive `fs.defaultFS` | ✅ `hdfs://qixuandata` |
| Kafka | ✅ 3 broker，9/9 topic RF3 |
| 服务状态 | HDFS/YARN/HIVE/HBASE/KAFKA/SPARK/FLINK 全部 **STARTED** |
| 告警 | 93 OK，**4 条磁盘使用 WARNING**，0 CRITICAL |

---

## 三、实施中遇到的问题与处置

| # | 问题 | 根因 | 处置 |
|---|---|---|---|
| 1 | Ambari HA 向导卡在 “Start Additional NameNode” | NN1 先起为 standby，NN2 未 bootstrap，形成死锁 | 手动 `hdfs namenode -bootstrapStandby -force` + 启动 NN2 + ZKFC |
| 2 | NN2 启动失败 `bound must be positive` | h3 缺少 Ranger HDFS 插件配置（`ranger-hdfs-security.xml`、`/etc/ranger/qixuandata_hadoop`） | 从 h0 补齐配置后 NN2 正常启动 |
| 3 | ZKFC 卡在 `INIT → STARTED` 非法状态 | Ambari 状态机死锁（同类 BUG-030） | DB `current_state=INSTALLED` → 重启 Ambari Server → 启动 ZKFC |
| 4 | HDFS 服务显示 INSTALLED | Secondary NameNode 仍存在，HA 后应删除 | 删除 h1 `SECONDARY_NAMENODE`，HDFS 变为 STARTED |
| 5 | Spark 仍用旧 warehouse | 手工改 `spark-defaults.conf` 被 Ambari 覆盖 | 通过 Ambari desired_config 写入 `spark-defaults-ns-*`，重启 ThriftServer |
| 6 | NodeManager 未启动，Spark ThriftServer 拿不到资源 | 向导未启动 NM | 手动启动 h1/h2/h3 NODEMANAGER；`yarn node -list` 3 节点 |
| 7 | YARN TimelineReader/RegistryDNS CRITICAL | 组件 INSTALLED | 启动后 CRITICAL 清零 |

> 以上均为实施过程中的可恢复问题，已全部处理；HDFS HA 与业务服务当前正常。

---

## 四、重要约束

1. **旧 authority 仅在 NN1 Active 时可用**：旧表 metadata 写死 `hdfs://bigtop-hostname0...:8020`；当前已把 NN1 切为 Active，旧路径可读。应用迁移/回滚期间需保持 NN1 健康。
2. **容器级 HA**：本次为容器故障域；物理宿主机故障不在承诺范围。
3. **快照**：`pre_nn_ha_20261109`（HA 前）、`pre_app_cutover_20261109`（应用切换前）。
4. **磁盘 WARNING**：4 台 `/` 约 53%，非业务告警；建议后续清理日志或调整阈值。

---

## 五、关键发现：应用迁移脚本存在路径冲突（必须先修正）

在准备执行应用侧 `hdfs_ha_cutover.sh migrate` 前，平台做了只读验证，发现：

- `oldice` warehouse：`hdfs://bigtop-hostname0...:8020/iceberg-warehouse`
- `newice` warehouse：`hdfs://qixuandata/iceberg-warehouse`
- **两者指向同一个物理目录**（只是 authority 不同）；
- 对 `newice.edulake_ai.ods_llm_inference_log` 执行 `SHOW CREATE TABLE`，返回的 `LOCATION` 仍是旧 authority 路径，证明新旧 catalog 操作的是同一张表目录。

**风险**：应用脚本中的 `DROP TABLE IF EXISTS newice...` / `CREATE TABLE newice...` / `INSERT INTO newice...` 会直接作用在旧表目录上，可能删除或覆盖旧表 metadata，**破坏回滚副本**。

**修正方案（建议）**：

1. 新 warehouse 改用独立目录，例如 `hdfs://qixuandata/iceberg-warehouse-ha`；
2. 应用侧设置 `NEW_ICEBERG_BASE=hdfs://qixuandata/iceberg-warehouse-ha`（脚本已支持 `--new-base`）；
3. 新 Flink JAR 的 warehouse 同步改为 `-ha` 路径；
4. Spark `spark.sql.catalog.iceberg.warehouse` 在迁移完成后改为 `-ha`；
5. 旧 `/iceberg-warehouse` 保持不动，作为回滚副本。

> **当前状态：`migrate` 未执行。** 等待应用侧确认新路径并重建 JAR 后再执行。

---

### 5.1 迁移完成与作业切换（2026-11-09）

- ✅ 70/70 表迁移完成，旧/新行数 **0 mismatch、0 missing**；
- ✅ 旧 `/iceberg-warehouse` 未动，保持回滚能力；
- ✅ 应用侧 JAR 已取到：`flink-sql-job-ha.jar` SHA256 与业务方一致；`rollback.jar` 也已校验；
- ⚠️ 应用 JAR 的 checkpoint 原为 60s；平台复制并调整为 **20s**（满足 <30s 验收）后提交；
- ✅ 新作业 `bbf6360dfddf6592aa04fcf56e10faa8` **RUNNING**，3 Source / 3 Sink；
- ✅ checkpoint completed=7、failed=0，`interval=20000ms`，实际约 20s 一次；
- ✅ 探针事件 `post_fix_1794210460514`：19s 可见，写入 `-ha`。

> 说明：提交的是平台调整过 checkpoint 的副本 `/tmp/opencode/flink-sql-job-ha-20s.jar`；建议应用侧后续用 20s 重新构建正式 JAR，保持 SHA 可追溯。

---

### 5.2 原路径冲突发现（历史）

- ✅ 创建 `/iceberg-warehouse-ha`（`hdfs:hadoop 775`）；
- ✅ 创建 Ranger 策略 `iceberg-warehouse-ha`（id 19），授予 `hdfs/flink/spark/ambari-qa` read/write/execute；
- ✅ 单表试迁 `edulake_ai.ods_llm_inference_log`：旧 102 行 → 新 102 行，新位置 `hdfs://qixuandata/iceberg-warehouse-ha/...`，旧表保持不动；
- 🚧 70 表全量迁移已启动（beeline 双 catalog 方式）；
- ⏳ 新 Flink JAR 尚未在平台侧找到（`/tmp/opencode/flinkjob/out/flink-sql-job.jar` 不存在），`submit` 待应用侧提供路径。

---

## 五、2026-11-09 备份后异常与恢复

### 5.1 事件

| 时间（CST） | 事件 |
|---|---|
| 15:34–15:35 | 备份重 I/O 触发 NVMe timeout；HBase RS 因 WAL 写 HDFS 失败 Abort；h0 NameNode 退出 |
| 15:38 | 平台重启 h0 NAMENODE / h3 HBASE_REGIONSERVER |
| 15:40 | HDFS 恢复为 h0 standby / h3 active；HBase Master/RS 恢复 |
| 15:45 | 发现 Flink 作业实际 checkpoint 仍为 60s（`SqlJob.class` 硬编码），平台对 class 常量打补丁 |
| 15:50 | 提交 fixed JAR，作业 `bbf6360...` RUNNING，interval=20s |
| 15:55 | 探针 19s 可见；切回 h0 active，旧/新仓库均可读 |

### 5.2 根因

- 备份产生大 I/O，NVMe 出现周期性 `I/O timeout`（BUG-043）；
- HDFS NameNode 的 Ranger 审计写 HDFS 失败并退出；
- HBase RS WAL async close 失败，`HRegionServer Aborted`；
- Flink 作业在 HDFS 切换期间出现 2 次 checkpoint 失败，自动恢复。

### 5.3 处置

- 重启 NN1 / HBase RS；
- 对 `SqlJob.class` 的 `60s/30s` 常量做等长替换为 `20s/10s`，重新打包提交；
- 切回 h0 active，恢复旧 authority 可读；
- 当前：**0 CRITICAL**，仅 4 条磁盘 WARNING；Kafka 68/68 分区 RF3+ISR3；HBase 1 RS Normal；Flink 3 sink / 7 checkpoint / 0 failed。

### 5.4 建议

1. 备份避开业务高峰，使用 `ionice`/`rsync --bwlimit` 限流；
2. 尽快对 NVMe 做健康检查/更换（BUG-043）；
3. HBase 增加 RS2 或 watchdog；
4. 应用侧在源码中把 checkpoint 改为 20s，重建正式 JAR。

---

## 六、Ambari 登录后强制跳转 HA Wizard step9（已修复）

现象：即使用全新浏览器 / 全新系统，登录 `http://<ambari>/` 仍落到
`#/main/services/highAvailability/NameNode/enable/step9`。

根因不是浏览器缓存，也不是 HA 未完成，而是 Ambari **按用户持久化**的
`CLUSTER_CURRENT_STATUS`（`/api/v1/persist/CLUSTER_CURRENT_STATUS`）仍为：

```json
{
  "clusterState": "HIGH_AVAILABILITY_DEPLOY",
  "wizardControllerName": "highAvailabilityWizardController",
  "localdb": { "HighAvailabilityWizard": { "currentStep": "9" } }
}
```

登录后 `getSection()` 读取 `wizardControllerName`，直接路由到 HA 向导；
向导再按 `currentStep=9` 落到 step9。该状态保存在服务端，所以换机器仍复现。

处置：

- 确认 HDFS 组件/配置正常（2 NN + 2 ZKFC + 3 JN 全 STARTED，SNN 已删除），
  `requests` 0 条未完成；
- 通过 persist API 将 `clusterState` 重置为 `CLUSTER_INSTALLED_4`，移除
  `wizardControllerName` 与 `localdb.HighAvailabilityWizard`；
- 同时清理 `wizard-data`（向导占用标记）；
- 执行前先关闭仍停留在 step9 的旧标签页；打开着的向导标签可能把旧状态再次写回；
- 脚本：`scripts/ambari_reset_ha_wizard.sh`（可重复执行）；
- 验证：全新标签页访问 `/` 落到 Dashboard，`#/main/services` 落到 HDFS
  Summary，均无向导弹窗。

> 不要点向导弹窗里的 **YES**；那会触发 HA 回滚，拆掉已完成的 NN HA。

---

## 七、应用侧下一步

平台已就绪，应用侧可以开始：

1. 确认 Flink 当前作业已停止（平台已停旧作业，当前无 RUNNING 作业）；
2. 执行 `hdfs_ha_cutover.sh migrate`：oldice → newice 重建 70 表；
3. 提交新 JAR（warehouse/checkpoint 均为 `hdfs://qixuandata`）；
4. 发探针事件，验证 3 sink RUNNING、checkpoint≥1、ODS 无重复；
5. 失败则执行 `rollback`，旧 catalog/旧表保留。

> **平台待命**：nameservice、Spark/Hive 配置、checkpoint 目录、快照、Kafka RF3 均已就绪；应用侧脚本/执行人到位即可开始。

---

## 七、关联文档

- `docs/HDFS_NN_HA_PLATFORM_REVIEW.md`
- `docs/HDFS_NN_HA_PLATFORM_RUNBOOK.md`
- `ambarirpm/37-data-lake-platform-ha-handoff-2026-11-08.md`
- `ambarirpm/36-hdfs-nn-ha-cutover-runbook-2026-11-08.md`
- `docs/HA_PROGRESS_REPORT_2026-11-08.md`（Kafka RF3）
