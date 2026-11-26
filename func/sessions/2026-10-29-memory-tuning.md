# 阶段总结：JVM 堆内存全量调优（2026-10-29）

> ⚠️ **重要说明**：本文记录的是**第一次**调优——直接修改容器内 `/etc/*/conf` 文件。
> 该方式在 Ambari 重新渲染配置时**被覆盖**，进程 Xmx 未真正生效。
> **正式生效的方案见 [`2026-10-29-t014-ambari-config-tuning.md`](./2026-10-29-t014-ambari-config-tuning.md)**（通过 Ambari 配置中心）。
> 本文保留作为"直接改文件为何无效"的教训记录。

## 1. 背景

- 宿主机约 40GB 内存 / 8GB Swap，4 个容器共享宿主机内存视图。
- h0 承载近 20 个 Java 服务（NN/RM/HBase Master/Hive/Ranger×3/Kafka/Solr/Spark HS/Flink JM/AMS/Ambari Server/ZK/...），
  调优前 Java 堆总量约 23GB，加上 off-heap/元空间/页缓存，系统 `used ≈ 33.5GB`、`available ≈ 5GB`、
  **Swap 8.2GB 100% 用尽**、Load 9.5+。
- 后果：Ambari Agent 检查脚本执行缓慢 → 检查超时 → `zookeeper_server_process`/`ranger_admin_process`
  误报 CRITICAL；Flink/Kafka 实际运行但状态长期 INSTALLED。

## 2. 动作

### 2.1 配置文件修改（容器内）

| 服务 | 旧 Xmx | 新 Xmx | 文件 |
|---|---|---|---|
| NameNode | 2048m | 1536m | `/etc/hadoop/conf/hadoop-env.sh` |
| SecondaryNameNode | 2048m | 1536m | 同上 |
| DataNode | 1024m | 512m | 同上 |
| ResourceManager | 2048m | 1536m | `/etc/hadoop/conf/yarn-env.sh` |
| NodeManager | 2048m | 1024m | 同上 |
| AppTimelineServer | 2048m | 512m | 同上 |
| JobHistoryServer | 1024m | 512m | `/etc/hadoop/conf/mapred-env.sh` |
| HBase Master | 1536m | 1024m | `/etc/hbase/conf/hbase-env.sh` |
| HBase RegionServer | 3072m | 2048m | 同上 |
| HiveServer2 | 2048m | 1024m | `/etc/hive/conf/hive-env.sh` |
| HiveMetaStore | 1024m | 512m | 同上 |
| Ranger Admin | 1g | 768m | `/usr/lib/ranger-admin/ews/ranger-admin-services.sh` |
| Ranger Usersync | 1g | 512m | `.../ranger-usersync-services.sh` + `conf/ranger-usersync-env.sh` |
| Ranger KMS | 1g | 512m | `/usr/lib/ranger-kms/ranger-kms` + `conf/ranger-kms-env.sh` |
| Ambari Server | 2048m | 1024m | `/var/lib/ambari-server/ambari-env.sh` |
| Infra Solr | 2048m | 1024m | `/usr/lib/ambari-infra-solr/bin/solr.in.sh` |
| Zookeeper | 1000m | 512m | `/etc/zookeeper/conf/zookeeper-env.sh` |
| Flink JobManager | 1024m | 512m | `/etc/flink/conf/flink-conf.yaml` |

> 所有文件已备份至各容器 `/root/jvm-config-backup-<timestamp>/`。

### 2.2 生效方式

- 通过 Ambari API `PUT STARTED` 只更新状态，**不会重启进程**；必须重启进程/容器。
- h0 执行 `docker restart bigtop_hostname0`（因 systemd 未响应 SIGTERM，最终 `docker kill` + `docker start`）。
- 容器重启后需**手工拉起**：MySQL → Ambari Server → Ambari Agent（三者未随容器自启）。

### 2.3 重启后服务恢复

- 受控启动顺序：ZK → NN → RM → HBase Master → 其他。
- 部分服务通过 Ambari API 启动时代理正常，但 `HiveServer2` 曾出现 Derby 回退（首次手工启动路径不完整）；
  通过 Ambari 正常启动后使用 **MySQL** 元数据库，10000 端口正常。
- AMS Collector 需显式 `JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.432.b06-2.el8.x86_64` 才能启动。

## 3. 结果

| 指标 | 调优前 | 调优后 | 变化 |
|---|---|---|---|
| Mem used | 33.5 GB | 23.3 GB | **-10.2 GB** |
| Mem available | 5.0 GB | 15.2 GB | **+10.2 GB** |
| Swap used | 8.2 GB (100%) | 4.6 GB (56%) | **-3.6 GB** |
| Ambari 告警 | 2 CRITICAL + 若干 UNKNOWN | **82/82 OK** | 归零 |

## 4. 根因与经验

1. **不要假设"小集群就该给每个服务 1-2G"**：很多服务（Usersync/KMS/TimelineReader/JobHistory/RegistryDNS）
   512m 甚至 256m 足够；堆总量才是内存压力的主因。
2. **Swap 100% 是连锁反应源头**：内存不足 → 检查脚本慢 → Ambari 超时误报 → 运维误判。
3. **Ambari PUT 不等于重启**：状态变更需配合真实进程重启。
4. **容器重启不等于服务自启**：MySQL/Ambari Server/Agent 需显式启动，建议后续做开机自启编排。
5. **Hive 元数据库是 MySQL**，Derby 仅是 classpath 依赖；不要被启动日志中的 derby jar 误导。

## 5. 遗留项

| 项 | 优先级 | 说明 |
|---|---|---|
| JVM 配置持久化 | P1 | 当前在容器内，重建容器会丢失；需写入镜像/初始化脚本 |
| 组件 watchdog | P1 | 防止服务宕机后长时间不恢复 |
| Swap 监控 | P1 | 阈值 80% 告警 |
| h1-h3 容器重启 | P2 | 应用 DN/NM 新配置（当前仍为旧堆） |
| AMS/Grafana 自启 | P2 | 手工部署，未纳入 Ambari |
