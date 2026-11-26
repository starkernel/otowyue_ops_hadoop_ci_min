# Iceberg HA Warehouse 迁移与 Flink HA 作业

> **日期**：2026-11-09  
> **目标**：把 EduLake 数据湖从旧单 NameNode authority 切到 HDFS HA nameservice，并保持 Flink Exactly-Once。  
> **当前状态**：✅ HDFS NN HA 已启用；✅ 70/70 表迁移完成；✅ 新 Flink 作业 RUNNING（3 sink，checkpoint 20s，端到端 18s）。

---

## 1. 目录

```
datalake/
├── pipelines/
│   ├── migrate_iceberg_warehouse.py        # 应用侧原始脚本（需 PyHive/SASL）
│   └── flink_sql_job/release/
│       ├── flink-sql-job-ha.jar            # 应用侧正式 JAR（warehouse=-ha）
│       ├── flink-sql-job-rollback.jar      # 回滚 JAR（warehouse=旧目录）
│       ├── flink-sql-job-ha-20s.jar        # 仅改 job.sql（无效，class 仍硬编码 60s）
│       └── flink-sql-job-ha-20s-fixed.jar  # class+SQL 均改 20s（当前运行）
├── tools/
│   ├── migrate_beeline.py                  # 平台迁移工具（beeline，无 PyHive 依赖）
│   └── verify_counts.py                    # old/new 全量计数核对
└── evidence/
    └── 2026-11-09-migration-summary.json   # 迁移/作业/探针证据
scripts/
└── hdfs_ha_cutover.sh                      # 应用侧切换脚本（已改默认路径）
```

---

## 2. JAR 与 SHA256

| JAR | warehouse | SHA256 |
|---|---|---|
| `flink-sql-job-ha.jar` | `hdfs://qixuandata/iceberg-warehouse-ha` | `1e112402470ce3e2ac29954ed186eafd71c71d1ea21d91cdd98546b518630c95` |
| `flink-sql-job-rollback.jar` | `hdfs://qixuandata/iceberg-warehouse` | `4b072ca427aa298ddc3889f360397ad084317780e5c378f18a0d7c78c6b2adc5` |
| `flink-sql-job-ha-20s.jar` | 同 ha.jar，仅 job.sql 改 20s | 平台派生（class 仍 60s，未采用） |
| `flink-sql-job-ha-20s-fixed.jar` | 同 ha.jar，class+SQL 均 20s | `d1ab2286adce905b97f5bd17593dfed6cb0fd1afba90074e28cb8891877fd13b` |

> **20s 说明**：应用侧 `SqlJob.class` 里**硬编码**了 `execution.checkpointing.interval=60s` / `min-pause=30s`，会覆盖 `job.sql` 的 SET。只改 `job.sql` 无效；平台对 class 常量做等长替换（60s→20s、30s→10s）并重新打包为 `flink-sql-job-ha-20s-fixed.jar`。当前运行的是该 fixed 版本。建议应用侧后续在源码中改为 20s 并重建正式 JAR。

---

## 3. 使用方式

### 3.1 迁移（平台已验证）

```bash
# 只读预检：列出 oldice 表与行数
python3 datalake/tools/migrate_beeline.py --dry-run

# 全量迁移（oldice -> newice，旧表保留）
python3 datalake/tools/migrate_beeline.py

# 只迁指定表
python3 datalake/tools/migrate_beeline.py --tables edulake_ai.ods_llm_inference_log
```

### 3.2 计数核对

```bash
python3 datalake/tools/verify_counts.py
# 期望 old=70 new=70，mismatch=0，missing=[]
```

### 3.3 提交新作业

```bash
NEW_JAR=$PWD/datalake/pipelines/flink_sql_job/release/flink-sql-job-ha-20s.jar \
  bash scripts/hdfs_ha_cutover.sh submit
```

验证：

```bash
curl -s http://172.19.0.2:8081/jobs/overview
curl -s http://172.19.0.2:8081/jobs/<jid>/checkpoints
```

期望：1 个 RUNNING、3 Source / 3 Sink、checkpoint completed ≥1、failed=0。

### 3.4 回滚

```bash
NEW_JAR=$PWD/datalake/pipelines/flink_sql_job/release/flink-sql-job-rollback.jar \
  bash scripts/hdfs_ha_cutover.sh submit
```

旧 `/iceberg-warehouse` 未删除，回滚安全。

---

## 4. 当前验证结果（2026-11-09）

| 项 | 结果 |
|---|---|
| HDFS HA | h0 Active / h3 Standby，3 JN，2 ZKFC |
| nameservice | `hdfs://qixuandata` 可读写 |
| 迁移 | 70/70，0 mismatch，0 missing |
| 旧仓库 | `/iceberg-warehouse` 未动 |
| 新仓库 | `/iceberg-warehouse-ha` |
| 新作业 | `bbf6360dfddf6592aa04fcf56e10faa8` RUNNING |
| Sink | 3 Source / 3 Sink |
| Checkpoint | completed=7、failed=0，interval=20000ms |
| 端到端 | 探针 19s 可见，写入 `-ha` |
| 分层查询 | ODS/DWD/DWS/ADS 均可查 |
| Kafka | 3 broker，9/9 topic RF3 |
| Spark/Hive | `fs.defaultFS`/warehouse 已切 nameservice |

---

## 5. 注意

- `ambarirpm/` 在 `.gitignore` 中，原始 JAR/脚本不会被 Git 跟踪；本目录是**可交付副本**。
- `migrate_iceberg_warehouse.py` 是应用侧原版，依赖 PyHive/SASL；平台实际使用 `tools/migrate_beeline.py`（beeline，无额外依赖）。
- 旧 authority 仅在 NN1 Active 时可用；迁移/回滚期间保持 NN1 健康。
