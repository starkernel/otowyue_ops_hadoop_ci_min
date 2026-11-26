# HadoopForge × eduLake · 系统功能特性清单与落地执行跟踪表

> **状态提示（2026-11-26）**：本文为阶段材料；当前 Kafka 已切 SASL_PLAINTEXT/GSSAPI，
> 架构与客户端配置以 [`ARCHITECTURE.md`](ARCHITECTURE.md) / [`KAFKA_EXTERNAL_ACCESS.md`](KAFKA_EXTERNAL_ACCESS.md) 为准。


| 字段 | 值 |
|---|---|
| 文档编号 | HF-EDULAKE-ARCH-20261028 |
| 版本 | v1.0 |
| 状态 | **架构基线版**（基于 2026-10-28 实测） |
| 作者 | 系统架构视角 |

---

## 第一章 · 系统全景

### 1.1 总体定位

HadoopForge 是面向 eduLake（教育领域数据湖）的基础设施层，提供：

- **HDFS** — 分布式对象存储（Iceberg table format 的物理承载）
- **YARN** — 统一资源调度（Flink TM、Spark Thrift 运行时）
- **Zookeeper** — 分布式协调（3 节点法定人数）
- **HBase** — 宽表存储（预留，Ranger ATS v1 复用）
- **Hive** — 元数据管理 + JDBC 查询（Iceberg catalog）
- **Kafka** — 实时数据总线（eduLake 数据摄入）
- **Flink** — 流计算引擎（Kafka → Iceberg ETL）
- **Spark** — 交互式 SQL + 批处理
- **Ranger** — 安全治理（HDFS/HBase/Kafka 鉴权 + 审计日志）
- **Ambari** — 集群运维与监控
- **NAT** — 容器网络暴露（宿主机 192.168.0.60 ↔ 集群内 172.19.0.0/24）

### 1.2 eduLake 数据湖定位

| 层级 | 技术 | 内容 |
|---|---|---|
| 实时摄入 | Python bridge → Kafka | Kafka Connect（手动 standalone，可升级为分布式） |
| 实时计算 | Flink 1.20.1 SQL | Kafka Source → Iceberg Sink |
| 存储层 | HDFS 1.21 TB + Iceberg 1.11.0 | edulake_* DB × 6，表 × 25+ |
| 元数据 | Hive Metastore 4.0.1 (MySQL) | Iceberg HiveCatalog |
| 离线计算 | Spark Thrift (h1:10016) | 交互式 SQL 查询 |
| 向量检索 | Qdrant v1.12.1 (外部) | dense + sparse hybrid |
| 模型治理 | eduteacher_v1.0 | format=96% |
| 调度 | crontab 10 条 | 02:00~05:00 全链路 |
| 测试 | Python 22 脚本 | 108/109 通过 |

---

## 第二章 · HadoopForge 功能特性清单

### 2.1 基础设施层

| # | 功能特性 | 技术/实现 | 版本 | 状态 | 验证方式 |
|---|---|---|---|---|---|
| INF-01 | 分布式存储 HDFS | Hadoop FS + 3 DN | 3.3.6 | ✅ | `hdfs dfsadmin -report` |
| INF-02 | 高可用 NN (HA) | Active NN (h0) + 2NN (h1) | 3.3.6 | ✅ | `hdfs haadmin -getServiceState` |
| INF-03 | 资源调度 YARN | RM (h0) + NM ×3 (h1/h2/h3) | 3.3.6 | ✅ | RM WebUI / Ambari alerts |
| INF-04 | Zookeeper 法定人数 | 3 节点 quorum | 3.8.4 | ✅ | `zkCli.sh stat` + 端口 2181 |
| INF-05 | 集群运维 Ambari | Server (h0:8080) + Agent ×4 | 3.1.0 | ✅ | 13/13 services STARTED |
| INF-06 | 安全治理 Ranger | Admin + Usersync + KMS + Plugins | 2.7.0 | ✅ | Ranger UI 200 OK |
| INF-07 | Kerberos 安全模式 | — | — | ⚪ **未启用** | Ambari `kerberos_enabled=false` |
| INF-08 | 透明加密 HDFS | Ranger KMS + hadoop-kms | KMS 9292 | 🟡 **KMS 在但未配置 KEF** | KMS TCP OK |
| INF-09 | 外部访问 NAT | iptables PREROUTING+OUTPUT 双链 | V2.6 | ✅ | 23 个端口映射 |
| INF-10 | NAT 规则持久化 | iptables-persistent | — | 🔴 **未执行** | 需宿主机 `sudo bash scripts/setup-nat-forward.sh persist` |

### 2.2 计算引擎层

| # | 功能特性 | 技术 | 版本 | 状态 | 备注 |
|---|---|---|---|---|---|
| COMP-01 | Flink Standalone | JM+TM (h2:8081) | 1.20.1 | ✅ | 1 TM, 1 slot, 刚重启过 |
| COMP-02 | Flink SQL Gateway | sql-client.sh | 1.20.1 | ✅ | 可用 |
| COMP-03 | Flink Kafka Connector | flink-sql-connector-kafka | **3.4.0-1.20** | ✅ **本轮补齐** | 从 Maven Central 下载 |
| COMP-04 | Flink Iceberg Connector | iceberg-flink-runtime | 1.20-1.11.0 | ✅ | 预装 |
| COMP-05 | Flink Hive Connector | flink-sql-connector-hive | 3.1.3_2.12-1.20.1 | ✅ | 预装 |
| COMP-06 | Flink Checkpoint | — | — | 🟡 **未配置** | SQL 作业里需显式 `with ('checkpoint'='1min')` |
| COMP-07 | Flink HA | Standalone HA (ZooKeeper) | — | ⚪ **未启用** | 生产建议加，P2 |
| COMP-08 | Spark Thrift JDBC | HiveThriftServer2 (h1:10016) | Bigtop Spark | ✅ | 端口 LISTEN |
| COMP-09 | Spark History Server | JobHistoryServer (h0:18081) | — | ✅ | TCP OK |
| COMP-10 | Spark Connect | — | — | ⚪ **未启用** | P2 |

### 2.3 数据存储层

| # | 功能特性 | 技术 | 版本 | 状态 | 备注 |
|---|---|---|---|---|---|
| STO-01 | Iceberg Table Format | iceberg-core + HiveCatalog | 1.11.0 | ✅ | Hive Metastore 6 个 edulake DB |
| STO-02 | HBase 宽表 | Master (h0) + RS (h3) | 2.6.2 | 🟡 **RS 单点** | 1 RS 运行中，ZK SessionExpired 风险 |
| STO-03 | HBase 安全 Coprocessor | RangerAuthorizationCoprocessor | — | ✅ | 已启用 |
| STO-04 | HBase ZooKeeper Session | 默认 30000ms | — | 🔴 **有超时风险** | 改 120000ms 根治 |
| STO-05 | Hive Metastore (MySQL) | hive metastore DB | 4.0.1 | ✅ | `edulake_*` × 6 DB |
| STO-06 | Hive Server2 JDBC | 10000 | — | ✅ | Ambari alerts OK |

### 2.4 实时数据通路

| # | 功能特性 | 技术 | 版本 | 状态 | 备注 |
|---|---|---|---|---|---|
| REALT-01 | Kafka Broker 单节点 | broker (h0:9092) | 3.4.1 | ✅ | 7 topics（含 4 eduLake） |
| REALT-02 | Kafka Broker 监听地址 | `PLAINTEXT://bigtop-hostname0.bigtop.apache.org:9092` | — | 🟡 **不监听 localhost** | 所有 client 必须用 IP |
| REALT-03 | Kafka Connect Worker (Standalone) | connect-standalone.sh (h0:8083) | 3.4.1 | ✅ | PID 472270，8 个内置 connector |
| REALT-04 | Kafka Connect 外部 Connector | Confluent JDBC/Debezium | — | 🔴 **未安装** | 需要 fat jar 手动下载 |
| REALT-05 | Kafka Connect 持久化 | — | — | 🔴 **容器重启丢** | 需 entrypoint 脚本 |
| REALT-06 | Python Bridge | `kafka_to_iceberg_bridge` | — | 🟡 **Python 侧运行** | eduLake 侧管理 |

### 2.5 安全与治理

| # | 功能特性 | 技术 | 状态 | 备注 |
|---|---|---|---|---|
| SEC-01 | Ranger HDFS 鉴权 | Policy Admin + Plugins | ✅ | 正常运行 |
| SEC-02 | Ranger HBase 鉴权 | Authorization Coprocessor | ✅ | 已启用 |
| SEC-03 | Ranger Kafka 鉴权 | kafka-plugin-impl | ✅ | broker classpath 含 ranger-kafka-plugin |
| SEC-04 | Ranger Audit | HDFS AuditDestination | 🟡 | 写入 HDFS /ranger/audit，h1/h3 DN 健康 |
| SEC-05 | Ranger Usersync | UnixAuthenticationService | ✅ | 5151 TCP OK |
| SEC-06 | Ranger KMS | Embedded Tomcat :9292 | ✅ | 端口 OK |
| SEC-07 | Ambari Admin | 已轮换（2026-11-20） | ✅ | 凭据存 `/etc/hodoopforge/ambari.env`（600），不再使用默认密码 |
| SEC-08 | SELinux/AppArmor | 容器内核隔离 | 🟡 | 宿主机禁用 |

### 2.6 网络架构

| # | 功能特性 | 技术 | 状态 | 备注 |
|---|---|---|---|---|
| NET-01 | 容器 overlay 网络 | Docker bridge 172.19.0.0/24 | ✅ | 4 节点互通 |
| NET-02 | PREROUTING DNAT | iptables NAT | ✅ | 47 条规则（所有 LAN → 容器） |
| NET-03 | OUTPUT DNAT | iptables NAT | ✅ | 47 条（宿主机自身 → 容器） |
| NET-04 | MASQUERADE | `-s 172.19.0.0/24 ! -d 172.19.0.0/24` | ✅ | 出方向 NAT |
| NET-05 | 禁止转发 ZK 仲裁端口 | 2888/3888 排除 | ✅ | V2.6 脚本硬编码 |
| NET-06 | 禁止转发 DN 数据面 | 50010 排除 | ✅ | 防宿主机绕过安全策略直连 DN |
| NET-07 | Ambari 20609 端口 | NAT 到 8080 | ✅ | 宿主机访问 OK |
| NET-08 | NAT 持久化 | — | 🔴 | 需宿主机 sudo persist |

---

## 第三章 · eduLake 功能特性清单

| # | 功能域 | 具体能力 | 依赖组件 | 状态 |
|---|---|---|---|---|
| EDU-01 | 数据摄入 | 学习事件实时采集 | Python → Kafka learning_events | ✅ |
| EDU-02 | 数据摄入 | 推理日志实时采集 | Python → Kafka ai_inference_log | ✅ |
| EDU-03 | 数据摄入 | RAG 查询日志 | Python → Kafka rag_query_log | ✅ |
| EDU-04 | 数据摄入 | 学生画像更新 | Python → Kafka student_profile_updates | ✅ |
| EDU-05 | 实时 ETL | Kafka → Iceberg 管道 | Flink SQL + kafka connector + iceberg sink | 🟡 **提交前等待 Flink SQL** |
| EDU-06 | 存储 ODS 层 | 原始事件表 | Iceberg (edulake_*) | ✅ |
| EDU-07 | 存储 DWD 层 | 清洗宽表 | Iceberg | ✅ |
| EDU-08 | 存储 DWS 层 | 聚合汇总表 | Iceberg | ✅ |
| EDU-09 | 存储 ADS 层 | 应用场景表 | Iceberg | ✅ |
| EDU-10 | 数据治理 | 元数据管理 | Hive Metastore | ✅ |
| EDU-11 | 数据治理 | 22 个 Python 脚本语法检查 | edulake 侧 | ✅ |
| EDU-12 | 数据治理 | 10 条 crontab 02~05 调度 | edulake 侧 | ✅ |
| EDU-13 | 向量检索 | Qdrant dense+sparse hybrid | Qdrant 1.12.1 (外部) | ✅ |
| EDU-14 | 模型治理 | eduteacher_v1.0 | edulake 侧 | ✅ |
| EDU-15 | 测试覆盖 | 108/109 (99.1%) | edulake 侧 | ✅ |

---

## 第四章 · 落地执行跟踪表

### 4.1 HadoopForge 基础设施（按优先级）

| ID | 任务 | 优先级 | 负责人 | 前置条件 | 依赖项 | 交付物 | 风险 | 状态 | 2026-10-28 进展 |
|---|---|---|---|---|---|---|---|---|---|
| HF-01 | **NAT persist** | P0 | 宿主机 sudo | — | setup-nat-forward.sh V2.6 已 apply | 持久化 iptables 规则 | 宿主机重启丢规则 | 🔴 待执行 | 脚本已就绪，`sudo bash scripts/setup-nat-forward.sh persist` |
| HF-02 | **Flink auto-start** | P0 | 架构师 | docker-entrypoint.d 机制 | Flink 1.20.1 可正常 start-cluster.sh | 容器重启自动拉起 Flink | 容器重启丢进程 | 🔴 待执行 | Flink 已手动拉起（1 TM 1 slot） |
| HF-03 | **Connect auto-start** | P0 | 架构师 | docker-entrypoint.d | Connect 已验证可启动 | 容器重启自动拉起 Connect Standalone | 容器重启丢 PID | 🔴 待执行 | Connect PID 472270 还在 |
| HF-04 | **HBase ZK timeout 调优** | P1 | 运维 | hbase-daemon.sh stop/start RS | hbase-site.xml | `zookeeper.session.timeout=120000` | 改完 RS 需重启 | 🟡 待执行 | RS 刚手动拉起，SessionExpired 是反复 abort 根因 |
| HF-05 | **HBase 多 RS 冗余** | P1 | 运维 | Ambari 支持 | BIGTOP 3.5.0 HBASE_REGIONSERVER 组件定义 | 3 RS 运行中 | stack 3.5.0 可能有 bug | 🟡 待执行 | 当前 RS 在 h3 单点 |
| HF-06 | **Kafka Connect 外部 JDBC/Debezium** | P1 | 开发 | 外部 fat jar | Maven Central 可联网 | `/usr/lib/kafka/plugins/jdbc/` 目录 | 下载错误会崩 broker | 🟡 待执行 | Maven Central + Confluent 仓库都通 |
| HF-07 | **Kafka Broker 多副本** | P1 | 运维 | 3 节点部署 | KAFKA_INTERNAL 多 broker | 3 broker quorum | 单 broker 数据丢 | 🟡 待评估 | 当前单节点，但 eduLake 数据非核心 |
| HF-08 | **Ambari 默认密码** | P1 | 运维 | — | — | admin/amb_ranger_admin 改强密码 | 安全风险 | 🔴 待执行 | 当前默认密码 admin/admin |
| HF-09 | **HiveServer2 HA** | P2 | 运维 | HAProxy/F5 | — | HAProxy 配置 | JDBC 连接串变更 | 🟢 低优先 | 当前单实例可用 |
| HF-10 | **HBase HA（备份 Master）** | P2 | 运维 | Ambari HBASE_MASTER standby 组件 | — | 1 active + 1 backup | 已配置但 Ambari 未跟踪 | 🟢 低优先 | 当前状态 1 active master |
| HF-11 | **Flink HA** | P2 | 架构师 | Standalone HA + ZK | `execution.high-availability: zookeeper` | Flink 作业 HA 元数据存 ZK | 配置复杂 | 🟢 低优先 | 无 HA 但作业简单 |
| HF-12 | **Kerberos 启用** | P3 | 安全 | KDC + keytab + principal | 所有组件需要重新配置 | 端到端安全 | 大改动 | ⚪ 规划中 | 当前关闭 |
| HF-13 | **Ranger KEF 启用** | P3 | 安全 | 透明加密配置 | HDFS 新数据自动加密 | 合规需要 | 性能影响 + 配置复杂 | ⚪ 规划中 | KMS 存在但 KEF 未开 |
| HF-14 | **JMX Exporter** | P3 | 运维 | — | Prometheus 可用 | Prometheus 监控接入 | 环境依赖 | ⚪ 规划中 | 当前 Ambari metrics server |
| HF-15 | **宿主机 swap 监控** | P2 | 运维 | — | 告警脚本 | swap > 80% 告警 | h0 已 20GB | 🟢 低优先 | 宿主机资源紧张 |

### 4.2 eduLake 数据湖（按阶段）

| ID | 阶段 | 任务 | 优先级 | 前置条件 | 依赖项 | 交付物 | 状态 | 2026-10-28 进展 |
|---|---|---|---|---|---|---|---|---|
| EDU-01 | 阶段 1 | Kafka → Iceberg 实时管道（P2 Flink SQL） | **P0** | Flink Kafka connector 就位 | Flink 1.20.1 + kafka + iceberg | `edulake_flink_jobs.sql` | 🟡 提交前 | **Kafka connector 本轮补齐** |
| EDU-02 | 阶段 1 | python bridge 停止（Flink 接管后） | P2 | EDU-01 稳定运行 | — | `pkill -f kafka_to_iceberg_bridge` | 🔴 待执行 | 脚本里已包含 |
| EDU-03 | 阶段 1 | Flink Checkpoint + Savepoint 配置 | P1 | EDU-01 跑起来 | `with ('checkpoint'='1min')` | Checkpoint S3/HDFS 路径 | 🟡 设计中 | SQL 模板可加 |
| EDU-04 | 阶段 2 | Qdrant embedding pipeline | P1 | eduLake 向量侧 | Qdrant v1.12.1 | embedding 生成脚本 | 🟡 进行中 | dense+sparse hybrid 就绪 |
| EDU-05 | 阶段 2 | Retriever + Rag 集成 | P1 | EDU-04 | — | API endpoint | 🟡 进行中 | — |
| EDU-06 | 阶段 2 | 离线分析 Spark Notebook | P2 | Spark Thrift | Jupyter + %spark magic | notebook 交付 | 🟢 规划中 | Spark Thrift 4040 已通 |
| EDU-07 | 阶段 3 | 数据质量监控 | P2 | 全链路跑通 | Great Expectations / dbt | dbt tests | 🟢 规划中 | 22 Python 脚本已通过语法检查 |
| EDU-08 | 阶段 3 | 元数据血缘（Lineage） | P3 | — | Atlas / OpenLineage | 血缘 UI | ⚪ 远期 | — |
| EDU-09 | 阶段 3 | API 网关 + Auth | P3 | EDU-05 | — | 网关鉴权 | ⚪ 远期 | — |

---

## 第五章 · 依赖关系图

### 5.1 eduLake 依赖 HadoopForge 的清单

| eduLake 组件 | 依赖 HadoopForge 组件 | 硬依赖 | 软依赖 | 版本/配置要求 |
|---|---|---|---|---|
| Python bridge → Kafka | Kafka Broker | ✅ | — | `172.19.0.2:9092`（不能用 localhost） |
| Flink SQL ETL | Flink Standalone | ✅ | — | 1.20.1 启动中 |
| Flink Kafka Source | Kafka connector jar | ✅ | — | 3.4.0-1.20（**本轮补齐**） |
| Flink Iceberg Sink | Iceberg connector jar | ✅ | — | 1.20-1.11.0（已就位） |
| Flink Iceberg Catalog | Hive Metastore + MySQL | ✅ | — | MySQL hive/hive + edulake_* DB |
| Flink Iceberg Sink | HDFS | ✅ | — | 1.21 TB, 3 DN |
| Flink Iceberg Sink | Zookeeper | ✅ | — | 3 节点 quorum |
| Qdrant (外部) | 无 | — | — | 外部服务 |
| crontab 调度 | Python 22 脚本 + Hive CLI | — | ✅ | 需 Hadoop conf 在 PATH |
| 测试脚本 | Hive Metastore + Kafka | ✅ | — | 连通性 OK |

### 5.2 版本兼容矩阵

| Flink 版本 | Kafka Connector 版本 | Iceberg Flink Runtime | 状态 |
|---|---|---|---|
| 1.20.1 | **3.4.0-1.20** ✅ | **1.20-1.11.0** ✅ | **就位** |
| 1.20.1 | 3.3.0-1.20 | 1.20-1.11.0 | 兼容但旧 |
| 1.19.x | 3.3.0-1.19 | 1.19-1.11.x | 不匹配当前 Flink |

**注意**：`flink-sql-connector-kafka` 3.4.0-1.20 是 Flink 1.20 官方推荐版本。下载 URL：
```
https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.4.0-1.20/flink-sql-connector-kafka-3.4.0-1.20.jar
https://repo1.maven.org/maven2/org/apache/flink/flink-connector-kafka/3.4.0-1.20/flink-connector-kafka-3.4.0-1.20.jar
```

### 5.3 Hive Metastore DB 命名规范

| DB | 用途 | 包含表数 |
|---|---|---|
| edulake_learning | 学习事件 ODS/DWD | 多 |
| edulake_knowledge | 知识库 RAG | 多 |
| edulake_ai | AI 推理日志 | 多 |
| edulake_user | 用户画像 | 多 |
| edulake_pronunciation | 发音纠正 | 多 |
| edulake_meta | 系统元数据/治理 | 多 |

---

## 第六章 · 2026-10-28 本轮变更速览

| 变更 | 类型 | 影响面 | 回滚 |
|---|---|---|---|
| ✅ 下载 Flink Kafka connectors (2 jar) | lib 补齐 | Flink 全作业 | 删除 jar + `start-cluster.sh` |
| ✅ 重启 Kafka broker（listeners 保持 hostname） | 服务维护 | 7 topics 保持 | 已恢复原 config |
| ✅ 手动拉起 HBase RS (h3) | 服务恢复 | 1 server 恢复 | 杀进程即可 |
| ✅ 重启 Flink Standalone | 服务维护 | 无作业丢失 | 重 start-cluster.sh |
| ✅ NAT 脚本 V2.6 （前置已 apply） | 网络 | 全部端口映射 | `setup-nat-forward.sh remove` |

**文件变动**：
- `/home/rkam/hadoop-ops-course/ambari3/scripts/setup-nat-forward.sh` — V2.6（前置，本轮只 apply 没改）
- `/home/rkam/hadoop-ops-course/docs/HADOOPFORGE_EDULAKE_TEST_REPORT.md` — **新建**
- `/home/rkam/hadoop-ops-course/docs/HADOOPFORGE_EDULAKE_FEATURES_TRACKING.md` — **新建（本文件）**

---

## 附录 · 状态图例

| 图标 | 含义 |
|---|---|
| ✅ | 已完成/就位/运行中 |
| 🟡 | 进行中/部分就位/有已知限制 |
| 🟢 | 规划中但优先级低 |
| 🔴 | 待执行/需要宿主机操作/硬依赖未满足 |
| ⚪ | 未规划/不需要 |

## 附录 · Kubernetes 对比（HadoopForge vs K8s）

作为架构参考，记录当前选择 Docker Compose 而非 K8s 的原因：

| 维度 | Docker Compose（当前） | Kubernetes |
|---|---|---|
| 资源 | 1 宿主机足够 | 至少 3 节点 |
| 运维复杂度 | Ambari + docker | Helm + Operators + Argo |
| Iceberg 元数据 | HiveCatalog（HDFS） | Nessie/Glue/DynamoDB（可选） |
| Kafka | 单节点够用 | 需要 3+ nodes |
| Flink | Standalone | Native K8s HA |
| 适合 | **eduLake P2 阶段，数据量小** | 生产化后考虑 |

**架构演进建议**：当 eduLake 日均数据 >100GB 或 QPS > 1000/s 时，考虑迁移 K8s + Flink Native K8s + Kafka 3 broker。
