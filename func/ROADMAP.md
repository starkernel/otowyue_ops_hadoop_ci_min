# 迭代计划与进展（ROADMAP）

> 优先级：P0（阻塞/高危）> P1（重要）> P2（改进）
> 状态：`✅ 完成` / `🚧 进行中` / `⏳ 待办` / `❌ 取消`

## 当前版本目标：v1.0「稳定基线」

目标：小型 4 节点集群在 40GB 宿主机上长期稳定运行，核心服务 100% 可用，告警零异常。

### 里程碑 M1：内存与稳定性（2026-10）

| ID | 事项 | 优先级 | 状态 | 备注 |
|---|---|---|---|---|
| M1-1 | JVM 堆内存全量调优（h0/h1-h3） | P0 | ✅ | 见 sessions/2026-10-29-memory-tuning.md |
| M1-2 | 消除 Swap 100% 导致的告警误报 | P0 | ✅ | Swap 56%，告警 82/82 OK |
| M1-3 | 告警根因治理（HBASE/SPARK/ZK/Ranger） | P0 | ✅ | |
| M1-4 | 修复 `/usr/bin/python` 缺失导致组件启动失败 | P0 | ✅ | install 脚本已加固 |
| M1-5 | NAT V2.4 持久化（systemd persist） | P1 | ✅ | 需宿主机 sudo 执行 persist |
| M1-6 | 各容器 JVM 配置持久化（写入镜像/初始化脚本） | P1 | ⏳ | 当前改动在容器内，重建容器会丢失 |

### 里程碑 M2：服务完整性（2026-11）

| ID | 事项 | 优先级 | 状态 | 备注 |
|---|---|---|---|---|
| M2-1 | AMS 纳入 Ambari 管理或开机自启 | P1 | ⏳ | 当前手工启停 |
| M2-2 | Grafana AMS 数据源 + 仪表盘 | P1 | ⏳ | 服务在跑，配置缺失 |
| M2-3 | 重新启用 12 个 AMS 依赖告警 | P2 | ⏳ | AMS 就绪后可逆启用 |
| M2-4 | 清理 Ambari UNKNOWN 组件状态（状态刷新） | P2 | ⏳ | 实际进程正常 |
| M2-5 | Tez 服务（当前 INSTALLED）评估是否需要 | P2 | ⏳ | 仅客户端 |

### 里程碑 M3：自愈与可观测（2026-12）

| ID | 事项 | 优先级 | 状态 | 备注 |
|---|---|---|---|---|
| M3-1 | 关键组件 watchdog（端口/状态检测 + 自动拉起） | P1 | ⏳ | 防止 HBase 类故障长时间不恢复 |
| M3-2 | ZK 会话超时调优 / 避免单点重启 ZK | P1 | ⏳ | 根因：HBase 对 ZK 抖动敏感 |
| M3-3 | Swap 使用率监控告警 | P1 | ⏳ | 阈值 80% |
| M3-4 | 日志集中化（可选：Infra Solr + LogSearch） | P2 | ⏳ | |
| M3-5 | AMS 指标 + Grafana 大屏 | P2 | ⏳ | |

### 里程碑 M4：生产最小 HA（2026-11 起，P0）

> **模型**：h0–h3 每个容器 = 一台主机；HA 以容器为故障域，通过反亲和部署实现；物理宿主机故障不在承诺范围。完整方案见 `docs/PRODUCTION_HA_UPGRADE_PLAN.md`。

| ID | 事项 | 优先级 | 状态 | 依赖/备注 |
|---|---|---|---|---|
| M4-0 | 容器内存上限调整 + 反亲和核对 | P0 | 🚧 | h1 10/h2 9/h3 9GB 已调整；反亲和核对待做 |
| M4-1 | Kafka 3 broker + RF3 + min.insync=2 | P0 | ✅ | 2026-11-08 完成，故障注入通过 |
| M4-2 | HDFS NN HA（NN1 h0 Active / NN2 h3 Standby + JN h0/h1/h3 + ZKFC） | P0 | ✅ | 2026-11-09 完成，双向 failover 通过 |
| M4-3 | HMS/HS2 HA（h0/h3 + VIP + MySQL 主从） | P1 | ⏳ | 依赖 M4-2 |
| M4-4 | Flink JM HA（JM1 h0 / JM2 h2 + ZK + HDFS） | P1 | ⏳ | 依赖 M4-2 |
| M4-5 | Kerberos/Ranger（KDC1 h0 / KDC2 h3 + keytab + 维护窗口） | P2 | ⏳ | 依赖 M4-0 |
| M4-6 | Prometheus/Alertmanager HA + blackbox | P2 | ⏳ | 依赖 M4-0 |
| M4-7 | 容器故障注入演练与验收（`docker stop`，RTO/RPO） | P0 | ⏳ | 依赖 M4-1~M4-6 |

## 进展时间线

| 日期 | 里程碑 | 事件 |
|---|---|---|
| 2026-10-14 | — | 集群初始修复（stack_root、TimelineReader、Solr、chronyd） |
| 2026-10-15 | — | HDFS/HBase 稳定性根因（Router/NAT/资源） |
| 2026-10-16 | — | 告警系统性根因分析（SNN、Ranger 路径、AMS 缺失） |
| 2026-10-17 | — | AMS 经典部署（collector + monitor + grafana） |
| 2026-10-28 | M1 | HBASE/SPARK 告警消除 + NAT V2.4 |
| 2026-10-29 | M1 | JVM 堆内存全量调优，Swap 100%→56%，82/82 告警 OK |
