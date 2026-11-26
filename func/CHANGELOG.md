# 变更日志（CHANGELOG）

> 格式：日期 | 类型 | 变更 | 影响 | 关联（commit/文档）
> 类型：`feature` / `fix` / `perf` / `docs` / `chore`

| 日期 | 类型 | 变更 | 影响 | 关联 |
|---|---|---|---|---|
| 2026-11-26 | fix | guard 稳定性修复：不再 `systemctl stop ambari-agent`（cgroup 会连带杀 RM/NN），改为只 kill agent PID；增加进程检测/cooldown；HDFS 同时检查两个 NN；恢复 h0/h3 NN、YARN RM/3 NM、Hive/HBase/Spark/Flink | 解决 YARN/HDFS 反复重启和业务假宕机 | KRB-GUARD-002 |
| 2026-11-26 | docs | 全面同步架构/文档/地图：新增 `ARCHITECTURE.md`；更新 CURRENT_STATE/KERBEROS/LAN/Kafka/Hive/Flink/监控/重建/管理手册；`lake-map.html` 增加 Kerberos/KDC/guard/MySQL 节点；新增 `ambarirpm/hodoopforge-handbook-2026-11-26` 交接包与 tar.gz | 文档与当前 Kerberos 设计一致；同事可独立参考 | DOC-KRB-001 |
| 2026-11-26 | feature | Ambari 收口：`security_type=KERBEROS`、`cluster-env/security_enabled=true`；guard 继续锁 agent；收口请求覆盖 h0 nn/jn/kafka keytab 后已恢复并重启；guard 增加 keytab 快照 | Ambari 认识 Kerberos，同时避免旧配置覆盖；keytab 可回滚 | KRB-AMBARI-001 |
| 2026-11-26 | feature | Flink 恢复 Kerberos：keytab 登录、关闭 ZK SASL、移除 Hive connector/KMS 依赖；Kafka 切 SASL_PLAINTEXT/GSSAPI（共享 IP principal，3 broker systemd）；Flink 作业 `adb1b6a9` RUNNING，Kafka produce/consume 验证通过 | Flink/Kafka 进入 Kerberos，实时链路恢复 | KRB-FLINK-KAFKA-001 |
| 2026-11-26 | feature | 新增手工 Kerberos 防呆守护 `kerberos_guard.py`：用户级 systemd 每 30s 锁 ambari-agent、检测/恢复 Kerberos 配置、按序补起 HDFS/HBase/Hive/YARN/Flink/Kafka；Kafka 已切 SASL_PLAINTEXT/GSSAPI 并验证 produce/consume | Ambari 误启动不再覆盖手工 Kerberos；无需 sudo/密码 | KRB-GUARD-001 |
| 2026-11-25 | feature | 数据面手工 Kerberos：HDFS（3 DN/HA）、HBase（HMaster/RS）、Hive（HMS/HS2）、YARN（RM/3 NM）全部验证通过；新增 `scripts/kerberos_hdfs_enable.sh`；Flink 卡 KMS 委托令牌，Kafka/Spark 未切换 | 核心数据面进入 Kerberos；需按文档处理 Flink/Kafka/Spark 与 Ambari 收口 | KRB-INC-006 |
| 2026-11-25 | incident | 显式 principal 第二轮 HDFS Kerberos 验证：`kinit`/RPC/`dfs -ls` 成功，但 JN web 认证与 Ambari `INSTALLED` 残留导致 NN 被 agent 反复停止；已回滚 simple，修复 h1 RPM 库并经 Ambari 恢复 HDFS 3 DataNode，watchdog 全绿 | 证明 Kerberos RPC 可用；下一轮需干净 Ambari 状态 + JN web 认证收口 | KRB-INC-005 |
| 2026-11-25 | feature | Kerberos 侧修正：`dns_canonicalize_hostname=false`；`kerberos_align_hosts.sh` 为 nn/dn/jn/HTTP 生成 FQDN+Docker DNS 双 principal/keytab | 解决 GSS 主机名规范化导致的 SASL 失败 | KRB-FIX-001 |
| 2026-11-25 | incident | Kerberos 第三次尝试（HDFS 单服务）：hostname FQDN 已就绪，手工切 Kerberos 后 DataNode 连接 NN 报 EOF/SASL，立即回滚；HDFS/HBase/Hive/Kafka/Flink/Spark 恢复，Ambari 100/100 | 验证 HDFS Kerberos keytab/配置仍不足 | KRB-INC-004 |
| 2026-11-25 | incident | Kerberos 第二次尝试：hostname 统一 FQDN 并验证，但 Ambari `security_type` 单步 API 未下发 Kerberos 配置，HDFS 启动失败；再次回滚并恢复全部业务 | 确认需 Ambari 向导/分阶段迁移 | KRB-INC-003 |
| 2026-11-24 | fix | Kerberos 回滚后业务恢复：HDFS 3 DataNode/0 missing，HBase HMaster/RS 恢复，Hive/Kafka/Flink/Spark 正常；Ambari 100/100 OK | 业务主链路恢复 | KRB-INC-002 |
| 2026-11-24 | incident | Kerberos 启用尝试失败并回滚：keytab 生成成功，但 `_HOST` 解析为 `bigtop_hostnameX.ambari3_hodoopforge`，与 Ambari `bigtop-hostnameX...` 不一致，DataNode/NN GSS 失败；回滚 security_type=NONE，HDFS/Flink/Hive/Kafka 恢复，HBase 仍不可用 | 确认主机名/显式 principal 前禁止重试 | KRB-INC-001 |
| 2026-11-24 | fix | M-101 h2 试点：70GB `docker commit` 29min 仅 8GB，中止并回滚；h2 服务全部恢复，HDFS/Flink 正常，清理未完成层释放 19G | 验证 commit 路径不可行，改用软件-only 镜像 | MGMT-003 |
| 2026-11-24 | feature | Kerberos 启用前准备：Ambari KERBEROS 服务 + KERBEROS_CLIENT 4/4 安装，kerberos-env/krb5-conf 写入；security_type 仍 NONE | 最后切换等待业务客户端 SASL/keytab | KRB-KDC-001 |
| 2026-11-24 | test | 管理面演练：控制面恢复 113 表/9253 行、RTO 128s；MySQL h3 提升 1s、回切 2s、lag=0；新增 `restore_drill.sh`、`mysql_failover_drill.sh`、blueprint 导出与重建手册 | 备份可恢复、切换可回切，风险可量化 | MGMT-002 |
| 2026-11-24 | feature | 管理面加固：容器 `unless-stopped` + `hodoopforge-containers.service`；MySQL/Ambari/Agent enabled；watchdog 覆盖容器/Agent/MySQL/Hive/KDC/YARN/备份；宿主机 `management_exporter` :9404 + 9 条管理面告警；`config_drift_check.py` | 主机重启可无人值守恢复，管理面可观测/可漂移检测 | MGMT-001 |
| 2026-11-22 | feature | Kerberos KDC 主备上线：h0/h3 krb5kdc，realm `HODOOPFORGE.LOCAL`，4 节点 krb5.conf，admin kinit 验证；`kerberos_setup_kdc.sh` / `kerberos_status.sh`；集群仍 simple | 解除 KDC/realm 阻塞，启用留维护窗口 | KRB-KDC-001 |
| 2026-11-22 | feature | Hive/MySQL HA：HMS h0+h1（双 URI）、HS2 h0+h3（ZK 服务发现）；MySQL h3 异步副本（延迟 0）+ 提升脚本；移除 proxyuser.hive 使 notification API 认证关闭 | 停 h0 HS2/HMS 查询不中断；元数据库有热备 | T-064 |
| 2026-11-22 | feature | Flink JM HA：JM1 h0（Ambari）+ JM2 h1（systemd），ZK 选主 + HDFS HA 元数据；补齐 h1 connector jar；savepoint 恢复作业 | 停任一 JM 作业继续，checkpoint 正常 | T-065 |
| 2026-11-22 | feature | 监控统一查询代理 `prom_proxy.py`（h2:9099 / NAT 19099）、Grafana 数据湖总览面板；node_exporter 纳入 overlay 根分区 | 查询自动切主备；磁盘告警恢复有效 | MON-005 |
| 2026-11-22 | feature | 限流备份 `backup_with_throttle.sh` + 每日 02:30 timer（ionice/nice、7 天保留、SHA256） | 控制面可恢复，避免备份 I/O 抢占 | T-070 |
| 2026-11-20 | feature | 监控 HA：h2 部署 Prometheus/Alertmanager 备实例，Alertmanager gossip 集群（9094）；新增 `failover.sh` 切换 9090/19093；NAT 增加 19090/29093 | h1 故障时可切到 h2，告警去重 | MON-003 |
| 2026-11-20 | feature | Alertmanager 通知闭环：`alert_webhook.py` 落盘 `/var/log/hodoopforge-alerts.jsonl`，支持 `ALERT_WEBHOOK_URL` 转发；Grafana `Prometheus-Flink` 数据源切到新 Prometheus | 告警可留痕/转发，Grafana 可查新指标 | MON-004 |
| 2026-11-20 | fix | Kafka 外部访问补齐 h1 容器 hairpin（kafka_exporter 依赖）；kafka job scrape timeout 10s→25s；Prometheus 10/10 targets 全绿 | 监控不再因 9093 hairpin 缺失而偶发超时 | MON-002 |
| 2026-11-20 | chore | Kerberos 前置：4 节点启用真实 chronyd（偏移 <1ms）；h0/h3 安装 krb5-server，h1/h2 安装 krb5-workstation；watchdog 增加时间同步探活 | 解除时间同步与软件包阻塞，剩余 realm/keytab/客户端改造 | KRB-PREP-001 |
| 2026-11-20 | feature | 启用 Prometheus 监控：h1 部署 Prometheus/Alertmanager，h0–h3 node_exporter，Kafka/HDFS/Ambari/Flink exporter；10/10 targets，13 条告警规则；合并宿主机旧实例，NAT 暴露 9090/9093；watchdog 纳入监控自愈 | 从“只有 Ambari 告警”升级为指标+告警+容量可视化 | MON-001 |
| 2026-11-20 | feature | 建立可执行测试体系与 GitHub CI：`tests/`（L1 静态 + L2 单元 + L3 契约 + L4 集成）、`.github/workflows/ci.yml`（pytest + JUnit + dorny/test-reporter + Allure）、`docs/TEST_STRATEGY.md` / `docs/CI_CD.md` | 每次提交自动回归；HA/仓库路径不再漂移 | CI-TEST-001 |
| 2026-11-20 | fix | 全量告警恢复：HDFS 双 NN 停止、HBase、Kafka broker 重启；checkpoint 补做；h0 回 Active；97/97 告警 OK；清理 14.3GB 旧日志 | 集群恢复健康，磁盘 63%→58% | INCIDENT-2026-11-20 |
| 2026-11-20 | fix | Kafka 耐久性对齐：h0 broker `min.insync.replicas=2`、`default.replication.factor=3`、`unclean.leader.election=false`；9 个 topic 动态补齐 minISR=2 | RF3 下 acks=all 真正生效 | KAFKA-DUR-001 |
| 2026-11-19 | docs | 新增交互式数据湖地图 `docs/lake-map.html`、当前状态 `docs/CURRENT_STATE.md`；历史 HA 文档加注，README 增加文档入口 | 集群状态与文档统一 | DOC-MAP-001 |
| 2026-11-19 | fix | 修复 warehouse 分叉：补齐 7 张表、Spark iceberg catalog 切 -ha、77/77 Location 对齐；h0 回到 Active | 业务读与 Flink 写一致 | WAREHOUSE-ALIGN-001 |
| 2026-11-18 | feature | 运维自动化：post_snapshot_recover 增加 --fix-nat/--fix-kafka/--reset-wizard/--all；新增 install_ops_automation（开机自愈 + 10min 巡检） | 快照/重启后自动恢复，减少人工巡检 | OPS-AUTO-001 |
| 2026-11-18 | fix | NAT 补齐 9093/9094 + 容器 hairpin；Kafka advertised.listeners 统一为 192.168.0.60:9092/9093/9094；三分区写入 4/5/3 | 外部 Kafka 客户端可直达，不再依赖 hosts/override | KAFKA-EXT-003 |
| 2026-11-10 | fix | Kafka advertised.listeners 修正为 `192.168.0.60:9092/9093/9094`；标准客户端 metadata 与三分区写入通过 | 应用侧可移除 `EDULAKE_KAFKA_PARTITION=0` 和 `EDULAKE_KAFKA_ADVERTISED_HOST_OVERRIDE` | KAFKA-EXT-002 |
| 2026-11-09 | fix | Kafka 外部访问补齐 9093/9094，advertised listeners 初版改为 as.long.kim；三分区写入验证通过（应用侧 override 路径） | 应用侧可移除 `EDULAKE_KAFKA_PARTITION=0` | KAFKA-EXT-001 |
| 2026-11-09 | docs | 发布 v3.0 深度手册（10 章 HA/业务联通）、67 张截图、6:26 Edge TTS 晓晓解说视频 | 交付/培训/验收材料同步到最新状态 | DOC-v3.0 |
| 2026-11-09 | fix | 清理 Ambari persist `CLUSTER_CURRENT_STATUS` 的 HA 向导残留（`HIGH_AVAILABILITY_DEPLOY` / `currentStep=9`） | 登录不再强制跳转 HA Wizard step9；新增重置脚本 | BUG-047 |
| 2026-11-18 | fix | 恢复 HDFS（双 NN 停止）：Ambari request 734/735 拉起 HDFS+HBase；h3 Active / h0 Standby，3 DN，0 missing blocks | 存储与 HBase 恢复 | BUG-048 |
| 2026-11-18 | fix | Flink TM 全停 + slot 不足：`numberOfTaskSlots` 2→8，启动 h2/h3 TM；作业 42c0 恢复 RUNNING，checkpoint 正常 | 实时入湖恢复 | BUG-049 |
| 2026-11-18 | fix | Ambari 第二层自愈：index.html 清理浏览器 localStorage step9 并重写 wizard 路由；新增 `scripts/fix_ambari_ha_wizard.sh` | 旧浏览器/Tab 不再回跳 Finalize，避免误点回滚 | BUG-050 |
| 2026-11-08 | docs | 新增《生产最小 HA 升级方案》（Kafka RF3/HDFS NN HA/HMS/Thrift HA/Flink JM HA/Kerberos/Prometheus） | 按「容器即主机」模型明确容器级 HA、反亲和与资源腾挪，无需另购硬件 | HA-001 |
| 2026-11-09 | fix | 备份重 I/O 触发 NVMe timeout，NN1 退出/HBase RS Abort；已恢复并切回 h0 active | 服务恢复，旧/新仓库可读 | BUG-045 |
| 2026-11-09 | fix | SqlJob.class 硬编码 60s 覆盖 job.sql；class 常量改 20s/10s，新作业 bbf6360 探针 19s | 满足 <30s 验收 | BUG-046 / T-069 |
| 2026-11-09 | feature | Iceberg 迁移完成 70/70；新作业 42c0 RUNNING（3 sink、checkpoint 20s）；探针写入 -ha | 数据湖切到 HA warehouse | HA-001 / T-069 |
| 2026-11-09 | feature | 创建 `/iceberg-warehouse-ha` + Ranger 策略 id 19；单表试迁通过（102→102）；70 表迁移启动 | 应用迁移进入执行 | HA-001 / T-069 |
| 2026-11-09 | fix | 发现应用侧 Iceberg 迁移路径冲突：oldice/newice 同指 `/iceberg-warehouse`，migrate 会作用旧表 | 暂停 migrate；建议 newice 改 `-ha` 独立目录 | HA-001 / T-069 |
| 2026-11-09 | feature | HDFS NN HA 完成：NN1 h0 Active / NN2 h3 Standby + 3 JN + 2 ZKFC；nameservice qixuandata；双向 failover 通过 | HDFS 不再单点，旧/新路径可读 | HA-001 / T-063 |
| 2026-11-08 | docs | 收到应用侧 HDFS NN HA 交接单；平台预检通过并创建快照 pre_nn_ha_20261109 | HDFS HA 进入执行准备 | HA-001 / T-063 |
| 2026-11-08 | feature | Kafka 3 broker（h0/h2/h3）+ RF3 + min.insync=2；故障注入通过 | 单 broker 故障不丢，RPO=0 | HA-001 / T-062 |
| 2026-11-08 | chore | 宿主机 +8GB（48.8GB）；容器上限 h1 10/h2 9/h3 9GB | 为容器级 HA 预留资源 | HA-001 |
| 2026-11-08 | docs | ROADMAP M4 升级为 P0 容器级 HA；新增任务 T-061~T-068 | 路线与任务对齐业务优先级 | HA-001 |
| 2026-11-04 | perf | Flink checkpoint 60s→20s，端到端延迟 45s→17s | 满足 <30s 目标 | 延迟优化 |
| 2026-11-03 | fix | HBase 因 ZK 会话过期 Abort，重启 Master/RS 恢复 | HBase 服务恢复 | BUG-023 复发 |
| 2026-11-03 | fix | AMS collector 僵尸 PID 导致启动失败，清理后恢复 6188 | 指标采集恢复 | BUG-041 |
| 2026-11-03 | docs | 新增平台技术与用户使用说明书（727 行） | 平台文档总纲 | MANUAL-001 |
| 2026-11-03 | feature | 部署 Prometheus 2.54.1 + Grafana Flink Dashboard | 监控闭环 | T-046 |
| 2026-11-03 | feature | Flink Prometheus reporter(9249)、edulake_dlq、Iceberg 治理脚本、运维手册 | 可观测与可维护性提升 | T-046/047/058/059 |
| 2026-11-03 | feature | Flink 两作业上线（hadoop catalog），bridge 停用，去重完成 | 实时链路贯通 | V4 文档 |
| 2026-10-29 | perf | T-014 通过 Ambari 配置中心降低 JVM 堆（10 项配置+重启） | h0 used 33.7→28.5GB，avail 4.8→10GB，Swap 59%→43% | BUG-025 / T-014 |
| 2026-10-29 | fix | Ranger 启动脚本 -Xms1g 适配新 Xmx（admin 512m/usersync·kms 256m） | Ranger 可正常启动 | BUG-035 |
| 2026-10-29 | fix | ZK PID 文件修正（654353→实际 1235） | ZK 状态恢复 STARTED | BUG-036 |
| 2026-10-29 | fix | TIMELINE_READER UNKNOWN 死锁修复 + 心跳超时调至 600s | YARN 显示恢复正常 | BUG-037 |
| 2026-10-29 | fix | AMS 栈恢复（清理 collector 僵尸进程，重启 ams-hbase+collector 6188） | 指标采集恢复 | BUG-033 / T-001 |
| 2026-10-29 | fix | h0 metrics-monitor 重启（collector 恢复后 4 主机全部上报） | 指标完整 | T-025 |
| 2026-10-29 | fix | Ambari 8 组件 UNKNOWN 死锁修复（DB current_state→INSTALLED + 重启） | 服务状态全 STARTED | BUG-030 / T-002 |
| 2026-10-29 | docs | 新增任务跟踪表 func/TASK_TRACKER.md | 任务单一来源 | 本目录 |
| 2026-10-29 | perf | JVM 堆内存全量调优（h0 17 个服务 + h1-h3 DN/NM） | h0 used 33.5→23.3GB，Swap 100%→56% | `func/sessions/2026-10-29-memory-tuning.md` |
| 2026-10-29 | fix | h0 容器重启后 MySQL/Ambari Server/Ambari Agent 未自启，手工拉起 | 恢复控制面 | — |
| 2026-10-29 | fix | Hive 元数据库确认使用 MySQL（非 Derby）；HiveServer2 正常运行 | 澄清 Derby 告警 | — |
| 2026-10-29 | docs | 建立 func / bugtrace / uttest 三个跟踪目录 | 项目治理 | 本目录 |
| 2026-10-28 | fix | HBASE/SPARK 告警消除（ZK 会话过期 Abort） | 82/82 OK | commit 8776d63 |
| 2026-10-28 | fix | `/usr/bin/python` 软链接加固（install 脚本） | 组件可启动 | commit 8776d63 |
| 2026-10-28 | feature | NAT 脚本 V2.4（persist/unpersist + 计数修复） | 规则可持久化 | commit 8776d63 |
| 2026-10-17 | feature | AMS 经典部署（collector/monitor/grafana） | 指标采集 | `docs/AMBARI_CLUSTER_REPAIR_RECORD.md` |
| 2026-10-16 | fix | 告警系统性根因（SNN/Ranger/AMS 缺失） | 降噪 | 同上 |
| 2026-10-15 | fix | HDFS/HBase 根因（Router/NAT/资源） | 稳定性 | 同上 |
| 2026-10-14 | fix | 集群初始修复 | 可用 | 同上 |
