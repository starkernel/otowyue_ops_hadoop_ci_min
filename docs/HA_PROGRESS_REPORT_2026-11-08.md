# 生产最小 HA 进展报告：Kafka RF3 已完成

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


> 历史报告。当前状态以 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准；外部 Kafka/NAT 后续修复见 [`KAFKA_EXTERNAL_ACCESS.md`](KAFKA_EXTERNAL_ACCESS.md)。

> **文档编号**：HODOOPFORGE-HA-PROGRESS-001  
> **日期**：2026-11-08  
> **对应方案**：`docs/PRODUCTION_HA_UPGRADE_PLAN.md` v2.1  
> **结论**：第一优先级 **Kafka 3 Broker / RF3** 已完成并通过故障注入；业务未中断，无数据丢失/重复。  
> **边界**：本系统为**容器级 HA**（每个容器 = 一台主机）；物理宿主机故障不在承诺范围。

---

## 一、完成内容

| 项 | 实施结果 |
|---|---|
| Broker 数 | **3**：1001（h0）、1002（h2）、1003（h3） |
| Topic 副本 | **9/9 全部 RF3**（含 `__consumer_offsets`） |
| 最小同步副本 | `min.insync.replicas=2` |
| 非干净选主 | `unclean.leader.election.enable=false` |
| 内部 topic | `offsets.topic.replication.factor=3`、`transaction.state.log.replication.factor=3` |
| 新 topic 默认 | h0/h2/h3 均为 `default.replication.factor=3`、`num.partitions=6`、`auto.create.topics.enable=false` |
| 进程守护 | h2/h3 已配置 `systemd kafka-broker.service`，容器重启自动拉起 |
| 滚动重启 | h0 broker 已滚动重启，Ambari 状态恢复 **STARTED** |

---

## 二、故障注入结果

**场景**：停止 h3 broker（broker.id=1003），在故障期间用 `acks=all` 生产并消费。

| 步骤 | 结果 |
|---|---|
| 停止前生产 2 条 | ✅ |
| 停止 h3 broker | 9092 关闭 |
| 故障期间生产 1 条（acks=all） | ✅ 成功 |
| 故障期间消费 | ✅ 3/3 条全部读到（during-1 / before-1 / before-2） |
| 故障期间 ISR | 2/3（符合 min.insync=2） |
| 恢复 h3 broker | 8 秒内 ISR 回到 3/3 |
| 测试 topic 清理 | ✅ 已删除 |

**结论**：单 broker 故障时，生产/消费不中断，RPO=0；恢复后副本自动补齐。

---

## 三、业务链路影响

| 项 | 结果 |
|---|---|
| Flink 作业 | `edulake-realtime-ingest` **RUNNING**（3 Source / 3 Sink） |
| Checkpoint | completed=155、failed=2、restored=3 |
| ODS 重复主键 | **0** |
| 消费组 | 已恢复消费；`edulake_app_sink_v1` 等组正常 |
| 数据丢失/重复 | **无** |

> **说明**：`failed=2` 发生在 h0 broker 滚动重启的瞬间（控制器切换），作业自动从 checkpoint 恢复；属于预期内的短暂抖动，不是数据问题。后续滚动重启会使用 `systemctl stop`（受控关闭）减少该类抖动。

### 3.1 实施期间的其他事件

| 事件 | 处置 | 当前状态 |
|---|---|---|
| HBase RegionServer@h3 因 Ranger 审计写 HDFS 失败而 Abort | Ambari 重启 HBASE_REGIONSERVER | ✅ STARTED，Master UI 显示 1 RS / 3 regions |
| 宿主机 NVMe 周期性 `I/O timeout`（dmesg 169 条，最近 17:54） | 已记录，建议硬件检查 | ⚠️ 待硬件排查 |
| Ambari 磁盘使用 WARNING（4 台，/ 约 53%） | 非业务告警，观察 | ⚠️ 4 条 WARNING |

> HBase 的 Abort 与 Kafka RF3 无直接因果，但时间上发生在同一维护窗口；根因指向 HDFS 写入 pipeline + NVMe I/O 抖动。已恢复，不影响 Kafka 结论。

---

## 四、与业务要求的对应

| 业务要求 | 状态 |
|---|---|
| Kafka 3 broker | ✅ 完成 |
| RF3 | ✅ 完成 |
| producer `acks=all` 真正生效 | ✅ 在 RF3 + min.insync=2 下生效 |
| 单 broker 故障不丢 | ✅ 已验证 |
| 旧 bridge 停用/单写入方 | ✅ 保持（ODS 重复 0） |
| 其余五项 | ⏳ 待实施 |

---

## 五、剩余五项与下一步

| 顺序 | 项目 | 计划 |
|---|---|---|
| 2 | **HDFS NN HA** | NN1 h0 / NN2 h1 + JN h0/h2/h3 + ZKFC；`docker stop h0` 验证自动切换 |
| 3 | HMS/HS2 HA | HMS2/HS2-2 h3 + VIP + MySQL 从库 |
| 4 | Flink JM HA | JM2 h2 + ZK + HDFS storageDir |
| 5 | Kerberos/Ranger | KDC1 h0 / KDC2 h3 + keytab + 维护窗口 |
| 6 | Prometheus HA | P2 h3 + Alertmanager 2 |

**下一步 HDFS NN HA 需要业务侧配合一件事**：

- 当前 Iceberg warehouse 使用 `hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse`；
- 启用 NN HA 后，客户端应改为 nameservice `hdfs://qixuandata/iceberg-warehouse` 才能享受自动切换；
- 需要应用侧在 Flink SQL / Spark 配置中同步修改，并安排 **30 分钟维护窗口**做切换演练。

### 5.1 应用侧交接与平台预检（2026-11-08）

- 已收到应用侧交接单 `ambarirpm/37-data-lake-platform-ha-handoff-2026-11-08.md`；
- 应用侧已完成：warehouse/checkpoint 改 nameservice、70 表双 catalog 迁移脚本、30 分钟切换手册、回滚脚本；
- 平台预检：HDFS **HEALTHY**、0 corrupt/missing/under-replicated、3 DN、JN 端口空闲、warehouse 12.5GB/37.6GB；
- 已创建 HA 前快照 `pre_nn_ha_20261109`，并完成 HDFS 配置备份；
- **窗口调整**：30 分钟仅够应用侧切换；平台启用 NN HA + Spark/Hive 配置需前置 **90–120 分钟**，建议 **2026-11-08 21:00–23:00**；应用窗口 11-09 04:00–04:30 不变。

---

## 六、风险提示

1. **NVMe I/O timeout**：宿主机 dmesg 累计 169 条，最近 17:54；可能再次引发 HDFS pipeline 失败/HBase Abort，建议尽快做磁盘健康检查或更换。
2. **磁盘使用 WARNING**：4 台容器 `/` 约 53%，当前不影响业务；建议清理历史日志或调整阈值。
3. **HBase 单 RS**：当前仅 h3 一个 RegionServer，HBase 本身尚无 HA；不在本次六项范围内，后续可加 RS2/RS3。

---

## 七、边界说明（对外口径）

- 本次完成的是**容器级 HA**：任一 Kafka broker 容器/进程故障，业务不中断。
- **物理宿主机故障**（4 个容器同时消失）不在本系统承诺范围；对外应写“容器级高可用”，不写“物理机级 HA”。
- 整容器 `docker stop h3` 的故障注入，建议在 HDFS/Flink/HBase 反亲和完成后统一做，避免当前单 RS/单 TM 造成误判。

---

## 八、证据命令

```bash
# 3 broker
kafka-broker-api-versions.sh --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092

# RF/ISR
kafka-topics.sh --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 --describe

# 故障注入（h3 broker 停止期间）
kafka-console-producer.sh ... --topic ha_test_rf3 --producer-property acks=all
kafka-console-consumer.sh ... --topic ha_test_rf3 --from-beginning --max-messages 3
```

---

**平台运维组**  
2026-11-08
