# 事故与恢复报告：HDFS NameNode 双停 + Ambari HA Wizard 残留

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


- **日期**：2026-11-18
- **影响面**：HDFS（NameNode 全部停止）、HBase（Master/RS 停止）、Flink（TaskManager 停止、作业反复重启）
- **当前状态**：✅ 已恢复；HDFS **h0 Active / h3 Standby**（2026-11-19 复核），HBase 1 Master + 1 RS，Flink 作业 RUNNING，Spark/Hive/Kafka 正常
- **后续更新**：2026-11-19 完成 77/77 表 Location 对齐到 `-ha`，详见 [`WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md`](WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md)；当前状态以 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准
- **级别**：S1 / P0（存储主服务不可用超过 24h）

---

## 1. 结论（先看这里）

| 项 | 事故期间 | 现在 |
|---|---|---|
| HDFS NameNode | ❌ h0 于 11-14 05:21 停、h3 于 11-17 07:48 停，**两台都不可用** | ✅ h0 Active、h3 Standby（11-19 复核），3 DataNode Live，0 missing blocks |
| HBase | ❌ Master/RS 进程不存在 | ✅ 1 active master / 1 regionserver / 0 dead |
| Flink | ⚠️ Job `42c0fdb…` 反复 `RESTARTING`（TM 全停 + slot 不足） | ✅ RUNNING，3 Source / 3 Sink，checkpoint 持续完成 |
| Spark | ✅ ThriftServer 进程在、可查询（但 HDFS 不可写） | ✅ Spark 3.5.6，ODS 227 / ADS 10，`-ha` 仓库可查 |
| Hive | ✅ HS2/Metastore 进程在 | ✅ `SELECT 1` 正常 |
| Kafka | ✅ 3 broker | ✅ 3 broker，topic RF3 |
| Ambari Wizard | ❌ 每次进入都弹 `Enable NameNode HA Wizard / Finalize HA Setup` | ✅ 已修，进入直接到 Services |

**重要**：
1. **HDFS 自动 failover 是生效的**：11-14 05:21 h0 NN 停止后，h3 在 20 秒内自动切为 Active（日志 `startActiveServices`），单 NN 继续服务到 11-17。
2. 11-17 07:48 h3 上的 NN 收到 **SIGTERM**（JVM shutdown hook，非 OOM、非崩溃），之后没有再次拉起，才导致双 NN 全停。
3. Ambari 请求表里**没有**对应的 STOP 请求（最后一条业务请求是 11-09），说明不是 Ambari 正常停服流程，而是进程被直接终止（人工/脚本/宿主侧操作）。
4. 那个反复出现的 Wizard 是**服务端 persist + 浏览器 localStorage 两层残留**（`currentStep=9`），不是 HA 真的没做完；服务端 `request` 表 581 条、0 条未完成。服务端重置脚本已于 11-09 落地，11-18 又补了浏览器层自愈。

---

## 2. 时间线（来自日志与 DB）

| 时间 | 事件 | 证据 |
|---|---|---|
| 2026-11-09 05:25 | 上次正常 HA 运行，h3 Standby | NN 日志 `StandbyCheckpointer` |
| 2026-11-14 05:21:20 | h0 NN 正常 SHUTDOWN（SIGTERM） | `hadoop-hdfs-namenode-…log` `SHUTDOWN_MSG` |
| 2026-11-14 05:21:23 | **h3 自动切 Active** | `startActiveServices(1353)` |
| 2026-11-17 07:48:26 | h3 NN 正常 SHUTDOWN（SIGTERM） | `SHUTDOWN_MSG` + JVMShutdownHook |
| 2026-11-18 09:53 | h2 上 NM/ZK 告警开始超时（host 侧同时异常） | alert_current |
| 2026-11-18 10:07 | 平台执行 HDFS 启动（request 734） | Ambari request 734 COMPLETED |
| 2026-11-18 10:09 | h0 NN 启动为 Standby，随后 h3 成为 Active | NN 日志 |
| 2026-11-18 10:13 | HBase 启动（request 735） | Ambari request 735 |
| 2026-11-18 10:18 | Flink TM 启动（request 736/737） | Ambari request 736/737 |
| 2026-11-18 10:36 | h3 成为 Active，h0 Standby（host 重启后再次自动切换） | `startActiveServices` |

---

## 3. 根因分析

### 3.1 HDFS 双 NN 停止
- 两次都是**进程收到 SIGTERM 后优雅退出**，不是 crash、不是 OOM、不是磁盘满。
- Ambari `request` 表没有 STOP 记录，排除“通过 Ambari 正常停服”。
- 结合当时 Ambari UI 一直停在 `Enable NameNode HA Wizard / step9`，最可能的操作路径是：**有人在残留 Wizard 上继续点步骤/确认，触发了对已 HA 集群的重复 HA 操作或直接停进程**。
- 无论触发者是谁，暴露出的真实问题是：**NN 停止后没有 watchdog 自动拉起**，且告警没有在 24h 内升级到人。

### 3.2 Ambari Wizard 反复出现（两层残留）
- **服务端层**：Ambari persist `CLUSTER_CURRENT_STATUS` 曾残留 `clusterState=HIGH_AVAILABILITY_DEPLOY`、`wizardControllerName=highAvailabilityWizardController`、`HighAvailabilityWizard.currentStep=9`，导致换浏览器/换机器也复现（BUG-047，已由 `scripts/ambari_reset_ha_wizard.sh` 重置为 `CLUSTER_INSTALLED_4`）。
- **浏览器层**：`localStorage` 的 `ambari.HighAvailabilityWizard.currentStep` 仍可能为 `"9"`，旧 Tab 会把它再次写回服务端（BUG-050）。
- 因此只重置服务端不够，还需要前端自愈：本次在 `index.html` 注入脚本，进入时清 step9 并改写 wizard 路由。
- 该弹窗里的 **YES 是“回滚 HA”**，非常危险；用户为了关弹窗点时可能造成真实停服。

### 3.3 Flink 作业反复重启
- 直接异常：`NoResourceAvailableException: Could not acquire the minimum required resources`。
- 原因：h2/h3 的 `FLINK_TASKMANAGER` 处于 `INSTALLED`（未运行），集群只有 JM，没有任何 slot。
- 隐患：原配置 `taskmanager.numberOfTaskSlots=2`，即使两台 TM 都起来也只有 4 slot，而作业需要 9 slot（3 条链路 × (2 并行 + 1 committer)）。
- 处置：通过 Ambari 配置把 slot 调到 **8**，启动 h2/h3 TM（2×8=16 slot），作业恢复。

---

## 4. 恢复动作（已执行）

```text
1) 清理 h0 上挂了 5 天的僵尸进程：
   DFSHAAdmin -transitionToActive --forcemanual nn1  (pid 1664687) -> kill -9

2) 通过 Ambari 启动 HDFS（request 734）：
   h0 NN Active / h3 NN Standby / 3 DataNode / 3 JournalNode / 2 ZKFC

3) 通过 Ambari 启动 HBase（request 735）：
   1 active master, 1 regionserver, 0 dead

4) Flink：
   - Ambari flink-conf 新增 tag，taskmanager.numberOfTaskSlots: 2 -> 8
   - 启动 h2/h3 FLINK_TASKMANAGER（request 736/737）
   - 作业 42c0fdb46751781c640b17be70550b9b 自动恢复 RUNNING

5) Ambari Wizard 自愈（两层）：
   - 服务端：`scripts/ambari_reset_ha_wizard.sh` 已重置 persist（11-09）
   - 浏览器层：在 /usr/lib/ambari-server/web/index.html 注入脚本：
     currentStep==9 时清空 HighAvailabilityWizard；
     命中 .../highAvailability/NameNode/enable/stepN 时跳回 #/main/services
   - 原文件备份为 index.html.orig
   - 可重复执行脚本：scripts/fix_ambari_ha_wizard.sh
```

---

## 5. 验收结果（2026-11-18 10:45）

| 检查项 | 结果 |
|---|---|
| HDFS HA | `h0 active / h3 standby`（11-19 复核） |
| DataNode | 3 Live / 0 Dead |
| Missing blocks | 0 |
| HDFS 容量 | 412.17 GB，Used 6.84% |
| HBase | `1 active master, 0 backup, 1 servers, 0 dead` |
| Hive HS2 | `SELECT 1` 返回 `1` |
| Spark ThriftServer | Spark **3.5.6**，`newice` ODS **227**、ADS 10 |
| Flink 作业 | RUNNING，checkpoint latest **5680**，3 sink |
| 端到端探针 | 写入 `iceberg-warehouse-ha`，Spark 可查 |
| Kafka | 3 broker，topic RF3 |
| Ambari Wizard | 刷新后直达 `#/main/services`，modal 消失 |
| Ambari 告警 | 0 CRITICAL；仅 4 条磁盘 WARNING（57.7%）
| LastCheckpoint | h0/h3 均为 2026-11-18 11:02（强制 checkpoint 后） |

---

## 6. 剩余告警与后续动作

| 告警 | 现状 | 处理 |
|---|---|---|
| `namenode_last_checkpoint` ×2 | 102h 未 checkpoint（事故期间停滞） | ✅ 已处理：临时把 `checkpoint.period` 调为 60s 并重启 h0 Standby，11:02 完成一次 checkpoint（两台 NN 的 `LastCheckpointTime` 均已更新），随后恢复为 21600 并再次重启 Standby；告警已清零 |
| `yarn_nodemanager_webui*`、`zookeeper_server_process`（h2） | 09:53 的旧结果残留；实测 h2:8042、2181 均正常 | 已重启 h2 ambari-agent，等待下一轮上报自动恢复；若仍不消失再重启 Ambari Server |
| 磁盘 WARNING ×4 | 57.6% | 扩容或清理，非本次事故引入 |
| BUG-043 NVMe timeout | OPEN | 硬件侧排查 |

**必须补的防线（建议本周完成）**：
1. **NameNode watchdog**：每 60s 检查 `8020`，连续 2 次失败自动 `ambari-agent start NAMENODE` 并告警。
2. **禁止在生产 Ambari 上继续点击残留 Wizard**：已在 `index.html` 自愈；YES=回滚 HA。
3. **告警升级**：CRITICAL 超过 30 分钟未恢复，必须电话/IM 通知到人（当前 24h 无人处理）。
4. **Flink TM 纳入巡检**：`/taskmanagers` 数量 < 2 或 free slots < 作业需求即告警。

---

## 7. 复现/修复脚本

```bash
# 修复 Ambari Wizard（幂等）
bash scripts/fix_ambari_ha_wizard.sh

# 检查是否已注入
bash scripts/fix_ambari_ha_wizard.sh --check
```
