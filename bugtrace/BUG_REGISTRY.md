# 缺陷登记主表（BUG REGISTRY）

> 最后更新：2026-10-29
> 图例：S0 致命 / S1 严重 / S2 一般 / S3 轻微；状态 NEW/TRIAGED/IN_PROGRESS/FIXED/VERIFIED/CLOSED/WONTFIX

## 总览

| 状态 | 数量 |
|---|---|
| CLOSED / VERIFIED | 28 |
| FIXED（待复核） | 2 |
| OPEN（待处理） | 3 |
| **合计** | **33** |

---

## A. 集群部署与基础（2026-10-14 ~ 10-16）

| ID | 标题 | 级别 | 优先级 | 状态 | 首次发现 | 影响 | 根因 | 修复 | 关联 |
|---|---|---|---|---|---|---|---|---|---|
| BUG-001 | stack_root 双路径导致服务包不可见 | S1 | P0 | CLOSED | 2026-10-14 | 全服务部署失败 | `stack_root=/usr/bigtop/current` 导致 `/current/current/...` | 改为 `/usr/bigtop`，refresh agent cache | 修复记录 §1 |
| BUG-002 | TIMELINE_READER 未监听 8198 | S1 | P0 | CLOSED | 2026-10-14 | YARN Timeline 不可用 | stack_root 双路径 + WebHDFS 非法主机名（下划线）导致 copy_to_hdfs 失败 | 预置 service-dep.tar.gz 到 HDFS，重启 | 修复记录 §2 |
| BUG-003 | Infra Solr HTTP 超时 / CPU 高 | S1 | P0 | CLOSED | 2026-10-14 | Ranger 审计不可用 | `ranger_audits` 集合 shard node_name 为 IP，与 live node FQDN 不一致 → remoteQuery 死循环 | 删除重建集合（ZK configset） | 修复记录 §3 |
| BUG-004 | chronyd 健康检查异常 | S3 | P1 | CLOSED | 2026-10-14 | 主机告警 | 容器无 systemd NTP 服务 | 重建 dummy oneshot 单元 | 修复记录 §4 |
| BUG-005 | ulimit 告警阈值类型错误 | S3 | P2 | CLOSED | 2026-10-14 | 伪告警 | 阈值 float 与整数比较 | 改为整数 1500000/3000000 | 修复记录 §4 |
| BUG-006 | FLINK_TASKMANAGER pid 文件双行 | S2 | P1 | CLOSED | 2026-10-14 | h2 组件 ALERT | pid 文件含旧死 PID + 新活 PID，`int()` 解析失败 | 重写单行活 PID | 修复记录 §5 |
| BUG-007 | 多组件 INSTALLED 状态未刷新 | S2 | P1 | CLOSED | 2026-10-14 | HBASE/SPARK 等显示异常 | 组件未真正启动 | PUT STARTED + 端口验证 | 修复记录 §6 |
| BUG-008 | ambari_server_stale_alerts 伪告警 | S3 | P2 | CLOSED | 2026-10-14 | 噪声 | stale alert 机制 | 禁用 definition 76 | 修复记录 §7 |

## B. HDFS/HBase 稳定性（2026-10-15）

| ID | 标题 | 级别 | 优先级 | 状态 | 首次发现 | 影响 | 根因 | 修复 | 关联 |
|---|---|---|---|---|---|---|---|---|---|
| BUG-009 | HBase RS 反复 Abort（Router 链） | S1 | P0 | CLOSED | 2026-10-15 | HBase 不可用 | h3 Router 强制 fs.defaultFS=hdfs://ns-fed；hbase.rootdir 相对路径经 Router；Router ZK 地址为 `None:2181` | core-site 增 `ha.zookeeper.quorum`；hbase.rootdir 改绝对 NN URI；重启 | 修复记录 §8 |
| BUG-010 | WEB 类告警瞬时超时 | S3 | P1 | CLOSED | 2026-10-15 | 伪 CRITICAL | 1 分钟周期，高负载短暂停顿 | connection_timeout=20s，read_timeout=60s | 修复记录 §9 |
| BUG-011 | NAT 无差别 MASQUERADE 破坏容器通信 | S1 | P0 | CLOSED | 2026-10-15 | HDFS 写超时、HBase Abort | `bridge-nf-call-iptables=1` 下源地址被改写为网关，HMaster 反解得到 `_gateway` | NAT V2.3：DNAT 加 `--dst-type LOCAL` 守卫，MASQUERADE 限定出网段，移除 50010/2888/3888 | 修复记录 §10 |
| BUG-012 | 资源分配不合理 | S2 | P1 | CLOSED | 2026-10-15 | 内存压力 | 容器内存/NM 资源与小型集群不匹配 | 调整 docker-compose 与 blueprint | 修复记录 §11 |

## C. 告警系统性治理（2026-10-16）

| ID | 标题 | 级别 | 优先级 | 状态 | 首次发现 | 影响 | 根因 | 修复 | 关联 |
|---|---|---|---|---|---|---|---|---|---|
| BUG-013 | SecondaryNameNode 停止 checkpoint | S2 | P0 | CLOSED | 2026-10-16 | `namenode_last_checkpoint` CRITICAL | SNN checkpoint 主循环挂起 | 重启 SECONDARY_NAMENODE@h1 | 修复记录 §13 |
| BUG-014 | ranger_admin_password_check 路径失配 | S3 | P1 | CLOSED | 2026-10-16 | 告警脚本找不到 | definition 路径 3.2.0 与实际 3.3.0 不符 | 更新 definition 49 source.path | 修复记录 §14 |
| BUG-015 | 12 个 HDFS 指标告警 UNKNOWN | S2 | P1 | FIXED | 2026-10-16 | 告警缺失 | 依赖 AMS `timeline.metrics.service.webapp.address`，当时未装 AMS | 临时禁用 definition 4/9/11/16/19/20/22/24/25/29/30/35；**AMS 已就绪，可重新启用（待办）** | 修复记录 §15；ROADMAP M2-3 |
| BUG-016 | ambari_server_component_version WARNING | S3 | P2 | CLOSED | 2026-10-16 | 伪告警 | Bigtop 栈版本元数据缺口 | 禁用 definition 75 | 修复记录 §16 |

## D. AMS 部署（2026-10-17）

| ID | 标题 | 级别 | 优先级 | 状态 | 首次发现 | 影响 | 根因 | 修复 | 关联 |
|---|---|---|---|---|---|---|---|---|---|
| BUG-017 | ams-hbase ZK 端口冲突 | S1 | P0 | CLOSED | 2026-10-17 | ams-hbase 无法启动 | 读 `/etc/ams-hbase/conf`（默认 2181），与集群 ZK 冲突 | 复制 collector hbase-site，ZK 改 61181，建数据目录 | 修复记录 §18 |
| BUG-018 | collector jar 版本冲突 | S1 | P0 | CLOSED | 2026-10-17 | collector 启动失败 | jackson/jersey/JAX-RS 版本不一致 | 对齐 Hadoop 3.3.6 版本，冲突 jar 改 .bak | 修复记录 §18.1 |
| BUG-019 | host-monitor 需 python2 | S1 | P0 | CLOSED | 2026-10-17 | monitor 无法运行 | 容器仅 python3.6.8 | 安装 python2 | 修复记录 §18.2 |
| BUG-020 | 内置 psutil 缺 C 扩展 | S1 | P0 | CLOSED | 2026-10-17 | monitor 崩溃 | 无 `_psutil_linux.so`，无 gcc/python2-devel | 安装工具链并 `setup.py build`，复制 build 目录 | 修复记录 §18.2 |
| BUG-021 | metric_groups.conf JSON 解析失败 | S2 | P0 | CLOSED | 2026-10-17 | monitor 退出 | 文件含 Apache 许可注释头，`json.load` 拒绝 | 去注释，纯 JSON | 修复记录 §18.2 |
| BUG-022 | monitor 连 localhost 而非 collector | S2 | P0 | CLOSED | 2026-10-17 | 指标不入库 | collector 地址取自 `[default] metrics_servers` | 设为 bigtop_hostname0；补 `hostname=<FQDN>` | 修复记录 §18.2 |

## E. HBASE/SPARK 与内存（2026-10-28 ~ 10-29）

| ID | 标题 | 级别 | 优先级 | 状态 | 首次发现 | 影响 | 根因 | 修复 | 关联 |
|---|---|---|---|---|---|---|---|---|---|
| BUG-023 | HBASE/SPARK CRITICAL（ZK 会话过期） | S1 | P0 | CLOSED | 2026-10-28 | HBase/Spark 不可用 | 单独重启 ZK@h2 使 HBase 会话过期 Abort，且不自愈 | 重启 Master/RS/Thrift | 修复记录 §19；sessions/2026-10-28-alert-repair |
| BUG-024 | `/usr/bin/python` 缺失导致组件启动失败 | S1 | P0 | CLOSED | 2026-10-28 | HBASE_MASTER 启动 126 | 容器无 `/usr/bin/python`，Ranger helper shebang 需要 | `ln -sf /usr/bin/python3`；install 脚本加固 | commit 8776d63 |
| BUG-025 | Swap 100% 导致 Ambari 检查超时误报 | S1 | P0 | CLOSED | 2026-10-29 | ZK/Ranger 伪 CRITICAL | h0 堆总量过大，内存枯竭 | 通过 Ambari 配置中心提交 10 项堆配置并重启生效；used 33.7→28.5GB，Swap 59%→43% | sessions/2026-10-29-memory-tuning；T-014 |
| BUG-026 | HiveServer2 Derby 回退 | S2 | P1 | CLOSED | 2026-10-29 | 首次手工启动失败 | 手工启动路径不完整，回退 Derby | 通过 Ambari 启动，使用 MySQL 元数据库 | 本次确认 |
| BUG-027 | Ambari PUT 只改状态不重启进程 | S3 | P1 | CLOSED | 2026-10-29 | 配置不生效 | Ambari API 语义 | 需真实重启进程/容器 | 经验记录 |
| BUG-030 | Ambari 8 组件卡 UNKNOWN 死锁 | S1 | P0 | CLOSED | 2026-10-29 | 服务级显示 UNKNOWN，UI 误判未启动 | FSM 不接受 `HOST_SVCCOMP_START at UNKNOWN` | 停 Server → DB `hostcomponentstate.current_state` UNKNOWN→INSTALLED → 重启 → PUT STARTED | 任务 T-002 |
| BUG-033 | AMS 栈未运行（ams-hbase + collector 6188） | S1 | P0 | CLOSED | 2026-10-29 | 指标采集中断 | collector 僵尸进程未退出；ams-hbase 未启动 | kill 僵尸 → `ambari-metrics-collector start`（含 ams-hbase） | 任务 T-001 |

---
| BUG-040 | HBase 因 ZK 会话过期再次 Abort | S1 | P0 | CLOSED | 2026-11-03 | HBase INSTALLED | 与 BUG-023 同源，ZK 会话过期 | 重启 HBASE_MASTER/REGIONSERVER | — |
| BUG-041 | AMS collector 僵尸 PID 导致无法启动 | S2 | P1 | CLOSED | 2026-11-03 | 6188 不可达 | 旧 PID 文件残留，启动脚本误判"已在运行" | 清理 PID + 直接 java 启动 | — |
| BUG-042 | Ranger TagSync 堆参数冲突导致 host3 长期 ALERT | S2 | P1 | CLOSED | 2026-11-04 | Ambari Hosts 中 host3 显示橙色 ALERT，组件 Ranger Tagsync 红色 | `ranger-tagsync-env.sh` 设 `Xmx=512m`，启动脚本固定 `-Xms1g` → JVM 报 "Initial heap size set to a larger value than the maximum heap size"；另 `.bak` 文件被 `find conf/ -name 'ranger-tagsync-env*'` 一并 source，覆盖回 512m | 将 `ranger_tagsync_max_heap_size` 调为 1g，移除 conf 下 `.bak`，启动 TagSync 后 host3 恢复 HEALTHY | 截图采集时发现 |

## F. 待处理缺陷（OPEN）

| ID | 标题 | 级别 | 优先级 | 状态 | 说明 |
|---|---|---|---|---|---|
| BUG-028 | 容器重建后 JVM 配置丢失 | S2 | P1 | OPEN | 当前改动在容器内，未写入镜像/初始化脚本 |
| BUG-029 | 容器重启后 MySQL/Ambari/Agent 未自启 | S2 | P1 | OPEN | 需编排开机自启顺序 |
| BUG-031 | Grafana 无 AMS 数据源/仪表盘 | S2 | P1 | OPEN | 未装 datasource 插件 |
| BUG-032 | HBase Abort 后无自愈 | S2 | P1 | OPEN | 需 watchdog（ROADMAP M3-1） |
| BUG-045 | 备份重 I/O 触发 NVMe timeout，NN1 退出/HBase RS Abort | S1 | P0 | CLOSED | 2026-11-09 备份期间 NVMe I/O timeout；HDFS Ranger 审计写失败导致 NN1 退出，HBase WAL 失败 Abort；重启 NN1/RS 并切回 h0 active 恢复 | 备份限流/避开高峰；NVMe 健康检查见 BUG-043 | 2026-11-09 巡检 |
| BUG-046 | SqlJob.class 硬编码 checkpoint 60s 覆盖 job.sql | S2 | P1 | CLOSED | 应用 JAR 的 SqlJob.class 固定 `60s/30s`，仅改 job.sql 无效；平台对 class 常量等长替换为 `20s/10s`，新作业 bbf6360 实测 19s | 建议应用侧源码改为 20s 并重建正式 JAR | 2026-11-09 延迟复核 |
| BUG-047 | Ambari 登录后强制跳转 HA Wizard step9 | S2 | P1 | CLOSED | 服务端 persist `CLUSTER_CURRENT_STATUS` 残留 `clusterState=HIGH_AVAILABILITY_DEPLOY`、`wizardControllerName=highAvailabilityWizardController`、`HighAvailabilityWizard.currentStep=9`；换浏览器/换机器仍复现。重置为 `CLUSTER_INSTALLED_4` 并移除向导字段后恢复 | 使用 `scripts/ambari_reset_ha_wizard.sh`；不要点 YES（回滚 HA） | 2026-11-09 UI 复核 |
| BUG-048 | HDFS 双 NameNode 全部停止（2026-11-14 ~ 11-18） | S1 | P0 | CLOSED | h0 NN 11-14 05:21 停止后 h3 自动切 Active（HA 生效）；11-17 07:48 h3 NN 也收到 SIGTERM 停止，导致 HDFS 全停、HBase/Flink 连带不可用；Ambari 无 STOP 请求记录，判断为残留 HA 操作/直接停进程 | 通过 Ambari request 734 启动 HDFS、735 启动 HBase；清理 h0 僵尸 `DFSHAAdmin -transitionToActive`；补 NN watchdog 与告警升级（T-076） | docs/INCIDENT_2026-11-18_HDFS_NN_RECOVERY.md |
| BUG-049 | Flink 作业反复 RESTARTING（NoResourceAvailable） | S1 | P0 | CLOSED | h2/h3 `FLINK_TASKMANAGER` 未运行（INSTALLED），集群 0 slot；且原 slot=2，即使两台 TM 也只有 4 slot，作业需 9 | 通过 Ambari 把 `taskmanager.numberOfTaskSlots` 2→8，启动 h2/h3 TM（request 736/737），作业 42c0 恢复 RUNNING | docs/INCIDENT_2026-11-18_HDFS_NN_RECOVERY.md |
| BUG-050 | 浏览器 localStorage 残留 HA Wizard step9（BUG-047 的第二层） | S2 | P1 | CLOSED | 服务端 persist 已重置后，旧浏览器仍可能保留 `ambari.HighAvailabilityWizard.currentStep=9` 并再次写回 | Ambari `index.html` 注入自愈脚本（清 step9 + 重写 wizard 路由）；`scripts/fix_ambari_ha_wizard.sh` | docs/INCIDENT_2026-11-18_HDFS_NN_RECOVERY.md |
| BUG-044 | HBase Master 因 ZK 连接异常 Abort（2026-11-09） | S1 | P0 | CLOSED | h0 HMaster 退出，16000/16010 无监听；日志为 ZK getData/ActiveMasterManager 异常；Ambari 重启后恢复，HBase UI 正常 | 与 BUG-023/040 同源，建议 ZK/HBase watchdog | 2026-11-09 巡检 |
| BUG-043 | 宿主机 NVMe 周期性 I/O timeout | S1 | P0 | OPEN | 2026-11-08 发现 dmesg 169 条 nvme timeout（最近 17:54）；可能引发 HDFS pipeline 失败/HBase RS Abort；建议硬件健康检查或更换 |
| BUG-034 | Ambari 批量 desired_configs 合并导致配置错乱 | S2 | P1 | CLOSED | 一次提交 10 个 type 时，Ambari 将内容合并到错误 type（hbase-env 被污染）。改为**逐个提交**（一次一个 type）后正常 | T-014 |
| BUG-035 | Ranger `-Xmx<1g -Xms1g` 导致 JVM 拒绝启动 | S1 | P0 | CLOSED | ranger-admin/usersync/kms 启动脚本硬编码 `-Xms1g`，Xmx 降到 768m/512m 后 Xms>Xmx，报 "Initial heap size set to a larger value than the maximum heap size"；修复脚本 `-Xms512m/256m` | T-014 |
| BUG-036 | ZK PID 文件与实际进程不符导致状态 INSTALLED | S2 | P1 | CLOSED | 手动启动 ZK 后 PID 文件写入临时 PID(654353)，实际进程 1235 → Agent status 判为未运行；修正 PID 文件后恢复 STARTED | T-014 |
| BUG-038 | Flink 与 Python bridge 双写导致主键重复 | S1 | P0 | CLOSED | 2026-11-03 | ODS 同 log_id 2 行 | bridge 与 Flink 同时写同一 ODS（违反二选一约束） | 业务方停 bridge + Iceberg MERGE 去重 | T-055/T-056 |
| BUG-039 | Flink TM 缺 Kafka connector 导致作业无法启动 | S1 | P0 | CLOSED | 2026-11-03 | 作业 RESTARTING | TM（h2/h3）`/usr/lib/flink/lib/` 无 `flink-sql-connector-kafka` | 复制 connector 到所有 TM + 重启 | T-057 |
| BUG-037 | TIMELINE_READER 心跳超时变 UNKNOWN，YARN 显示红色 | S1 | P0 | CLOSED | Ambari `HeartbeatMonitor` 在 Agent 心跳延迟（默认 timeout 300s）时将组件设为 UNKNOWN；UNKNOWN 无法通过 `HOST_SVCCOMP_START` 恢复（InvalidStateTransitionException）。修复：DB current_state UNKNOWN→INSTALLED + 重启 Ambari Server；并将 `agent.heartbeat.monitor.timeout` 调至 600s | 本次 |

> 注：BUG-030 已于 2026-10-29 修复（Ambari UNKNOWN 死锁）；原 F 表 5 条现剩 4 条 OPEN。
