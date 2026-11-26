# 生产最小高可用升级方案（容器即主机模型）

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


> **文档编号**：HODOOPFORGE-HA-001  
> **版本**：v2.2（容器 = 主机；2026-11-08 Kafka RF3 已实施）  
> **日期**：2026-11-08  
> **模型前提**：h0 / h1 / h2 / h3 **每个 Docker 容器视为一台独立主机**；**容器宕机 = 主机宕机**；HA 以容器为故障域，通过反亲和部署实现。  
> **边界**：物理宿主机宕机时 4 个容器同时消失，属于单机演示环境的固有限制，**不在本系统“容器级 HA”承诺范围内**；对外口径需明确写“容器级高可用”。

---

## 一、模型与边界（先统一认知）

### 1.1 本系统的 HA 定义

| 概念 | 在本系统中的含义 |
|---|---|
| 主机 | 一个 Docker 容器（h0/h1/h2/h3） |
| 主机宕机 | `docker stop hX` / 容器进程崩溃 / 容器 OOM |
| 故障域 | 容器 |
| 反亲和 | 同一组件的两个副本不得落在同一容器 |
| HA 验收 | `docker stop` 任一容器，业务不中断或自动恢复 |
| **不在范围** | 物理宿主机断电、磁盘损坏、宿主机网络故障（4 容器同时失效） |

> 这不是“降级”，而是本系统的设计价值：**用 4 个容器模拟 4 台主机，在单机上验证分布式 HA 的部署、切换与运维流程**。对外承诺应写“容器级 HA”，不写“物理机级 HA”。

### 1.2 反亲和硬规则

1. 同一组件的两个副本**必须**在不同容器。
2. NN1/NN2、JM1/JM2、HMS1/HMS2、HS2-1/HS2-2、Kafka broker、KDC、Prometheus 均遵守。
3. JournalNode / ZooKeeper 至少 3 个，分布在 3 个容器。
4. 新增组件优先放在**余量最大**的 h3，其次 h2，避免压垮 h1（当前 83.5%）。

---

## 二、现状核实（2026-11-08）

### 2.1 容器资源

| 容器 | 内存上限 | 已用 | 余量 | 说明 |
|---|---|---|---|---|
| h0 | 20 GB | 15.0 GB (75%) | ~5.0 GB | 控制面主，承载 NN/RM/HMS/HS2/Kafka/JM/Ranger/Ambari |
| h1 | **10 GB** | 6.7 GB (67%) | ~3.3 GB | DN/SNN/NM/Spark ThriftServer/ZK |
| h2 | **9 GB** | 5.3 GB (59%) | ~3.7 GB | DN/NM/Flink TM/ZK |
| h3 | **9 GB** | 3.9 GB (44%) | ~5.1 GB | DN/NM/Flink TM/HBase RS/ZK |

> **2026-11-08 宿主机扩容 +8GB**：总内存 48.8 GB，available ≈ 13 GB；容器上限已调整为 h0 20 / h1 10 / h2 9 / h3 9 GB。Swap 仍显示 100%，但 `si/so=0`（无活跃换入换出），属于历史占用，不再是阻塞项。

### 2.2 组件分布

| 容器 | 主要组件 |
|---|---|
| h0 | NameNode、ResourceManager、Hive Metastore、HiveServer2、Kafka Broker、Flink JobManager、HBase Master、Ranger Admin/Usersync/KMS、Infra Solr、ZooKeeper、Ambari |
| h1 | DataNode、SecondaryNameNode、NodeManager、Spark ThriftServer、ZooKeeper、App Timeline |
| h2 | DataNode、NodeManager、Flink TaskManager、ZooKeeper |
| h3 | DataNode、NodeManager、Flink TaskManager、HBase RegionServer、Ranger TagSync、ZooKeeper |

### 2.3 六项差距（容器视角）

| # | 要求 | 当前 | 容器级差距 |
|---|---|---|---|
| 1 | Kafka 3 broker / RF3 | **3 broker（h0/h2/h3），RF3，min.insync=2**（2026-11-08 完成） | ✅ 已完成 |
| 2 | HDFS NN HA | **h0 Active / h3 Standby，3 JN、2 ZKFC、nameservice `qixuandata`**（2026-11-09 完成，11-19 复核） | ✅ 已完成 |
| 3 | HMS/Thrift HA | HMS/HS2 各 1（h0） | 需 HMS2/HS2-2（h3）+ VIP/代理 |
| 4 | Flink JM HA | JM 1（h0），HA 未启用 | 需 JM2（h2）+ ZK + HDFS storageDir |
| 5 | Kerberos/Ranger | Kerberos 未启用；Ranger 1 | 需 KDC1/KDC2（h0/h3）+ keytab + Ranger2（h3） |
| 6 | Prometheus | 1 实例（宿主机） | 需 P2（h3）+ Alertmanager 2 |

### 2.4 应用侧联合核对

| 应用侧声明 | 平台实测 | 结论 |
|---|---|---|
| 1 作业 3 sink RUNNING | 3 Kafka Source → 3 Iceberg Sink，全部 RUNNING | ✅ |
| checkpoint 成功/失败=0 | completed=88，failed=0 | ✅ |
| producer acks=all + 幂等 | broker RF1/min.insync=1 | ⚠️ **acks=all 在 RF1 下不防丢** |
| app sink 降级 + 单写入方 | 旧 bridge 进程已停；ODS 重复=0 | ✅ 方向一致 |
| 旧 bridge 停用 | 无进程；`edulake_bridge_*` 组 Empty | ✅ |
| `/ops/*` 运行态 | 平台未接探测 | ⏳ 待联调 |

> **待确认**：检查时所有消费组均为 Empty。若 app sink 正在运行，请确认其 `group.id` 与心跳；若按需消费，请在 `/ops/stream-ingest` 标注。

---

## 三、目标反亲和矩阵

| 组件 | h0 | h1 | h2 | h3 | 说明 |
|---|---|---|---|---|---|
| Kafka Broker | B1（现有） | — | **B2（新增）** | **B3（新增）** | RF3 / min.insync=2 |
| NameNode | NN1（Active） | **NN2（Standby）** | — | — | ZKFC 同机 |
| JournalNode | **JN1** | — | **JN2** | **JN3** | 3 副本 |
| ZKFC | **ZKFC1** | **ZKFC2** | — | — | 与 NN 同机 |
| DataNode | — | DN1 | DN2 | DN3 | 已有 |
| ZooKeeper | ZK1 | ZK2 | ZK3 | — | 已有 3 节点 |
| Hive Metastore | HMS1 | — | — | **HMS2** | 共 MySQL |
| HiveServer2 | HS2-1 | — | — | **HS2-2** | VIP/代理 |
| MySQL | 主（现有） | — | — | **从（新增）** | 半同步 |
| Flink JM | JM1 | — | **JM2** | — | ZK + HDFS |
| Flink TM | — | TM1 | TM2 | TM3（可选） | 已有 2 |
| Ranger Admin | R1 | — | — | **R2** | DB 共用 |
| KDC | **KDC1** | — | — | **KDC2** | 双 KDC |
| Prometheus | P1（宿主机） | — | — | **P2（容器）** | 双实例 |
| Alertmanager | **AM1** | — | — | **AM2** | 集群去重 |
| HBase Master | HM1 | — | **HM2（可选）** | — | 非六项，二期 |
| HBase RS | — | RS1（可选） | RS2（可选） | RS3 | 非六项，二期 |

> **反亲和检查**：NN1/NN2、Kafka B1/B2/B3、JN1/JN2/JN3、HMS1/HMS2、HS2-1/HS2-2、JM1/JM2、KDC1/KDC2、P1/P2 均不在同一容器。

---

## 四、资源预算与腾挪（关键）

### 4.1 新增组件内存估算（小堆，按当前数据量）

| 组件 | 容器 | 估算堆/内存 | 说明 |
|---|---|---|---|
| Kafka B2/B3 | h2/h3 | 512 MB × 2 | 小流量，堆 512m 足够 |
| NN2 | h1 | 768 MB | Standby |
| JN1/JN2/JN3 | h0/h2/h3 | 192 MB × 3 | 轻量 |
| ZKFC1/ZKFC2 | h0/h1 | 128 MB × 2 | 轻量 |
| HMS2 | h3 | 384 MB | 共用 MySQL |
| HS2-2 | h3 | 512 MB | 小并发 |
| JM2 | h2 | 512 MB | Standby |
| KDC1/KDC2 | h0/h3 | 128 MB × 2 | MIT KDC |
| Ranger2 | h3 | 512 MB | 小堆 |
| Prometheus P2 | h3 | 256 MB | 15s 抓取 |
| Alertmanager ×2 | h0/h3 | 96 MB × 2 | 轻量 |
| **合计** | — | **≈ 4.4 GB** | 不含 MySQL 从库 |

### 4.2 容器余量对照

| 容器 | 当前余量 | 新增 | 结果 | 判断 |
|---|---|---|---|---|
| h0 | 5.0 GB | JN1 + ZKFC1 + KDC1 + AM1 ≈ 0.55 GB | 15.55/20 GB | ✅ 宽裕 |
| h1 | 3.3 GB | NN2 + ZKFC2 ≈ 0.9 GB | 7.58/10 GB | ✅ 可 |
| h2 | 3.7 GB | Kafka B2 + JN2 + JM2 ≈ 1.22 GB | 6.49/9 GB | ✅ 可 |
| h3 | 5.1 GB | Kafka B3 + JN3 + HMS2 + HS2-2 + KDC2 + Ranger2 + P2 + AM2 ≈ 2.4 GB | 6.31/9 GB | ✅ 可 |

> **结论**：+8GB 后六项 HA 组件（约 4.4GB）可全部放入容器上限内，**宿主机仍有约 8.6GB 余量，无需停用 HBase/MapReduce 等现有服务**。

### 4.3 资源腾挪选项（按推荐顺序）

**选项 A（可选，仅性能优化）：停用非业务必需组件（释放 ~3.5–4GB）**

> 扩容后**不再是 HA 的前置条件**；仅在需要进一步降低 Swap/提高性能时考虑。HBase 可保留。

| 组件 | 位置 | 估算释放 | 影响 | 建议 |
|---|---|---|---|---|
| WebHCat | h0 | ~0.5 GB | Hive REST 接口，业务未用 | 可停 |
| Ranger TagSync | h3 | ~0.5 GB | 无 tag source，空转 | 可停 |
| MapReduce History | h0 | ~0.5 GB | 无 MR 作业 | 可停 |
| Flink History | h0 | ~0.5 GB | 历史作业查询，非实时 | 可停或保留 |
| Spark JobHistory | h0 | ~0.5 GB | 历史作业查询，非实时 | 可停或保留 |
| Infra Solr | h0 | ~1.0 GB | Ambari 指标存储 | 可停（改用 Prometheus） |
| Ranger KMS | h0 | ~0.5 GB | 无加密场景 | 可停 |
| HBase Master/RS | h0/h3 | ~2.0 GB | 业务未声明使用 | **需业务确认后停** |

**选项 B：增加 8GB swap 文件（兜底，不释放内存）**

```bash
sudo fallocate -l 8G /swapfile2
sudo chmod 600 /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2
# /etc/fstab 追加：/swapfile2 none swap sw 0 0
```

> 作用：避免新增组件时触发 OOM；代价：Swap 换入换出会拖慢 Kafka/HDFS。**只作为兜底，不能替代选项 A。**

**推荐组合（扩容后）**：**先不做任何停用**，直接进入 Kafka RF3；观察 24 小时。若 Swap 活跃度升高，再选择性停用非业务组件或加 swap 文件。HBase 保留。

### 4.4 实施顺序

1. 容器内存上限已调整（h1 10 / h2 9 / h3 9 GB）→ 观察 30 分钟，确认无 OOM、`si/so` 为 0。
2. 容器反亲和检查（确认现有组件不在同容器重复）。
3. 直接进入 Kafka RF3；暂不停用任何现有服务。

---

## 五、六项改造（容器版）

### 5.1 P0-1：Kafka 3 Broker + RF3 ✅（2026-11-08 完成）

**目标**：`docker stop` 任一 broker 容器，生产/消费不中断，RPO=0。

**步骤**：

1. 通过 Ambari 在 h2、h3 增加 `KAFKA_BROKER` 组件（或手工起 broker 进程，broker.id=1002/1003）。
2. 每 broker 独立 `log.dirs`（容器内独立目录），堆 512m。
3. broker 配置：

```properties
default.replication.factor=3
min.insync.replicas=2
unclean.leader.election.enable=false
num.partitions=6
auto.create.topics.enable=false
```

4. 现有 topic 重分配 RF1 → RF3：

```bash
kafka-reassign-partitions.sh --bootstrap-server h0:9092 \
  --reassignment-json-file reassign.json --execute --throttle 10485760
kafka-reassign-partitions.sh --bootstrap-server h0:9092 \
  --reassignment-json-file reassign.json --verify
```

5. 应用侧 producer 保持 `acks=all`、`enable.idempotence=true`、`retries>0`。

**验收**：

| 用例 | 期望 |
|---|---|
| `docker stop h2`（B2） | producer 继续成功；ISR 恢复；无丢失 |
| `docker stop h0`（B1） | B2/B3 选主；消费继续 |
| 滚动重启 3 broker | 全程可生产/消费 |

**工作量**：2–3 人天；**依赖**：资源腾挪完成。

**实施记录（2026-11-08）**：

- broker：1001（h0）、1002（h2）、1003（h3），全部注册；
- 9/9 topic RF3（含 `__consumer_offsets`），`min.insync.replicas=2`、`unclean.leader.election.enable=false`；
- h2/h3 broker 已配置 systemd 开机自启；
- 故障注入：停止 h3 broker，`acks=all` 生产成功、消费 3/3、ISR 2→3，RPO=0；
- Flink 作业保持 RUNNING；滚动重启 h0 期间 2 次 checkpoint 失败，自动恢复，ODS 重复 0。

> 详细证据见 [`HA_PROGRESS_REPORT_2026-11-08.md`](HA_PROGRESS_REPORT_2026-11-08.md)。

---

### 5.2 P0-2：HDFS NameNode HA ✅（2026-11-09 完成）

**目标**：`docker stop h0`（Active NN），NN2 自动接管 <60s。

**步骤**：

1. Ambari 在 h1 增加 `NAMENODE`（NN2）、h0/h2/h3 增加 `JOURNALNODE`、h0/h1 增加 `ZKFC`。
2. 配置 `dfs.nameservices=qixuandata`、`dfs.ha.namenodes.qixuandata=nn1,nn2`、共享 edits `qjournal://h0:8485;h2:8485;h3:8485/qixuandata`、`dfs.ha.automatic-failover.enabled=true`。
3. `hdfs namenode -bootstrapStandby` 初始化 NN2。
4. 所有客户端 `fs.defaultFS=hdfs://qixuandata`。
5. Ambari 提供 “Enable HA” 向导可简化；手工方式需先备份。

**验收**：

| 用例 | 期望 |
|---|---|
| `docker stop h0` | ZKFC 切换 <60s；HDFS 读写恢复 |
| `docker stop h2`（JN2） | 仍可写 edits（2/3） |
| `docker start h0` | 原 NN 以 Standby 回归 |

**工作量**：3–4 人天。

**2026-11-09 实施结果**：

- NN1 h0 Active / NN2 h3 Standby；JN h0/h1/h3；ZKFC h0/h3；nameservice `hdfs://qixuandata`；
- 双向 failover 成功；旧/新仓库路径均可读；快照 `pre_nn_ha_20261109`、`pre_app_cutover_20261109`；
- Spark/Hive 已切 nameservice；全服务 STARTED；仅 4 条磁盘 WARNING；
- 应用侧迁移：**77 表已迁移并对齐 `-ha`**（2026-11-19 复核，77/77 Location = `hdfs://qixuandata/iceberg-warehouse-ha`）。
- 运维自动化：开机自愈 + 10 分钟巡检已接入（`docs/OPERATIONS_AUTOMATION.md`）。
- Kafka 外部访问：9092/9093/9094 + advertised 已统一（`docs/KAFKA_EXTERNAL_ACCESS.md`）。

**2026-11-19 更新**：

- HDFS：h0 Active / h3 Standby；快照/挂起后 ZK 会话过期可能重新选主，需要时 `hdfs haadmin -failover nn2 nn1`；
- Warehouse：Spark `iceberg` catalog 与 Flink 均指向 `-ha`，77/77 表 Location 对齐；旧 `/iceberg-warehouse` 保留回滚；
- 批处理差异需业务在 `-ha` 重跑 11-18 / 11-09（见 `docs/WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md`）；
- 当前状态单一事实源：`docs/CURRENT_STATE.md`；交互地图：`docs/lake-map.html`。

**2026-11-08 预检记录**：

- 应用侧交接单 `ambarirpm/37-...` 已收到，含 70 表双 catalog 重建、30 分钟切换手册、回滚脚本；
- 平台预检通过：HDFS HEALTHY、0 corrupt/missing/under-replicated、3 DN、JN 端口空闲、warehouse 12.5GB/37.6GB；
- 已创建 HA 前快照 `pre_nn_ha_20261109`；
- **平台窗口需前置**：建议 2026-11-08 21:00–23:00；应用窗口 11-09 04:00–04:30 不变；
- 平台执行手册：`docs/HDFS_NN_HA_PLATFORM_RUNBOOK.md`；评审：`docs/HDFS_NN_HA_PLATFORM_REVIEW.md`。

---

### 5.3 P1-1：HMS / HiveServer2 HA

**目标**：`docker stop h0`，JDBC 经 VIP 切到 h3，查询不中断。

**步骤**：

1. h3 增加 `HIVE_METASTORE`、`HIVE_SERVER`（HMS2/HS2-2）。
2. MySQL 主在 h0，h3 增加从库（半同步）。
3. h2 部署 HAProxy + keepalived，VIP `192.168.0.60:10016`（或内部 VIP）；后端 HS2-1/HS2-2。
4. JDBC URL 使用 VIP，开启重试。

**验收**：

| 用例 | 期望 |
|---|---|
| `docker stop h0` | VIP 切到 h3，JDBC 重连 <30s |
| `docker stop h3` | VIP 切回 h0 |
| MySQL 主停 | 从库提升；HMS 短暂只读 |

**工作量**：2–3 人天。

---

### 5.4 P1-2：Flink JobManager HA

**目标**：`docker stop h0`（JM1），JM2 接管，作业从 checkpoint 恢复。

**步骤**：

1. h2 部署 JM2（Standby），复用现有 ZK（h0/h1/h2）。
2. 配置：

```yaml
high-availability: zookeeper
high-availability.storageDir: hdfs://qixuandata/flink/ha
high-availability.zookeeper.quorum: h0:2181,h1:2181,h2:2181
high-availability.cluster-id: /edulake
```

3. 客户端通过 ZK/负载地址提交；TM 注册 ZK。
4. 保持 checkpoint 20s / EXACTLY_ONCE / RocksDB。

**验收**：

| 用例 | 期望 |
|---|---|
| `docker stop h0` | JM2 接管 <60s；作业自动恢复 |
| 恢复后 | 无重复、无丢失；checkpoint 继续 |

**工作量**：2 人天。

---

### 5.5 P2-1：Kerberos / Ranger

**目标**：容器级强认证；KDC1 宕机不影响已签发 ticket。

**步骤**：

1. h0/h3 部署 KDC1/KDC2（MIT KDC），全容器 chronyd 同步。
2. 生成 keytab（hdfs/yarn/hbase/hive/kafka/zookeeper/ranger/flink/spark）。
3. Ambari 启用 Kerberos（**全服务重启，维护窗口 2–4h**）。
4. Flink 配置 `security.kerberos.login.keytab/principal/contexts`。
5. h3 部署 Ranger Admin2；MySQL 共用/主从；策略与审计集中。
6. 业务客户端改造：JDBC principal、Kafka SASL、定时任务 kinit。

**验收**：

| 用例 | 期望 |
|---|---|
| `kinit` + 各服务读写 | 成功 |
| 无 ticket 访问 | 拒绝 |
| `docker stop h0`（KDC1） | 已签发 ticket 继续；新认证走 KDC2 |
| Ranger 策略变更 | 1 分钟内生效并审计 |

**工作量**：4–6 人天（含业务配合）。

---

### 5.6 P2-2：Prometheus / 告警 HA

**目标**：`docker stop` 任一监控实例，Grafana 查询与告警不中断。

**方案**：

- P1 保留在宿主机（不在容器故障域内），h3 增加 P2；Grafana 双数据源或 Thanos Query。
- Alertmanager AM1（h0）+ AM2（h3）集群去重。
- blackbox_exporter 探测 `/ops/stream-ingest`、`/ops/kafka-health`、JDBC、Kafka lag。
- 长期存储可选 Thanos/VictoriaMetrics（按成本）。

**验收**：

| 用例 | 期望 |
|---|---|
| `docker stop h3`（P2） | Grafana 走 P1，查询连续 |
| `docker stop h0`（AM1） | AM2 继续发送告警 |
| 采集目标宕机 | 1 分钟内告警 |

**工作量**：2 人天。

---

## 六、优先级与排期（无需采购硬件）

| 阶段 | 内容 | 优先级 | 工期 | 依赖 |
|---|---|---|---|---|
| P0-0 | 容器内存上限调整 + 反亲和核对 | P0 | 0.5–1 天 | 已完成上限调整 |
| **P0-1** | **Kafka RF3** ✅ | **P0** | 2–3 天 | P0-0 |
| **P0-2** | **HDFS NN HA** | **P0** | 3–4 天 | P0-0 |
| P1-1 | HMS/HS2 HA + MySQL 从库 | P1 | 2–3 天 | P0-2 |
| P1-2 | Flink JM HA | P1 | 2 天 | P0-2 |
| P2-1 | Kerberos/Ranger | P2 | 4–6 天 | P0-0 |
| P2-2 | Prometheus/Alertmanager HA | P2 | 2 天 | P0-0 |
| — | 容器故障注入演练与验收 | P0 | 1–2 天 | 全部 |

**总工期**：约 **17–24 人天**（不含业务客户端改造）。

**建议节奏**：

1. 第 1 周：资源腾挪 + Kafka RF3 + `docker stop` 演练；
2. 第 2 周：HDFS NN HA + 切换演练；
3. 第 3 周：HMS/HS2、Flink JM；
4. 第 4 周：Kerberos/Ranger（维护窗口）+ Prometheus；
5. 第 4 周末：全链路故障注入验收。

---

## 七、验收矩阵（容器故障注入）

| # | 注入 | 期望 RTO | 期望 RPO | 通过标准 |
|---|---|---|---|---|
| 1 | `docker stop h2`（Kafka B2） | <30s | 0 | 生产/消费不中断 |
| 2 | `docker stop h0`（Kafka B1） | <30s | 0 | B2/B3 选主 |
| 3 | `docker stop h0`（NN1） | <60s | 0 | NN2 自动接管 |
| 4 | `docker stop h2`（JN2） | 0 | 0 | edits 仍可写 |
| 5 | `docker stop h0`（HMS/HS2） | <30s | 0 | VIP 切 h3 |
| 6 | `docker stop h0`（JM1） | <120s | 0 | JM2 恢复作业 |
| 7 | `docker stop h0`（KDC1） | <30s（新认证） | 0 | KDC2 接管 |
| 8 | `docker stop h3`（P2/R2） | <60s | ≤1 周期 | P1 继续；Ranger 切 R1 |
| 9 | **`docker stop` 任一容器** | 按上表 | 0 | 六项均满足 |

> **验收原则**：只接受**跨容器反亲和**；同一容器内双实例不算通过。

---

## 八、风险与边界

| 风险 | 影响 | 缓解 |
|---|---|---|
| **宿主机物理故障** | 4 容器同时消失 | **不在承诺范围**；对外写“容器级 HA”；关键数据定期备份到外部 |
| 宿主机内存不足 | OOM / Swap 抖动 | 资源腾挪 + 8GB swap 兜底 + 监控 |
| 共享磁盘 | 磁盘故障影响所有容器 | 外部备份；HDFS 3 副本只能防容器故障，不能防盘故障 |
| 共享 bridge 网络 | 网络抖动影响所有容器 | 监控 + 限流；容器级 HA 不覆盖网络故障 |
| h1 余量仅 1.3GB | NN2 部署后更紧 | 压 Spark ThriftServer/SNN 堆，或把 NN2 改放 h2（需重算反亲和） |
| Kerberos 全服务重启 | 停机 2–4h | 维护窗口 + 测试预演 + Disable Kerberos 回滚 |
| 业务客户端未改造 | 认证失败 | 提前发 krb5.conf/keytab + 联调 |

**回滚原则**：每项保留原配置与数据快照；Kafka 保留原 assignment JSON；HDFS 保留单 NN 配置；Kerberos 用 Ambari Disable Kerberos。

---

## 九、给应用侧的答复（可直接转发）

> 应用侧的「单写入方 + Exactly-Once + 质量门禁」已核对：1 作业 3 sink RUNNING、checkpoint 155 完成 / 2 次滚动重启瞬时失败（已恢复）、ODS 重复 0、旧 bridge 已停，平台确认一致。
>
> 关于底座：我们按本系统“**一个容器 = 一台主机**”的模型做容器级 HA，不要求另购物理机。**Kafka RF3 已完成**：3 broker（h0/h2/h3）、9/9 topic RF3、min.insync=2，故障注入通过（停 h3 broker 期间 acks=all 生产/消费不中断，RPO=0）。
>
> 剩余：
> - HDFS NN HA（NN1 h0 / NN2 h1 + JN h0/h2/h3 + ZKFC）；
> - HMS/HS2 HA（h0/h3 + VIP）、Flink JM HA（h0/h2）、KDC/Ranger 双实例、Prometheus 双实例。
>
> 宿主机已扩容 **+8GB**（48.8GB，available ≈ 13GB），容器上限已调整为 h1 10GB / h2 9GB / h3 9GB；六项 HA 约需 4.4GB，**无需停用 HBase/MapReduce 等现有服务**。
>
> 完成后用 `docker stop` 逐容器做故障注入验收（RTO/RPO 见方案）。**边界说明**：物理宿主机断电不在容器级 HA 承诺范围，对外口径写“容器级高可用”。

---

## 十、关联文档

- `docs/KERBEROS_ENABLEMENT_PLAN.md` — Kerberos 启用详细步骤
- `docs/manual/01-architecture.md` — 当前架构与 ADR
- `docs/manual/05-operations.md` — 运维与应急
- `docs/manual/08-performance.md` — 容量与资源基线
- `func/ROADMAP.md` — 里程碑 M4
- `func/TASK_TRACKER.md` — 任务 T-061~T-068
