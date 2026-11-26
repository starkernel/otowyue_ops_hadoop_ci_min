# 测试体系（uttest）

> **2026-11-20 起**：可执行测试已迁移到仓库根目录 `tests/`，由 GitHub Actions（`.github/workflows/ci.yml`）自动执行。
> 自动化策略与用例目录见 [`../docs/TEST_STRATEGY.md`](../docs/TEST_STRATEGY.md)，CI 说明见 [`../docs/CI_CD.md`](../docs/CI_CD.md)。
> 本目录继续保留手工/历史测试矩阵，作为 L4/L5 的补充。

> 本目录维护 HodoopForge / EduLake 平台的单元测试、集成测试、性能测试与故障恢复测试方案及用例。
> 目标：每次变更后可重复执行，形成回归基线。

## 目录结构

```
uttest/
├── README.md                       # 本文件
├── TEST_PLAN.md                    # 总体测试方案与策略
├── UNIT_TEST_MATRIX.md             # 单元/脚本级测试矩阵
├── INTEGRATION_TEST_MATRIX.md      # 集成测试矩阵（端到端）
├── PERFORMANCE_TEST.md             # 性能测试方案与结果
├── SMOKE_TEST.md                   # 冒烟测试清单（快速健康检查）
└── testcases/
    ├── TC-HDFS-001.md              # HDFS 读写
    ├── TC-YARN-001.md              # YARN 作业
    ├── TC-HIVE-001.md              # Hive 查询
    ├── TC-HBASE-001.md             # HBase 读写
    ├── TC-KAFKA-001.md             # Kafka 生产消费
    ├── TC-SPARK-001.md             # Spark 作业
    ├── TC-FLINK-001.md             # Flink 作业
    └── TC-AMS-001.md               # AMS 指标
```

## 测试分层

| 层级 | 范围 | 执行频率 | 负责 |
|---|---|---|---|
| 冒烟（Smoke） | 端口/进程/HTTP 探活 | 每次变更后 | 运维 |
| 单元（Unit） | 脚本、配置解析、工具函数 | 每次提交 | 开发 |
| 集成（Integration） | 服务间端到端链路 | 每次发布 | 测试 |
| 性能（Perf） | 吞吐/延迟/资源 | 每版本 | 测试 |
| 故障恢复（Chaos） | 杀进程/断网/重启 | 每季度 | 运维 |

## 结果记录约定

- 每次执行在 `RESULTS.md` 追加一行：日期、用例 ID、环境、结果(PASS/FAIL/BLOCK)、备注。
- FAIL 必须关联 `bugtrace` 中的 BUG ID。
