# 性能基线与指标（PERFORMANCE BASELINE）

> 记录各阶段的内存 / JVM / 端口 / 负载基线，便于回归对比。
> 最后更新：2026-10-29（内存调优后）

## 1. 宿主机与容器内存基线

| 时间 | 场景 | Mem total | Mem used | Mem available | Swap used | Load(1m) |
|---|---|---|---|---|---|---|
| 2026-10-28 | 调优前（h0 重启前） | 39.5 GB | **33.5 GB** | **5.0 GB** | **8.2 GB (100%)** | 9.5+ |
| 2026-10-29 | 容器重启后（文件修改，被覆盖） | 39.5 GB | 33.7 GB | 4.8 GB | 59% | — |
| 2026-10-29 | **T-014 通过 Ambari 配置中心生效后** | 39.5 GB | **28.5 GB** | **10.0 GB** | **43%** | — |
| 目标 | 稳态 | 39.5 GB | < 26 GB | > 12 GB | < 4 GB | < 6 |

> 说明：4 个容器共享宿主机内存视图（`/proc/meminfo` 相同），docker-compose 的 `mem_limit`
> 在 cgroup v1 下不体现在容器内 free 输出中。Swap 100% 是 Ambari 检查超时误报的根因。

## 2. JVM 堆内存基线（h0 核心节点）

| 服务 | 调优前 Xmx | 调优后 Xmx | 配置文件 | 状态 |
|---|---|---|---|---|
| NameNode | 2048m | **1536m** | `/etc/hadoop/conf/hadoop-env.sh` | 已生效 |
| SecondaryNameNode | 2048m | **1536m** | 同上 | 已生效 |
| DataNode | 1024m | **512m** | 同上 | 已生效 |
| ResourceManager | 2048m | **1536m** | `/etc/hadoop/conf/yarn-env.sh` | 已生效 |
| NodeManager | 2048m | **1024m** | 同上 | 已生效 |
| AppTimelineServer | 2048m | **512m** | 同上 | 已生效 |
| JobHistoryServer | 1024m | **512m** | `/etc/hadoop/conf/mapred-env.sh` | 已生效 |
| HBase Master | 1536m | **1024m** | `/etc/hbase/conf/hbase-env.sh` | 已生效 |
| HBase RegionServer | 3072m | **2048m** | 同上 | 已生效 |
| HiveServer2 | 2048m | **1024m** | `/etc/hive/conf/hive-env.sh` | 已生效 |
| HiveMetaStore | 1024m | **512m** | 同上 | 已生效 |
| Ranger Admin | 1g | **768m** | `/usr/lib/ranger-admin/ews/ranger-admin-services.sh` | 已生效 |
| Ranger Usersync | 1g | **512m** | `/usr/lib/ranger-usersync/ranger-usersync-services.sh` + `conf/ranger-usersync-env.sh` | 已生效 |
| Ranger KMS | 1g | **512m** | `/usr/lib/ranger-kms/ranger-kms` + `conf/ranger-kms-env.sh` | 已生效 |
| Ambari Server | 2048m | **1024m** | `/var/lib/ambari-server/ambari-env.sh` | 已生效 |
| Ambari Infra Solr | 2048m | **1024m** | `/usr/lib/ambari-infra-solr/bin/solr.in.sh` (`SOLR_HEAP`) | 已生效 |
| Kafka Broker | 1g | 1g | `/etc/kafka/conf/` | 保持 |
| Flink JobManager | ~448m | **512m** | `/etc/flink/conf/flink-conf.yaml` (`jobmanager.memory.process.size`) | 已生效 |
| Zookeeper | 1000m | **512m** | `/etc/zookeeper/conf/zookeeper-env.sh` | 待进程重启（zkEnv 优先级） |
| AMS Collector | 512m | 512m | `/etc/ambari-metrics-collector/conf/ams-env.sh` | 保持 |
| RegistryDNS | 1024m | **256m** | 启动脚本参数 | 待确认 |

> 备份位置：各容器 `/root/jvm-config-backup-<timestamp>/`

## 2.5 Flink 实时链路资源（2026-11-03）

| 项 | 值 |
|---|---|
| JM | h0，process size 1024m |
| TM | 2 个（h2 + h3），各 2 slots × 2048m |
| 总 slots | 4 |
| Checkpoint | 20s，EXACTLY_ONCE，RocksDB，`/flink-checkpoints/edulake` |
| 作业 | 1 个 RUNNING（3 Sink：LLM / RAG / AnswerSample） |
| Kafka lag | 0 |
| 时区 | Asia/Shanghai |

## 3. 关键端口基线

| 服务 | 节点 | 端口 | 期望 |
|---|---|---|---|
| ZooKeeper | h0/h1/h2 | 2181 | LISTEN |
| NameNode | h0 | 8020 / 50070 | LISTEN |
| DataNode | h1/h2/h3 | 50010 / 50075 | LISTEN |
| ResourceManager | h0 | 8088 / 8050 | LISTEN |
| NodeManager | h1/h2/h3 | 8042 | LISTEN |
| HBase Master | h0 | 16000 / 16010 | LISTEN |
| HBase RS | h3 | 16020 / 16030 | LISTEN |
| HiveServer2 | h0 | 10000 / 10002 | LISTEN |
| HiveMetaStore | h0 | 9083 | LISTEN |
| Ranger Admin | h0 | 6080 | LISTEN |
| Ranger KMS | h0 | 9292 | LISTEN |
| Infra Solr | h0 | 8886 | LISTEN |
| Kafka | h0 | 9092 | LISTEN |
| Spark HS | h0 | 18081 | LISTEN |
| Spark Thrift | h1 | 10016 | LISTEN |
| Flink JM | h0 | 8081 / 6123 | LISTEN |
| AMS Collector | h0 | 6188 | HTTP 200 |
| Grafana | h0 | 3000 | HTTP 200 |
| TimelineReader | h0 | 8198 | LISTEN |
| MapReduce HS | h0 | 19888 | LISTEN |

## 4. 单服务吞吐/延迟目标（小型集群参考）

| 指标 | 目标 | 现状 |
|---|---|---|
| HDFS 顺序写 | > 100 MB/s | 待测 |
| HDFS 顺序读 | > 150 MB/s | 待测 |
| YARN 小作业调度延迟 | < 30 s | 待测 |
| Hive on Tez 简单查询 | < 60 s | 待测 |
| HBase 随机读 P99 | < 50 ms | 待测 |
| Kafka 生产者吞吐 | > 5 MB/s | 待测 |
| Spark Pi 作业 | < 2 min | 待测 |

> 上述吞吐指标需在 `uttest/` 的集成测试用例中补充实测数据。

## 5. 资源分配建议（40GB 宿主机，小型集群）

| 节点 | 内存上限 | 主要负载 | 建议 |
|---|---|---|---|
| h0 | 16g | NN/RM/HBase Master/Hive/Ranger/Kafka/Solr/Spark HS/Flink JM/AMS | 已降堆，保留页缓存 |
| h1 | 8g | DN/NM/SNN/ATS/Spark Thrift | 余量充足 |
| h2 | 7g | DN/NM/Flink TM | 余量充足 |
| h3 | 7g | DN/NM/HBase RS/Router | 余量充足 |

> 后续可选优化：将 Kafka Broker、Flink JobManager、Infra Solr 迁移至 h1/h2，进一步分散 h0 负载。
