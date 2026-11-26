# 功能跟踪体系（func）

> 本目录用于**全面、持续**跟踪 HodoopForge / EduLake 数据平台的功能支持矩阵、性能指标、测试结果、迭代计划与阶段总结。
> 所有文档面向"可审计、可迭代"，每次变更请更新对应条目并在 `CHANGELOG.md` 登记。

## 目录结构

```
func/
├── README.md                      # 本文件：体系说明与导航
├── FEATURE_MATRIX.md              # 功能支持矩阵（服务/组件/能力/状态）
├── PERFORMANCE_BASELINE.md        # 性能基线与指标（JVM/内存/端口/负载）
├── ROADMAP.md                     # 迭代计划与进展（版本路线图）
├── CHANGELOG.md                   # 功能/配置变更日志
└── sessions/                      # 各阶段工作总结（按日期）
    ├── 2026-10-29-t014-ambari-config-tuning.md  # T-014 通过 Ambari 配置中心调堆（正式版）
    ├── 2026-10-29-memory-tuning.md              # 第一次直接改文件（被覆盖，教训）
    ├── 2026-10-28-alert-repair.md
    ├── 2026-10-17-ams-deployment.md
    └── scripts/                   # 可复用脚本
        ├── t014_apply.py          # 配置备份 + 逐个提交
        └── t014_restart.py        # 按服务顺序 STOP→START
```

## 维护约定

1. **功能矩阵**：新增服务/组件或能力变化时更新 `FEATURE_MATRIX.md`，状态使用统一枚举：
   `✅ 已支持` / `🟡 部分支持` / `🔧 手工支持` / `❌ 未支持` / `⏳ 规划中`
2. **性能基线**：每次调优或重大变更后更新 `PERFORMANCE_BASELINE.md`，保留历史对比。
3. **阶段总结**：每个工作阶段（如内存调优、AMS 部署、告警治理）在 `sessions/` 下新增一份总结，
   包含：背景、动作、结果、根因、遗留项、指标对比。
4. **迭代计划**：`ROADMAP.md` 按季度维护，标注优先级 P0/P1/P2 与状态。
5. **变更日志**：任何功能/配置/脚本变更在 `CHANGELOG.md` 追加一行（日期 + 变更 + 影响 + 关联 commit/PR）。

## 环境速览

| 项 | 值 |
|---|---|
| 集群名 | qixuandata |
| Ambari | 3.1.0.0-SNAPSHOT（Web: `http://<host>:20609` → 容器 8080） |
| 栈 | BIGTOP 3.5.0（agent cache BIGTOP 3.2.0/3.3.0） |
| 节点 | h0 `172.19.0.2`(16g) / h1 `172.19.0.5`(8g) / h2 `172.19.0.3`(7g) / h3 `172.19.0.4`(7g) |
| 宿主机 | 约 40GB 内存 / 8GB Swap，容器共享宿主机内存视图 |
| 容器基镜像 | `bigtop/puppet:trunk-rockylinux-8` |

## 关联文档

- `../bugtrace/BUG_REGISTRY.md` — 缺陷跟踪库
- `../uttest/TEST_PLAN.md` — 测试方案
- `../docs/PLATFORM_TECH_USER_MANUAL.md` — 平台说明书（概要）
- `../docs/manual/` — **平台深度文档集（架构/组件/链路/用户/运维/治理/安全/性能/价值）**
- `../docs/screenshots/README.md` — **平台操作界面截图集（55 张实景 + 流水线视频）**
- `../docs/PRODUCTION_HA_UPGRADE_PLAN.md` — **生产最小 HA 升级方案（六项，P0/P1/P2）**
- `../docs/HA_PROGRESS_REPORT_2026-11-08.md` — **HA 进展报告（Kafka RF3 已完成）**
- `../docs/HDFS_NN_HA_PLATFORM_REVIEW.md` — **HDFS NN HA 交接单评审**
- `../docs/HDFS_NN_HA_PLATFORM_RUNBOOK.md` — **HDFS NN HA 平台执行手册**
- `../docs/HA_PROGRESS_REPORT_2026-11-09_HDFS_HA.md` — **HDFS NN HA 完成报告**
- `../docs/FLINK_REQ_RESPONSE_V5_BASELINE_VERIFICATION.md` — 基线报告三项问题核实答复
- `../docs/FLINK_OPS_RUNBOOK.md` — Flink 实时链路运维手册
- `../docs/AMBARI_CLUSTER_REPAIR_RECORD.md` — 集群修复历史
- `../docs/HADOOPFORGE_EDULAKE_FEATURES_TRACKING.md` — 既有功能跟踪（历史）
