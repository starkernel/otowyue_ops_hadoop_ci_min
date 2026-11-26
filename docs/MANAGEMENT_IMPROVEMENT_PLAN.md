# 管理机制优化计划

> **状态提示（2026-11-26）**：Kerberos 数据面已启用；当前架构与守卫见 [`ARCHITECTURE.md`](ARCHITECTURE.md) / [`KERBEROS_GUARD.md`](KERBEROS_GUARD.md)。旧 watchdog 描述为历史。


> 制定日期：2026-11-24
> 依据：`docs/MANAGEMENT_MODEL.md` 与 2026-11-24 管理机制审视
> 状态：✅ 已完成 / 🚧 进行中 / ⏳ 待办 / 🔴 阻塞
> Phase 0 已于 2026-11-24 全部落地并验证。
>
> 落地摘要：4 容器 `unless-stopped`；`hodoopforge-containers.service`；
> MySQL/Ambari/Agent enabled；compose 对齐 20/10/9/9；watchdog 覆盖管理面；
> 宿主机 `management_exporter` :9404 + 10 条告警；`config_drift_check.py`；
> 单元/静态 283 通过、16 跳过；管理面集成 3 项通过；恢复 RTO 128s；MySQL 提升 1s/回切 2s。

## 1. 目标

把当前“Ambari + 容器内 systemd + 宿主机 systemd”三层拼接的管理方式，收敛为：

1. 宿主机重启后**无人值守自动恢复**；
2. 每个组件**只有一个启动责任人**；
3. 配置**只有一个权威来源**，漂移可检测；
4. 管理面自身（Ambari/Agent/MySQL/KDC）**可观测、可自愈**；
5. 所有变更**可回写、可验证、可回滚**。

## 2. Phase 0：管理面自愈（本次落地）

| ID | 任务 | 状态 | 验收标准 |
|---|---|---|---|
| M-001 | 容器 restart policy 改为 `unless-stopped` | ✅ | 4 个容器 `docker inspect` 均为 `unless-stopped`，不重建 |
| M-002 | 宿主机 `hodoopforge-containers.service` | ✅ | enabled；`docker start` 已存在容器；不调用 compose；开机后 Ambari 20609 可达 |
| M-003 | 启用 MySQL h0、Ambari Server/Agent | ✅ | h0 `mysqld`/`ambari-server` enabled；4 节点 `ambari-agent` enabled；`ambari-server` 不再 failed |
| M-004 | compose 与运行时对齐 | ✅ | mem 20/10/9/9；含 restart/healthcheck/logging；文档标注“仅重建基线” |
| M-005 | watchdog 覆盖管理面 | ✅ | 新增 containers/ambari/agents/mysql/hive/kdc/yarn/backup 探活与动作 |
| M-006 | 管理面 exporter + 告警 | ✅ | `:9404` 暴露 ambari/agent/mysql/hive/kdc/backup 指标；Prometheus 12/12 targets；新增 10 条规则 |
| M-007 | 配置漂移检查器 | ✅ | `config_drift_check.py` 检查 compose/容器/unit/关键配置/备份，退出码 0 |
| M-008 | 管理模型与计划文档 | ✅ | `MANAGEMENT_MODEL.md` / 本文件 / INDEX / CURRENT_STATE 一致 |
| M-009 | 测试与 CI | ✅ | 新增静态/单元/集成用例；`pytest` 全绿；CI 可跑 |

## 3. Phase 1：消除单份数据/单份配置（维护窗口）

| ID | 任务 | 状态 | 方案 |
|---|---|---|---|
| M-101 | 容器数据持久化 | 🔴 | h2 试点：70GB `docker commit` 29 分钟仅写入约 8GB，已中止并回滚；全量 commit 不可行。改为软件-only 镜像 + 小状态卷，HDFS 数据靠三副本恢复 |
| M-102 | 统一 Kafka/Flink 管理归属 | 🚧 | 已声明 systemd 为 Kafka h2/h3 / JM2 唯一入口，drift checker 校验；Ambari 迁移待维护窗口 |
| M-103 | 备份恢复演练 | ✅ | `restore_drill.sh`：113 表/9253 行，RTO 128s，临时库已删除 |
| M-104 | MySQL 切换演练 | ✅ | `mysql_failover_drill.sh`：提升 1s、回切 2s、lag=0；应用仍指 h0 |
| M-105 | 资源护栏 | 🚧 | 已加 `mgmt_flink_tm_count` + 重复 TM 告警；自动清理与 JVM 上限待做 |
| M-106 | 日志集中化 | ⏳ | Loki/ES 收集容器 + 宿主机日志；保留 14 天；替代手工 logclean |
| M-107 | 管理面指标完善 | ⏳ | 增加 agent 心跳年龄、Ambari DB 连接池、备份成功率趋势 |
| M-108 | 配置漂移纳入 CI | ✅ | `.github/workflows/ci.yml` 已执行 `config_drift_check.py --static` |

## 4. Phase 2：可重建与安全基线

| ID | 任务 | 状态 | 方案 |
|---|---|---|---|
| M-201 | IaC/Blueprint | 🚧 | 已导出 `ambari3/blueprint.json` + `REBUILD_RUNBOOK.md`；镜像 digest/自动重建待做 |
| M-202 | 安全基线 | 🚧 | Grafana CLI 重置未实际写库，已回退；TLS/去 privileged 待维护窗口 |
| M-203 | Kerberos 启用 | ✅/🟡 | 2026-11-26 数据面 HDFS/HBase/Hive/YARN/Flink/Kafka/Spark 已启用；Ambari `security_type=KERBEROS`；agent 由 guard 锁定，ZK/Ranger/KMS/TLS 待后续 |
| M-204 | 告警通道 | ⏳ | 设置 `ALERT_WEBHOOK_URL`，接入电话/IM；CRITICAL 30min 升级 |

## 5. 实施顺序

```text
M-001 → M-002 → M-003 → M-004
      → M-005 → M-006 → M-007
      → M-008 → M-009
      → 维护窗口：M-101/M-102/M-103/M-104
      → M-105/M-106/M-107/M-108
      → M-201/M-202/M-203/M-204
```

## 6. 验收命令

```bash
# 容器
docker inspect -f '{{.Name}} {{.HostConfig.RestartPolicy.Name}}' bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3
systemctl is-enabled hodoopforge-containers.service

# 管理面
docker exec bigtop_hostname0 systemctl is-enabled mysqld ambari-server ambari-agent
for h in 1 2 3; do docker exec bigtop_hostname$h systemctl is-enabled ambari-agent; done

# 自愈
python3 scripts/watchdog.py --check
python3 scripts/config_drift_check.py

# 监控
curl -s http://192.168.0.60:9404/metrics | grep mgmt_
curl -s http://192.168.0.60:9090/api/v1/targets | python3 -m json.tool | grep -c '"health": "up"'
```

## 7. 回滚

| 变更 | 回滚 |
|---|---|
| restart policy | `docker update --restart no <container>` |
| 容器启动 unit | `systemctl disable --now hodoopforge-containers.service` |
| 管理面 enable | `systemctl disable mysqld/ambari-server/ambari-agent` |
| compose | `git checkout -- ambari3/docker-compose.yml` |
| watchdog/exporter | 停止对应 unit，恢复上一版脚本 |
| 配置 | `/var/backups/hodoopforge/<ts>/` + Ambari desired config 历史版本 |
