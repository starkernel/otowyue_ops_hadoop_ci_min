# 文档索引

> 当前状态以 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准；交互地图：[`lake-map.html`](lake-map.html)。

## 1. 当前状态与地图

| 文档 | 说明 |
|---|---|
| [`CURRENT_STATE.md`](CURRENT_STATE.md) | 集群当前状态单一事实源（HA、Kerberos、Flink、告警、待办） |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | **当前架构总览**：拓扑、认证链路、HA、端口、防呆、回滚 |
| [`lake-map.html`](lake-map.html) | 可交互数据湖地图；**单文件自包含**，file:// 可直接打开 |
| [`lake-map-data.json`](lake-map-data.json) | 地图数据快照；`python3 scripts/gen_lake_map_data.py` 刷新 |

## 1.1 测试与 CI

| 文档 | 说明 |
|---|---|
| [`TEST_STRATEGY.md`](TEST_STRATEGY.md) | 测试分层、完整用例目录、准入/退出标准 |
| [`CI_CD.md`](CI_CD.md) | GitHub Actions、JUnit/Allure 报告、self-hosted live smoke |
| [`CI_QIXUAN_CLOUDBUILD.md`](CI_QIXUAN_CLOUDBUILD.md) | Qixuan CloudBuild（as.long.kim:12131）流水线、镜像同步与排障 |
| [`../uttest/README.md`](../uttest/README.md) | 历史手工测试矩阵与冒烟清单 |

## 2. 运维手册

| 文档 | 说明 |
|---|---|
| [`POST_SNAPSHOT_RUNBOOK.md`](POST_SNAPSHOT_RUNBOOK.md) | 快照后巡检与恢复 |
| [`OPERATIONS_AUTOMATION.md`](OPERATIONS_AUTOMATION.md) | 开机自愈 + 10 分钟巡检 + Kerberos guard（旧 60s watchdog 已停） |
| [`MONITORING_PROMETHEUS.md`](MONITORING_PROMETHEUS.md) | Prometheus/Alertmanager/exporters 部署、指标与告警规则 |
| [`MANAGEMENT_MODEL.md`](MANAGEMENT_MODEL.md) | 组件归属矩阵、启动顺序、变更规则与禁止事项 |
| [`MANAGEMENT_IMPROVEMENT_PLAN.md`](MANAGEMENT_IMPROVEMENT_PLAN.md) | 管理机制优化计划、验收标准与回滚 |
| [`REBUILD_RUNBOOK.md`](REBUILD_RUNBOOK.md) | 灾难重建、恢复演练与持久化卷迁移 |
| [`M-101_PILOT_REPORT.md`](M-101_PILOT_REPORT.md) | h2 小状态卷迁移试点结果与结论 |
| [`KERBEROS_ENABLEMENT.md`](KERBEROS_ENABLEMENT.md) | KDC/realm、数据面 Kerberos、Ambari 收口与回滚 |
| [`KERBEROS_GUARD.md`](KERBEROS_GUARD.md) | 手工 Kerberos 防呆守护、agent 锁定、keytab 快照 |
| [`KERBEROS_INCIDENT_2026-11-24.md`](KERBEROS_INCIDENT_2026-11-24.md) | Kerberos 启用失败、回滚与排障记录（历史） |
| [`HIVE_MYSQL_HA.md`](HIVE_MYSQL_HA.md) | HMS/HS2 HA、MySQL 主从与提升步骤 |
| [`HDFS_NN_HA_PLATFORM_RUNBOOK.md`](HDFS_NN_HA_PLATFORM_RUNBOOK.md) | HDFS NN HA 平台执行手册（历史，70 表为当时范围） |
| [`FLINK_OPS_RUNBOOK.md`](FLINK_OPS_RUNBOOK.md) | Flink 运维 |
| [`LAN_ACCESS_GUIDE.md`](LAN_ACCESS_GUIDE.md) | 局域网访问与端口 |

## 3. 近期修复

| 文档 | 说明 |
|---|---|
| [`WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md`](WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md) | 77 表 Location 对齐 `-ha`、Spark catalog 切换、批处理补跑 |
| [`INCIDENT_2026-11-18_HDFS_NN_RECOVERY.md`](INCIDENT_2026-11-18_HDFS_NN_RECOVERY.md) | HDFS 双 NN 停止 / HBase / Flink 恢复 |
| [`KAFKA_EXTERNAL_ACCESS.md`](KAFKA_EXTERNAL_ACCESS.md) | Kafka 外部 9092/9093/9094、advertised、NAT/hairpin |
| [`KAFKA_ADVERTISED_LISTENER_RATIONALE_2026-11-09.md`](KAFKA_ADVERTISED_LISTENER_RATIONALE_2026-11-09.md) | advertised listener 设计依据 |

## 4. HA 计划与历史报告

| 文档 | 说明 |
|---|---|
| [`PRODUCTION_HA_UPGRADE_PLAN.md`](PRODUCTION_HA_UPGRADE_PLAN.md) | 六项 HA 总方案与进度 |
| [`HA_PROGRESS_REPORT_2026-11-08.md`](HA_PROGRESS_REPORT_2026-11-08.md) | Kafka RF3 进展（历史） |
| [`HA_PROGRESS_REPORT_2026-11-09_HDFS_HA.md`](HA_PROGRESS_REPORT_2026-11-09_HDFS_HA.md) | HDFS NN HA 完成报告（历史） |
| [`HDFS_NN_HA_PLATFORM_REVIEW.md`](HDFS_NN_HA_PLATFORM_REVIEW.md) | 交接单平台评审（历史） |

## 5. 业务与验收

| 文档 | 说明 |
|---|---|
| [`HADOOPFORGE_EDULAKE_TEST_REPORT.md`](HADOOPFORGE_EDULAKE_TEST_REPORT.md) | 业务联通测试报告（历史） |
| [`HADOOPFORGE_EDULAKE_FEATURES_TRACKING.md`](HADOOPFORGE_EDULAKE_FEATURES_TRACKING.md) | 功能跟踪 |
| [`../datalake/evidence/2026-11-19-business-acceptance-platform.json`](../datalake/evidence/2026-11-19-business-acceptance-platform.json) | 业务验收平台侧证据 |
| [`../datalake/evidence/2026-11-19-warehouse-alignment.json`](../datalake/evidence/2026-11-19-warehouse-alignment.json) | 77 表对齐证据 |

## 6. 安全与规划

| 文档 | 说明 |
|---|---|
| [`KERBEROS_ENABLEMENT_PLAN.md`](KERBEROS_ENABLEMENT_PLAN.md) | 早期 Kerberos 计划（历史，已被 KERBEROS_ENABLEMENT 取代） |
| [`PLATFORM_TECH_USER_MANUAL.md`](PLATFORM_TECH_USER_MANUAL.md) | 平台技术手册 |
| [`manual/`](manual/) | 分章节手册（部分章节为 v3.0 历史，当前以 ARCHITECTURE.md 为准） |
