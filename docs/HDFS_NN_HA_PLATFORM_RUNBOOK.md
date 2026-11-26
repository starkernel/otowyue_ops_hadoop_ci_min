# HDFS NameNode HA 平台侧执行手册

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


> 历史手册。文中“70 表”为 2026-11-09 窗口范围；最终为 **77 表**，当前状态见 [`CURRENT_STATE.md`](CURRENT_STATE.md)。

> **文档编号**：HODOOPFORGE-HA-HDFS-RUNBOOK-001  
> **日期**：2026-11-08  
> **适用**：qixuandata 集群（h0/h1/h2/h3，容器即主机）  
> **目标**：启用 `qixuandata` nameservice（2 NN + 3 JN + ZKFC），完成自动 failover，并同步 Spark/Hive 配置。  
> **配套**：`docs/HDFS_NN_HA_PLATFORM_REVIEW.md`、`ambarirpm/36-hdfs-nn-ha-cutover-runbook-2026-11-08.md`

---

## 一、范围与时间

| 项 | 内容 |
|---|---|
| 平台窗口 | **2026-11-08 21:00–23:00 CST** |
| 应用窗口 | 2026-11-09 04:00–04:30 CST（应用侧 70 表迁移） |
| 平台范围 | NN HA、JN、ZKFC、nameservice、checkpoint 目录、Spark/Hive 配置、快照、监控、failover 演练 |
| 应用范围 | 70 表 oldice→newice 重建、新 JAR、探针、回滚 |
| 停机影响 | HDFS 重启 10–20 分钟；Spark/Hive 重启 5–10 分钟；Flink checkpoint 可能 1–2 次失败 |

---

## 二、前置检查（窗口前 30 分钟）

```bash
# 1) HDFS 健康（应为 HEALTHY，0 corrupt/missing/under-replicated）
su -s /bin/bash hdfs -c "hdfs fsck / 2>&1" | grep -E "Status:|Corrupt blocks|Missing blocks|Under-replicated"

# 2) DataNode 3 台
su -s /bin/bash hdfs -c "hdfs dfsadmin -report 2>/dev/null" | grep -A5 "Live datanodes"

# 3) JN 端口空闲
for h in bigtop_hostname0 bigtop_hostname2 bigtop_hostname3; do
  docker exec $h bash -c "ss -ltn | grep ':8485' || echo '$h:8485 free'"
done

# 4) 当前配置
hdfs getconf -confKey fs.defaultFS
hdfs getconf -confKey dfs.nameservices
hdfs getconf -confKey dfs.ha.automatic-failover.enabled

# 5) 快照
su -s /bin/bash hdfs -c "hdfs dfs -ls /iceberg-warehouse/.snapshot"
```

**通过标准**：HDFS HEALTHY、3 DN、JN 端口空闲、快照存在。

---

## 三、配置备份

```bash
# HDFS 配置
docker exec bigtop_hostname0 bash -c \
  "tar czf /root/hadoop-conf-$(date +%Y%m%d%H%M).tgz /etc/hadoop/conf"

# Ambari HDFS 配置
curl -s -u "$AMBARI_USER:$AMBARI_PASS" -H 'X-Requested-By: ambari' \
  'http://localhost:20609/api/v1/clusters/qixuandata/configurations?type=hdfs-site' \
  > /root/ambari-hdfs-site-$(date +%Y%m%d%H%M).json

# 当前 NN 状态与 fsck
su -s /bin/bash hdfs -c "hdfs fsck / 2>&1" > /root/hdfs-fsck-before-ha.log
```

---

## 四、启用 NN HA

### 4.1 推荐：Ambari Enable HA 向导

1. Ambari → HDFS → **Actions → Enable HA**。
2. Nameservice ID：`qixuandata`。
3. NameNode 2：`bigtop-hostname1.bigtop.apache.org`。
4. JournalNode：`h0 / h2 / h3`（3 台）。
5. ZKFC：`h0 / h1`（与 NN 同机）。
6. 确认后执行；向导会：
   - 格式化 NN2；
   - 启动 3 个 JournalNode；
   - 启动 2 个 ZKFC；
   - 重启 HDFS。
7. 等待 Ambari 请求完成（约 10–20 分钟）。

> 若向导失败：不要手工继续，先按第七节回滚，再排查。

### 4.2 验证 nameservice

```bash
# 一 active 一 standby
su -s /bin/bash hdfs -c "hdfs haadmin -getServiceState nn1"
su -s /bin/bash hdfs -c "hdfs haadmin -getServiceState nn2"

# nameservice 可读
su -s /bin/bash hdfs -c "hdfs dfs -ls hdfs://qixuandata/"

# 容量/副本
su -s /bin/bash hdfs -c "hdfs dfsadmin -report 2>/dev/null" | head -20
```

**通过标准**：nn1/nn2 分别为 active/standby；`hdfs://qixuandata/` 可读；3 DN。

### 4.3 创建 Flink checkpoint 目录

```bash
su -s /bin/bash hdfs -c "
  hdfs dfs -mkdir -p hdfs://qixuandata/flink-checkpoints/edulake
  hdfs dfs -chmod 1777 hdfs://qixuandata/flink-checkpoints/edulake
  hdfs dfs -chown flink:hadoop hdfs://qixuandata/flink-checkpoints/edulake
  hdfs dfs -ls hdfs://qixuandata/flink-checkpoints/
"
```

---

## 五、Spark / Hive 配置同步

> 目标：应用侧 Spark ThriftServer / Hive 使用 nameservice；**不要求**本窗口内把 HBase/YARN 全部切到 nameservice（它们可继续通过 NN1 旧 authority 访问）。

### 5.1 Spark ThriftServer

在 Ambari `spark-defaults`（或 `/etc/spark/conf/spark-defaults.conf`）设置：

```properties
spark.hadoop.fs.defaultFS=hdfs://qixuandata
spark.sql.catalog.iceberg.warehouse=hdfs://qixuandata/iceberg-warehouse
```

重启 Spark ThriftServer（h1）。

验证：

```bash
beeline -u 'jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/default;transportMode=binary' -n spark \
  -e "SET spark.hadoop.fs.defaultFS; SET spark.sql.catalog.iceberg.warehouse;"
```

### 5.2 Hive

在 Ambari `hive-site`（或 `/etc/hive/conf/hive-site.xml`）增加/覆盖：

```xml
<property>
  <name>fs.defaultFS</name>
  <value>hdfs://qixuandata</value>
</property>
```

重启 HiveServer2 / HiveMetastore。

验证：

```bash
beeline -u 'jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default' -n hive \
  -e "SET fs.defaultFS;"
```

> 若 Hive 仍显示旧 authority，检查 `core-site.xml` 是否 `final=true` 覆盖；必要时在 `hive-site.xml` 中显式覆盖，或安排全局 `core-site` 切换（单独窗口）。

---

## 六、快照与旧仓库保留

```bash
# 窗口前/切换前新鲜快照
su -s /bin/bash hdfs -c \
  "hdfs dfs -createSnapshot /iceberg-warehouse pre_app_cutover_20261109"

# 旧仓库仍可读（NN1 保持 Active）
su -s /bin/bash hdfs -c \
  "hdfs dfs -ls hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse | head"
```

**通过标准**：快照创建成功；旧路径可读；旧 catalog 不删除。

---

## 七、Failover 演练

```bash
# 手动切换（推荐，可控）
su -s /bin/bash hdfs -c "hdfs haadmin -failover nn1 nn2"
su -s /bin/bash hdfs -c "hdfs haadmin -getServiceState nn1"
su -s /bin/bash hdfs -c "hdfs haadmin -getServiceState nn2"

# 读写验证
su -s /bin/bash hdfs -c "hdfs dfs -ls hdfs://qixuandata/"
su -s /bin/bash hdfs -c "echo test | hdfs dfs -put - hdfs://qixuandata/tmp/ha_failover_test"
su -s /bin/bash hdfs -c "hdfs dfs -rm hdfs://qixuandata/tmp/ha_failover_test"

# 切回
su -s /bin/bash hdfs -c "hdfs haadmin -failover nn2 nn1"
```

**通过标准**：切换 <30 秒；切换后读写正常；切回正常。

> 也可用 `docker stop h0` 做整机故障注入，但会同时停掉 NN1/RM/HMS/HS2/Kafka/JM 等；建议在应用窗口后再做整容器演练，本窗口先用 `haadmin -failover`。

---

## 八、监控告警（H8）

| 指标 | 方式 |
|---|---|
| NN active/standby | Ambari HDFS HA 告警 + `hdfs haadmin -getServiceState` |
| JN 状态 | Ambari JournalNode 告警 |
| ZKFC 状态 | Ambari ZKFC 告警 |
| nameservice 可读 | Prometheus blackbox / 定时脚本 |
| HDFS 容量/副本 | Ambari HDFS 告警 + `fsck` |
| failover 事件 | Ambari 告警历史 + 日志 |

建议增加 cron/blackbox：

```bash
su -s /bin/bash hdfs -c "hdfs dfs -ls hdfs://qixuandata/ >/dev/null" || echo "NAMESERVICE DOWN"
```

---

## 九、回滚

### 9.1 平台回滚（NN HA 启用失败）

1. Ambari → HDFS → **Actions → Disable HA**（若向导失败，先停 ZKFC/JN）。
2. 恢复 `/etc/hadoop/conf` 备份。
3. 重启 HDFS。
4. 验证旧 `hdfs://bigtop-hostname0...:8020` 可读写。
5. 恢复 Spark/Hive 旧配置并重启。
6. 记录事件与 MTTR。

### 9.2 应用回滚（70 表迁移失败）

1. 应用执行 `hdfs_ha_cutover.sh rollback`：停新 Flink，提交旧 JAR。
2. 平台把 Spark/Hive `fs.defaultFS` 与 catalog warehouse 切回旧 authority。
3. 验证旧表可读写、Flink checkpoint 恢复。
4. 旧 catalog/旧表保留，不删除。

### 9.3 数据回滚

- 快照：`pre_nn_ha_20261109` / `pre_app_cutover_20261109`。
- 旧仓库路径保持可读；不删除旧表。
- 如需恢复：`hdfs dfs -cp /iceberg-warehouse/.snapshot/<snap>/...` 到目标路径（谨慎，先评估）。

---

## 十、窗口执行清单

### 11-08 20:00–20:30 预检

- [ ] HDFS HEALTHY / 3 DN / JN 端口空闲
- [ ] 配置备份
- [ ] 快照 `pre_nn_ha_20261109` 存在
- [ ] 应用侧 standby 确认

### 11-08 21:00–22:30 启用 HA

- [ ] Ambari Enable HA 完成
- [ ] `hdfs haadmin -getServiceState nn1/nn2` = active/standby
- [ ] `hdfs://qixuandata/` 可读
- [ ] 3 DN 正常

### 11-08 22:30–23:00 配置与演练

- [ ] `/flink-checkpoints/edulake` 1777
- [ ] Spark/Hive 配置同步并重启
- [ ] `haadmin -failover` 演练 <30s
- [ ] 监控告警生效
- [ ] 旧仓库可读
- [ ] 快照 `pre_app_cutover_20261109`

### 11-09 03:30 最终预检

- [ ] nameservice/旧路径均可读
- [ ] 新鲜快照
- [ ] 应用侧准备就绪

### 11-09 04:00–04:30 应用切换

- [ ] 应用 cancel Flink / 迁移 70 表 / 提交新 JAR
- [ ] 3 sink RUNNING + checkpoint≥1
- [ ] 探针入湖、ODS 无重复
- [ ] 证据记录

### 11-09 04:30–05:00 缓冲/回滚

- [ ] 失败则执行应用回滚 + 平台配置回滚
- [ ] 记录 MTTR

---

## 十一、验收对照

| 编号 | 验收项 | 平台动作 |
|---|---|---|
| H1 | nameservice 可读 | `hdfs dfs -ls hdfs://qixuandata/` |
| H2 | 2 NN + 3 JN + ZKFC | `haadmin -getServiceState` |
| H3 | 自动 failover | `haadmin -failover` <30s |
| H4 | checkpoint 目录 | `mkdir/chmod 1777` |
| H5 | 旧仓库可读 | 旧 authority 访问 |
| H6 | 快照 | `pre_nn_ha_20261109` / `pre_app_cutover_20261109` |
| H7 | Spark/Hive 配置 | warehouse + fs.defaultFS |
| H8 | 监控告警 | Ambari + blackbox |

---

## 十二、关联文档

- `docs/HDFS_NN_HA_PLATFORM_REVIEW.md`
- `ambarirpm/37-data-lake-platform-ha-handoff-2026-11-08.md`
- `ambarirpm/36-hdfs-nn-ha-cutover-runbook-2026-11-08.md`
- `docs/PRODUCTION_HA_UPGRADE_PLAN.md`
