# 任务跟踪表（TASK TRACKER）

> 全项目任务单一来源。状态：`✅ 完成` / `🚧 进行中` / `⏳ 待办` / `❌ 取消` / `🔴 阻塞`
> 优先级：P0（最高）> P1 > P2
> 最后更新：2026-11-09

## 1. 当前迭代：集群健康收口（v1.0）

| ID | 任务 | 优先级 | 状态 | 关联 | 备注 |
|---|---|---|---|---|---|
| T-001 | AMS 栈恢复（ams-hbase + collector 6188） | P0 | ✅ | BUG-033 | 僵尸进程清理 + 重启 |
| T-002 | Ambari 8 组件 UNKNOWN 死锁修复 | P0 | ✅ | BUG-030 | 停 Server → DB 改 INSTALLED → 重启 |
| T-003 | 全服务端口/进程核对（31 项） | P0 | ✅ | — | 全部 ✅ |
| T-004 | 告警清零确认（82/82 OK） | P0 | ✅ | — | — |
| T-005 | 主机 HEALTHY 确认（4 台） | P0 | ✅ | — | — |

## 2. 待办任务（按优先级）

### P0 — 生产最小 HA（2026-11-08 新增）

| ID | 任务 | 状态 | 关联 | 说明 |
|---|---|---|---|---|
| T-061 | 容器内存上限调整 + 反亲和核对 | 🚧 | HA-001 M4-0 | 宿主机 +8GB；h1 10/h2 9/h3 9GB 已调整；反亲和核对待做 |
| T-062 | Kafka 3 broker（h0/h2/h3）+ RF3 + min.insync=2 | ✅ | HA-001 M4-1 | 2026-11-08 完成；停 h3 broker 验证 acks=all 不丢；systemd 自启 |
| T-063 | HDFS NN HA（NN1 h0 Active / NN2 h3 Standby + JN h0/h1/h3 + ZKFC） | ✅ | HA-001 M4-2 | 2026-11-09 完成；双向 failover、nameservice、旧/新路径均验证 |
| T-064 | HMS/HS2 HA（h0/h1 + h0/h3 + MySQL 主从） | ✅ | HA-001 M4-3 | HMS 双 URI；HS2 ZK 发现并演练；MySQL h0→h3 副本 + 提升脚本 |
| T-065 | Flink JM HA（JM1 h0 / JM2 h1 + ZK + HDFS） | ✅ | HA-001 M4-4 | JM2 systemd；ZK 选主；双向 failover 演练；作业从 savepoint 恢复 |
| T-066 | Kerberos/Ranger（KDC1 h0 / KDC2 h3 + keytab + 维护窗口） | ✅ | HA-001 M4-5 | HDFS/HBase/Hive/YARN/Flink/Kafka/Spark 已启用；Ambari security_type=KERBEROS；guard 锁 agent；ZK/Ranger/KMS/TLS 后续 |
| T-067 | Prometheus/Alertmanager HA + blackbox | ✅ | HA-001 M4-6 | 主备双实例 + AM 集群 + 统一查询代理；blackbox 未部署 |
| T-068 | 容器故障注入演练与验收（`docker stop`，RTO/RPO） | ⏳ | HA-001 M4-7 | 依赖 T-062~T-067 |
| T-069 | 修正 Iceberg 迁移路径冲突（newice 改独立 `-ha` 目录） | ✅ | HA-001 | 70/70 迁移完成；作业 bbf6360 RUNNING，3 sink，checkpoint 20s，探针 19s |
| T-070 | 备份 I/O 限流与窗口规范 | ✅ | BUG-045 | `backup_with_throttle.sh`（ionice -c3/nice）+ 每日 02:30 timer + 7 天保留 |
| T-071 | 清理 Ambari HA 向导持久化残留 | ✅ | BUG-047 | persist 重置为 `CLUSTER_INSTALLED_4`；登录/服务页不再跳 step9；脚本 `scripts/ambari_reset_ha_wizard.sh` |
| T-072 | v3.0 文档、截图与解说视频交付 | ✅ | DOC-v3.0 | 新增第 10 章；67 张截图；36 场景 6:26 Edge TTS 晓晓解说视频 |
| T-073 | Kafka 外部访问 9093/9094 + 三分区写入 | ✅ | KAFKA-EXT-002 | advertised listeners 修正为 192.168.0.60:9092/9093/9094；标准客户端 metadata 通过；30 条测试消息 offset 11/9/10；脚本 `scripts/kafka_external_listener.sh` |
| T-074 | 事故恢复：HDFS 双 NN 停止 + HBase/Flink 连带故障 | ✅ | BUG-048/049 | 2026-11-18 恢复；h3 Active / h0 Standby；HBase 1M1RS；Flink TM 2×8 slot、作业 42c0 RUNNING |
| T-075 | Ambari 浏览器 localStorage 残留自愈 | ✅ | BUG-050 | index.html 注入脚本 + `scripts/fix_ambari_ha_wizard.sh`；旧 Tab 不再回跳 step9 |
| T-076 | NameNode/TM watchdog 与 CRITICAL 告警升级 | ⏳ | BUG-048 | 60s 探活自动拉起；CRITICAL 30min 未恢复电话/IM 通知 |
| T-077 | Warehouse 分叉修复：77 表 Location 对齐 `-ha` | ✅ | WAREHOUSE-ALIGN-001 | 补齐 7 表；Spark catalog 切 `-ha`；`check_lake_alignment.py` 77/77；旧仓库保留回滚；批处理补跑待业务 |
| T-078 | 外部 Kafka + NAT/hairpin 自动化 | ✅ | KAFKA-EXT-003 / OPS-AUTO-001 | 9093/9094、advertised、hairpin；开机自愈 + 10min 巡检 |
| T-079 | 数据湖交互地图与文档一致性 | ✅ | DOC-MAP-001 | `docs/lake-map.html` + `lake-map-data.json` + `CURRENT_STATE.md`；历史文档加注 |
| T-080 | 测试体系与 GitHub CI（pytest + JUnit + Allure） | ✅ | CI-TEST-001 | `tests/` 覆盖 L1~L3；`ci.yml` 自动跑；`docs/TEST_STRATEGY.md` 全量用例目录 |
| T-081 | 全量告警恢复与耐久性对齐（2026-11-20） | ✅ | INCIDENT-2026-11-20 | HDFS/HBase/Kafka 恢复；97/97 OK；Kafka minISR=2；日志清理与保留策略 |
| T-082 | NameNode/TM watchdog + CRITICAL 升级 | ✅ | T-076 | 60s watchdog 已上线，覆盖 HDFS/HBase/Kafka/Flink/Spark/监控；电话/IM 升级待接 |
| T-083 | Prometheus/Alertmanager + exporters | ✅ | MON-001 | h1 主 + h2 备；10/10 targets；13 条规则；watchdog 兜底 |
| T-084 | 监控 HA 与告警通知闭环 | ✅ | MON-003/004 | Alertmanager 集群、failover.sh、webhook 落盘/转发、Grafana 数据源 |
| T-085 | 监控统一查询代理 + Grafana 面板 | ✅ | MON-005 | h2 `prom_proxy` :9099（NAT 19099）；数据湖总览面板 |
| T-086 | 管理面加固（容器自启/管理面自启/watchdog/漂移/指标） | ✅ | MGMT-001 | `hodoopforge-containers`、restart policy、Ambari/MySQL enabled、mgmt exporter、config drift |
| T-088 | M-101 小状态卷试点（h2） | 🔴 | MGMT-003 | 70GB commit 29min/8GB，已中止回滚；结论：改用软件-only 镜像 |
| T-089 | Kerberos 失败后的业务恢复 | ✅ | KRB-INC-001 | HDFS/HBase/Hive/Kafka/Flink/Spark 恢复；Ambari 100/100；HBase 用 simple + 独立 ZK 路径 |
| T-087 | 管理面演练与重建基线 | ✅ | MGMT-002 | 恢复 RTO 128s；MySQL 提升 1s/回切 2s；`ambari3/blueprint.json` + `REBUILD_RUNBOOK.md` |


### P0 — 稳定性保障

| ID | 任务 | 状态 | 关联 | 说明 |
|---|---|---|---|---|
| T-010 | JVM 配置持久化（写入镜像/初始化脚本） | ⏳ | BUG-028 | 当前改动在容器内，重建容器会丢失 |
| T-011 | 容器重启自启编排（MySQL→Ambari Server→Agent→服务） | ⏳ | BUG-029 | 当前需手工拉起 |
| T-012 | 关键组件 watchdog（端口/进程检测 + UNKNOWN 状态自愈） | ⏳ | BUG-032/037 | 防止 HBase/AMS 类故障长时间不恢复；增加 UNKNOWN 检测并修正为 INSTALLED |
| T-013 | Swap 使用率监控（阈值 80%） | ⏳ | — | 防止再次 100% 导致误报 |
| T-014 | **通过 Ambari 配置中心正式调整 JVM 堆内存** | ✅ | BUG-025 | 10 项配置已提交并重启生效；h0 used 33.7→28.5GB，Swap 59%→43% |

### P1 — 功能完善

| ID | 任务 | 状态 | 关联 | 说明 |
|---|---|---|---|---|
| T-020 | AMS/Grafana 开机自启 | ✅ | — | `ambari-metrics-grafana.service` 已 enabled |
| T-021 | Grafana AMS 数据源 + 仪表盘 | ✅ | BUG-031 | 数据源指向新 Prometheus；`HodoopForge 数据湖总览` 文件 provisioning |
| T-022 | Ambari UNKNOWN 状态防复发机制 | ⏳ | BUG-030 | 已修复，需监控 |
| T-023 | h1-h3 容器重启应用 DN/NM 新堆配置 | ⏳ | — | 当前仍为旧配置 |
| T-024 | ZK 会话超时调优 / 避免单点重启 | ⏳ | BUG-023 | HBase 对 ZK 抖动敏感 |
| T-025 | AMS Monitor 与 Collector 健康联动 | ✅ | — | h0 monitor 已重启，4 主机全部上报 |

### P2 — 增强与验证

| ID | 任务 | 状态 | 关联 | 说明 |
|---|---|---|---|---|
| T-030 | 重新启用 12 个 AMS 依赖告警 | ⏳ | BUG-015 | AMS 已就绪，可逆启用 |
| T-031 | 执行冒烟测试脚本并记录 | ⏳ | uttest/SMOKE_TEST | 脚本已就绪 |
| T-032 | 执行集成测试（33 用例） | ⏳ | uttest/INTEGRATION_TEST_MATRIX | 当前 8 已验证 |
| T-033 | 执行性能测试并回填基线 | ⏳ | uttest/PERFORMANCE_TEST | — |
| T-034 | Iceberg/Flink SQL 端到端验证 | ⏳ | func/FEATURE_MATRIX | 资源已带 |
| T-035 | 日志集中化（LogSearch/Solr） | ⏳ | — | 可选 |
| T-036 | HA 评估（NN/RM/HBase Master） | ⏳ | func/ROADMAP M4 | 资源评估 |
| T-015 | 残余堆未生效项排查（TimelineReader/HiveMetastore/ZK/RegistryDNS） | ⏳ | BUG-025 | 模板变量/zkEnv 默认值/无配置项；每项可省 ~0.5GB |
| T-016 | Ranger 启动脚本 `-Xms` 修改持久化 | ⏳ | BUG-035 | 当前在容器内，重建容器会丢失 |
| T-017 | 配置备份/恢复流程标准化 | ⏳ | BUG-034 | 归档脚本 func/sessions/scripts/ |

### P1 — Flink 实时链路需求落地（WQ-HODOOPFORGE-FLINK-REQ-001）

| ID | 任务 | 状态 | 关联 | 说明 |
|---|---|---|---|---|
| T-040 | Flink TM 扩容（2×2 slots×2GB，分散节点） | ✅ | 需求 R-01 | 已完成：2 TM(h2/h3) × 2 slots × 2048m |
| T-041 | 修复 `taskmanager.host` 硬编码 | ✅ | 需求 R-01 | 已从 Ambari content 移除 |
| T-042 | Flink 时区配置 `Asia/Shanghai` | ✅ | 需求 R-05 | 已生效 |
| T-043 | 创建 `/flink-checkpoints/edulake` 并授权 | ✅ | 需求 R-04 | 已存在（1777） |
| T-044 | Hive connector/HiveCatalog 兼容性 | ✅ | 需求 R-03 | 实测不可行（HMS 4.0.1 无 get_table_objects_by_name），改用 hadoop catalog |
| T-045 | 提交实时作业（1 作业 / 3 Sink） | ✅ | 需求 R-05 | 已 RUNNING；2026-11-08 checkpoint 88/0 |
| T-046 | Prometheus + Grafana 监控接入 | ✅ | 需求 R-07/14 | Prometheus 2.54.1 已部署(:9090，3 targets up)；Grafana 数据源+Dashboard 已配 |
| T-047 | 创建 `edulake_dlq` topic | ✅ | 需求 R-09 | 已创建（3 分区，retention 7 天） |
| T-048 | 确认 Python bridge 状态 | ✅ | 需求 R-06 | 已停止，无活跃 consumer |

### P0 — 数据融汇贯通（平台视角新增，见 docs/FLINK_REQ_RESPONSE_V2_PLATFORM_VIEW.md）

| ID | 任务 | 状态 | 关联 | 说明 |
|---|---|---|---|---|
| T-049 | **统一 Catalog**（方案 D：hadoop catalog） | ✅ | 断点1 | HiveCatalog 不可行；hadoop catalog 已验证双向贯通 |
| T-050 | **统一时区**：Spark + Flink 均设 Asia/Shanghai | ✅ | 断点3 | 两端均已生效，dt 一致 |
| T-051 | Hive Iceberg runtime 部署 | ⏳ | 断点2 | 业务方确认为 P1，不阻塞 |
| T-052 | 纠正需求文档 Iceberg 版本口径 1.6.1→1.11.0 | ⏳ | 断点4 | 文档仍写 1.6.1 |
| T-053 | 获取实际 SQL/表结构附件文件 | 🔴 | 断点5 | 仓库中均不存在 |
| T-055 | **停止 Python bridge（双写）** | ✅ | 需求 R-06 | 业务方已停止，双写消除 |
| T-056 | 历史重复数据清洗（ai_1_2/ai_1_3/rag_0_2） | ✅ | 双写 | MERGE 去重完成，零重复 |
| T-057 | Flink TM lib 一致性检查（JM/TM 必须同 JAR） | ✅ | 提交故障 | 已修复并记录 |
| T-058 | Iceberg 小文件治理脚本 | ✅ | R-11 | `ambari3/scripts/iceberg-maintenance.sh`（dry-run 已验证） |
| T-059 | Flink 运维手册 | ✅ | — | `docs/FLINK_OPS_RUNBOOK.md` |
| T-060 | Flink 轻量告警（cron） | ✅ | R-08 | `flink-alert-cron.sh`，每 10 分钟，日志 /tmp/flink-health.log |
| T-054 | NAT persist 服务 start（当前 enabled 但 inactive） | ⏳ | 平台自查 | `sudo systemctl start hodoopforge-nat`，确保重启后规则重建 |

> 答复文档：`docs/FLINK_REQ_RESPONSE_WQ-HODOOPFORGE-FLINK-REQ-001.md`

## 3. 已完成里程碑

| ID | 任务 | 完成日期 | 关联 |
|---|---|---|---|
| M-001 | 集群初始修复（stack_root/TimelineReader/Solr） | 2026-10-14 | BUG-001~008 |
| M-002 | HDFS/HBase 稳定性根因 | 2026-10-15 | BUG-009~012 |
| M-003 | 告警系统性治理 | 2026-10-16 | BUG-013~016 |
| M-004 | AMS 经典部署 | 2026-10-17 | BUG-017~022 |
| M-005 | HBASE/SPARK 告警消除 + NAT V2.4 | 2026-10-28 | BUG-023~024 |
| M-006 | JVM 堆内存全量调优 | 2026-10-29 | BUG-025 |
| M-007 | AMS 栈恢复 + Ambari UNKNOWN 死锁修复 | 2026-10-29 | BUG-030/033 |
| M-008 | func/bugtrace/uttest 治理体系建立 | 2026-10-29 | — |

## 4. 统计

| 状态 | 数量 |
|---|---|
| ✅ 完成 | 19 |
| ⏳ 待办 | 22 |
| 🚧 进行中 | 1 |
| 🔴 阻塞 | 0 |
