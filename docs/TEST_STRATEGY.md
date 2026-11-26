# 测试策略与用例目录

> 适用版本：2026-11-20 起
> 自动化入口：`.github/workflows/ci.yml`
> 本地入口：`pytest`（见文末）
> 历史手工用例：[`../uttest/`](../uttest/)

## 1. 目标

HodoopForge 的测试分四层，目标不同：

| 层级 | 目标 | 运行环境 | 是否阻断合并 |
|---|---|---|---|
| L1 静态检查 | 语法、格式、配置、文档链接、密钥泄露 | GitHub Runner | 是 |
| L2 单元测试 | 迁移/对齐/巡检/地图等纯逻辑 | GitHub Runner | 是 |
| L3 契约测试 | 仓库中的脚本、证据、文档与 HA 设计不漂移 | GitHub Runner | 是 |
| L4 集成/故障注入 | 真实容器集群的 HA、数据一致性、RTO/RPO | 自建 Runner / 运维机 | 手工触发 |
| L5 性能/容量 | 吞吐、延迟、磁盘与内存水位 | 运维机 | 周期性 |

**原则**

1. 能在 L1/L2 验证的，不放到 L4；CI 必须 5 分钟内给出结果。
2. L4 只读优先；涉及 `docker stop`、failover 的用例必须在维护窗口执行并留证据。
3. 每个线上事故至少沉淀一条回归用例（见 `bugtrace/BUG_REGISTRY.md`）。

## 2. 目录结构

```text
tests/
├── conftest.py                  # 按路径加载非包模块
├── unit/
│   ├── test_check_lake_alignment.py
│   ├── test_migrate_beeline.py
│   ├── test_migrate_iceberg_warehouse.py
│   ├── test_gen_lake_map_data.py
│   ├── test_opstools.py
│   ├── test_repo_assets.py
│   ├── test_scripts_static.py
│   ├── test_docs_links.py
│   └── test_ha_invariants.py
└── integration/
    └── test_live_cluster.py     # 默认 skip，HODOOPFORGE_LIVE=1 开启
```

## 3. 用例清单（自动化）

### 3.1 L1 静态检查

| 用例 ID | 用例 | 期望 | 自动化位置 |
|---|---|---|---|
| TC-STATIC-001 | 全部 shell 脚本 `bash -n` | 0 语法错误 | `test_scripts_static.py::test_shell_script_syntax` |
| TC-STATIC-002 | 全部 shell 脚本有 shebang | 无缺失 | `test_scripts_static.py::test_shell_scripts_have_shebang` |
| TC-STATIC-003 | 一方 Python 源码可编译 | 无 SyntaxError | `test_scripts_static.py::test_python_source_compiles` |
| TC-STATIC-004 | 仓库内 JSON 可解析 | 无解析错误 | `test_repo_assets.py::test_json_files_are_valid` |
| TC-STATIC-005 | 仓库内 YAML 可解析 | 无解析错误 | `test_repo_assets.py::test_yaml_files_are_valid` |
| TC-STATIC-006 | 入口文档相对链接可解析 | 无 404 链接 | `test_docs_links.py::test_entry_doc_relative_links_resolve` |
| TC-STATIC-007 | 关键文件存在 | README/地图/CI/脚本齐全 | `test_repo_assets.py::test_required_project_files_exist` |
| TC-STATIC-008 | 无明文私钥入库 | 无 `.pem/.key/.p12/.jks` | `test_ha_invariants.py::test_no_plaintext_private_keys_in_repo` |
| TC-STATIC-009 | 脚本不硬编码密码 | 只允许 `$AMBARI_*` 变量或 env 文件 | `test_ha_invariants.py::test_shell_scripts_do_not_embed_passwords_in_curl` |
| TC-STATIC-010 | 数据湖地图 JSON Schema | summary/flow/layers 字段与状态合法 | `test_repo_assets.py::test_lake_map_schema` |

### 3.2 L2 单元测试

| 用例 ID | 用例 | 期望 | 自动化位置 |
|---|---|---|---|
| TC-UNIT-LAKE-001 | HDFS 表目录解析 | 仅保留 `*/metadata` 表 | `test_check_lake_alignment.py::test_hdfs_ls_dirs_parses_metadata_paths` |
| TC-UNIT-LAKE-002 | HDFS 命令失败 | 返回空列表 | `...::test_hdfs_ls_dirs_returns_empty_on_failure` |
| TC-UNIT-LAKE-003 | Beeline 输出解析 | 表名→Location 映射正确 | `...::test_describe_locations_parses_beeline_output` |
| TC-UNIT-LAKE-004 | 全部对齐 | 退出码 0，aligned=N | `...::test_main_all_aligned_returns_zero` |
| TC-UNIT-LAKE-005 | 存在错位 | 退出码 1，misaligned>0 | `...::test_main_misaligned_returns_one` |
| TC-UNIT-LAKE-006 | 仅旧仓库有表 | 退出码 1，only_in_old 非空 | `...::test_main_reports_only_in_old` |
| TC-UNIT-LAKE-007 | 默认前缀 | nameservice + `-ha` | `...::test_expected_prefix_is_nameservice` |
| TC-UNIT-MIG-001 | `strip_ddl` 改名 | `oldice`→`newice` | `test_migrate_beeline.py::test_strip_ddl_renames_catalog` |
| TC-UNIT-MIG-002 | `strip_ddl` 去 LOCATION/TBLPROPERTIES | 两者均不存在 | 同上 |
| TC-UNIT-MIG-003 | 无 LOCATION 的 DDL | 原样保留 | `...::test_strip_ddl_without_location_or_properties` |
| TC-UNIT-MIG-004 | `SHOW TABLES` 解析 | 返回 `db.table` | `...::test_list_tables_parses_tsv` |
| TC-UNIT-MIG-005 | 列举失败 | 抛 RuntimeError | `...::test_list_tables_raises_on_failure` |
| TC-UNIT-MIG-006 | COUNT 解析 | 返回整数 | `...::test_count_parses_last_numeric_line` |
| TC-UNIT-MIG-007 | COUNT 不可解析 | 抛 RuntimeError | `...::test_count_raises_when_unparseable` |
| TC-UNIT-MIG-008 | 单表迁移成功 | status=ok，行数一致 | `...::test_migrate_one_ok` |
| TC-UNIT-MIG-009 | 单表迁移行数不一致 | status=count_mismatch | `...::test_migrate_one_count_mismatch` |
| TC-UNIT-MIG-010 | 迁移 SQL 失败 | 抛 RuntimeError | `...::test_migrate_one_propagates_failure` |
| TC-UNIT-PIPE-001 | DDL 去路径并改名 | 新 catalog + 无 LOCATION | `test_migrate_iceberg_warehouse.py::test_strip_location_renames_and_drops_paths` |
| TC-UNIT-PIPE-002 | 双 catalog 初始化 | 6 条 SET | `...::test_setup_catalogs_issues_six_set_statements` |
| TC-UNIT-PIPE-003 | 表清单映射 | `db.table` | `...::test_table_names_maps_second_column` |
| TC-UNIT-PIPE-004 | dry-run | 只查源行数，status=planned | `...::test_migrate_table_dry_run` |
| TC-UNIT-PIPE-005 | 迁移成功 | status=ok，files_outside=0 | `...::test_migrate_table_ok` |
| TC-UNIT-PIPE-006 | 行数不一致 | status=count_mismatch | `...::test_migrate_table_count_mismatch` |
| TC-UNIT-PIPE-007 | 无 `.files` 元数据 | 仍成功，outside=None | `...::test_migrate_table_tolerates_missing_files_metadata` |
| TC-UNIT-PIPE-008 | 非法表名 | ValueError | `...::test_migrate_table_rejects_bad_name` |
| TC-UNIT-MAP-001 | 节点查找 | 命中/未命中 | `test_gen_lake_map_data.py::test_find_node_searches_layers` |
| TC-UNIT-MAP-002 | HTTP 失败 | 返回 `{}` | `...::test_curl_json_returns_empty_on_failure` |
| TC-UNIT-MAP-003 | 命令失败 | 返回 `""` | `...::test_shell_returns_empty_on_failure` |
| TC-UNIT-MAP-004 | 数据刷新 | TEZ 不计入核心服务，状态正确 | `...::test_main_updates_summary_and_nodes` |
| TC-UNIT-MAP-005 | CRITICAL 告警 | 告警 chip=warn，HDFS=bad | `...::test_main_marks_critical_alerts` |
| TC-UNIT-MAP-006 | 数据文件缺失 | 返回 1 | `...::test_main_missing_data_file_returns_one` |
| TC-UNIT-OPS-001 | 合法 XML | 校验通过 | `test_opstools.py::test_config_validator_accepts_valid_file` |
| TC-UNIT-OPS-002 | 缺必需项 | 报错含键名 | `...::test_config_validator_reports_missing_property` |
| TC-UNIT-OPS-003 | 文件不存在 | 报错含“配置文件不存在” | `...::test_config_validator_reports_missing_file` |
| TC-UNIT-OPS-004 | XML 损坏 | 报错含“XML 解析错误” | `...::test_config_validator_reports_malformed_xml` |
| TC-UNIT-OPS-005 | 端口监听 | 返回 True | `...::test_service_checker_detects_open_port` |
| TC-UNIT-OPS-006 | 端口关闭 | 返回 False | `...::test_service_checker_returns_false_for_closed_port` |
| TC-UNIT-OPS-007 | 全服务检查 | 键齐全 | `...::test_service_checker_check_all_returns_expected_keys` |
| TC-UNIT-OPS-008 | 日志计数 | ERROR/WARN 数正确 | `...::test_log_analyzer_counts_errors_and_warnings` |
| TC-UNIT-OPS-009 | 日志文件不存在 | 返回 error | `...::test_log_analyzer_missing_file` |
| TC-UNIT-OPS-010 | 目录分析 | 只分析 `.log` | `...::test_log_analyzer_analyze_directory` |
| TC-UNIT-WD-001 | NN HA 输出解析（健康） | 1 active + 1 standby | `test_watchdog.py::test_parse_ha_state_healthy` |
| TC-UNIT-WD-002 | NN HA 输出解析（单台宕） | healthy=False，unknown 非空 | `...::test_parse_ha_state_one_namenode_down` |
| TC-UNIT-WD-003 | 端口探测 | 9092 命中、9093 未命中 | `...::test_parse_listening` |
| TC-UNIT-WD-004 | Flink 作业解析 | 有 RUNNING 即健康 | `...::test_parse_flink_jobs` |
| TC-UNIT-WD-005 | 恢复动作顺序 | HDFS→HBase→Kafka→Flink→Spark | `...::test_decide_orders_hdfs_before_others` |
| TC-UNIT-WD-006 | Ambari 不可达 | 只返回 wait_ambari | `...::test_decide_waits_for_ambari` |
| TC-UNIT-WD-007 | Spark 端口缺失 | 返回 start_spark | `...::test_decide_restarts_spark_thriftserver` |
| TC-UNIT-WD-008 | `--fix` 执行恢复 | performed 记录且最终 healthy | `...::test_main_fix_runs_recovery` |
| TC-UNIT-WD-009 | Ambari 宕机退出码 | 返回 2 | `...::test_main_returns_two_when_ambari_down` |

### 3.3 L3 契约测试（防止设计漂移）

| 用例 ID | 用例 | 期望 |
|---|---|---|
| TC-CONTRACT-001 | 对齐脚本默认 `-ha` | 含 `iceberg-warehouse-ha` 与 `qixuandata` |
| TC-CONTRACT-002 | 迁移工具指向 nameservice | 两个迁移脚本均含 `qixuandata` |
| TC-CONTRACT-003 | 77/77 证据 | `aligned=77, misaligned=0` |
| TC-CONTRACT-004 | Spark/Flink 仓库一致 | 两者均以 `iceberg-warehouse-ha` 结尾 |
| TC-CONTRACT-005 | Kafka 外部端口 | 脚本与 NAT 均含 9092/9093/9094 |
| TC-CONTRACT-006 | 快照恢复覆盖核心服务 | ZK/HDFS/YARN/MR/HIVE/HBASE/KAFKA/SPARK/FLINK/RANGER |
| TC-CONTRACT-007 | 地图摘要 | Warehouse 含 `77/77` 与 `-ha` |
| TC-CONTRACT-008 | HA 计划已更新 | 不再声称只有单 NN/0 JN |
| TC-CONTRACT-009 | 文档单一事实源 | `CURRENT_STATE.md` 含 h0 Active / h3 Standby / 77/77 |

### 3.4 L4 集成与故障注入（手工 / self-hosted）

| 用例 ID | 场景 | 步骤 | 期望 | 证据 |
|---|---|---|---|---|
| TC-INT-HDFS-001 | NN HA 状态 | `hdfs haadmin -getAllServiceState` | 1 active + 1 standby，无 Failed | `datalake/evidence/` |
| TC-INT-HDFS-002 | 数据完整性 | `hdfs dfsadmin -report` | 3 DN，Missing blocks=0 | 同上 |
| TC-INT-HDFS-003 | Active 故障切换 | `docker stop` 当前 Active 的 NN 容器进程 | 30s 内自动选主，读写在 60s 内恢复 | 故障注入记录 |
| TC-INT-HDFS-004 | Standby 故障 | 停 Standby | Active 不受影响，checkpoint 延后 | 同上 |
| TC-INT-KAFKA-001 | 副本与 ISR | `kafka-topics --describe` | 68 分区 RF3、ISR=3、minISR=2 | `datalake/evidence/` |
| TC-INT-KAFKA-002 | broker 故障 | 停 1 个 broker | 生产/消费不中断，ISR 降为 2 | 故障注入记录 |
| TC-INT-KAFKA-003 | 外部接入 | 从 LAN 写 9092/9093/9094 | 三端口均可写入且分区分布正确 | `KAFKA_EXTERNAL_ACCESS.md` |
| TC-INT-HBASE-001 | Master/RS | `echo status \| hbase shell` | 1 active master、1 RS、0 dead | 验收 JSON |
| TC-INT-FLINK-001 | 作业状态 | `/jobs/overview` | `RUNNING`，2 TM | `datalake/evidence/` |
| TC-INT-FLINK-002 | Checkpoint | `/jobs/<id>/checkpoints` | 最近 8 次 COMPLETED | 同上 |
| TC-INT-FLINK-003 | 端到端延迟 | 探针写入 → 落表 | < 60s | 业务回执 |
| TC-INT-SPARK-001 | ThriftServer | `beeline ... SELECT 1` | 返回 1 | 验收 JSON |
| TC-INT-SPARK-002 | 仓库对齐 | `check_lake_alignment.py --json` | 77/77，0 错位 | 对齐证据 |
| TC-INT-AMBARI-001 | 告警健康 | `/alerts` | 0 CRITICAL / 0 UNKNOWN | 巡检日志 |
| TC-INT-AMBARI-002 | 服务状态 | `/services` | 核心服务 STARTED（TEZ 仅客户端） | 巡检日志 |
| TC-HA-SNAPSHOT-001 | 快照恢复 | 恢复后执行 `post_snapshot_recover.sh --all` | 服务、NAT、Kafka、Flink 全部恢复 | 恢复日志 |
| TC-HA-SNAPSHOT-002 | 仅巡检 | `--check` | 不改状态，仅报告 | 日志 |
| TC-HA-SNAPSHOT-003 | 快照后 guard | 手工停 NN/HBase/Kafka/Flink/Spark 之一，等待 30s | `kerberos_guard` 自动拉起/恢复，1 分钟内恢复 | `~/.hodoopforge-kerberos/kerberos-guard.log` |
| TC-SEC-001 | Ranger 授权 | `-ha` 路径 rwx | HDFS/Hive/Spark 可读写 | Ranger 审计 |
| TC-SEC-002 | Kerberos（已启用） | 检查 `hadoop.security.authentication` | 期望 `kerberos`；`security_type=KERBEROS`；guard 锁 agent | 安全评估 |

### 3.5 L5 性能与容量

| 用例 ID | 指标 | 阈值 | 工具 |
|---|---|---|---|
| TC-PERF-001 | Kafka 生产吞吐 | ≥ 5 MB/s（单 broker 故障时 ≥ 3 MB/s） | `kafka-producer-perf-test.sh` |
| TC-PERF-002 | Flink 端到端延迟 | P95 < 60s | 探针时间戳 |
| TC-PERF-003 | Spark 小查询 | `SELECT 1` < 3s；77 表 Location 检查 < 15min | beeline |
| TC-PERF-004 | 容器内存 | 稳态 < 85% limit；无持续 swap 增长 | `docker stats` |
| TC-PERF-005 | 磁盘水位 | < 70% WARNING，< 85% CRITICAL | Ambari |
| TC-PERF-006 | 日志增长 | 单容器 `/var/log` < 5GB；14 天自动清理 | `cleanup_old_logs.sh` |

### 3.6 管理面（2026-11-24 新增）

| 用例 ID | 用例 | 期望 | 自动化位置 |
|---|---|---|---|
| TC-STATIC-011 | compose 重建基线 | 4 服务有 restart/healthcheck/logging，mem 20/10/9/9 | `test_management_plane.py::test_compose_is_a_safe_rebuild_baseline` |
| TC-STATIC-012 | 容器启动 unit 与管理 exporter | 安装脚本包含两个 unit，且禁止 compose up | `...::test_container_boot_unit_and_exporter_are_installed` |
| TC-STATIC-013 | 管理模型文档 | 归属矩阵/启动顺序/禁止事项齐全 | `...::test_management_model_documents_ownership_and_bans` |
| TC-STATIC-014 | 管理面指标 | exporter 暴露 ambari/agent/mysql/hive/kdc/backup/drift | `...::test_management_exporter_exposes_expected_metrics` |
| TC-STATIC-015 | watchdog 管理面覆盖 | containers/agents/mysql/hive/kdc/yarn/backup | `...::test_watchdog_covers_management_plane` |
| TC-STATIC-016 | 配置漂移静态检查 | `config_drift_check.py --static` 退出 0 | `...::test_config_drift_static_check_passes` |
| TC-UNIT-MGMT-001 | 自愈顺序 | 容器 → Ambari → Agent → MySQL → 数据面 | `test_watchdog.py::test_decide_starts_containers_first` |
| TC-UNIT-MGMT-002 | 管理面动作 | Agent/MySQL/KDC/Hive/YARN 缺失时动作正确 | `test_watchdog.py::test_decide_starts_management_plane` |
| TC-LIVE-MGMT-001 | 容器 restart policy | 4 个均为 `unless-stopped` | 集成/`config_drift_check.py` |
| TC-LIVE-MGMT-002 | 管理面 unit | containers/mysqld/ambari-server/agent enabled | 集成/`config_drift_check.py` |
| TC-LIVE-MGMT-003 | 管理面指标 | `:9404` 可抓取，`mgmt_config_drift=0` | 集成 |

## 4. 运行方式

### 4.1 本地（CI 同款）

```bash
python3 -m venv .venv-ci
. .venv-ci/bin/activate
pip install -r requirements-dev.txt
pytest -v
```

只跑某一层：

```bash
pytest tests/unit -v
pytest tests/unit/test_ha_invariants.py -v
pytest -m "not integration" -v
```

### 4.2 真实集群（只读）

```bash
HODOOPFORGE_LIVE=1 pytest -m integration -v
```

### 4.3 故障注入（维护窗口）

```bash
# 先确认当前 Active
docker exec bigtop_hostname0 bash -c \
  "su -s /bin/bash hdfs -c 'hdfs haadmin -getAllServiceState'"

# 停一个 Kafka broker（示例：h3）
docker exec bigtop_hostname3 systemctl stop kafka-broker

# 验证
HODOOPFORGE_LIVE=1 pytest -m integration -v -k kafka

# 恢复
docker exec bigtop_hostname3 systemctl start kafka-broker
```

> 故障注入后必须执行 `bash scripts/post_snapshot_recover.sh --check` 并记录 RTO/RPO。

## 5. 准入与退出标准

**合并准入**

- L1+L2+L3 全绿；
- 新增脚本必须被 `bash -n` 覆盖；
- 新增文档必须进入 `docs/INDEX.md` 且链接可解析；
- 修改 HA/仓库路径必须同步更新 `docs/CURRENT_STATE.md` 与契约测试。

**发布退出**

- L4 关键项（HDFS/Kafka/HBase/Flink/Spark/Ambari）通过；
- 0 CRITICAL 告警；
- 磁盘 < 70%，容器内存 < 85%；
- 77/77 表 Location 对齐；
- 证据写入 `datalake/evidence/`。

## 6. 事故 → 回归用例映射

| 事故 | 回归用例 |
|---|---|
| 2026-11-14 / 11-17 双 NN 停机 | TC-INT-HDFS-001/003、TC-HA-SNAPSHOT-001 |
| 快照后 NAT/hairpin 丢失 | TC-INT-KAFKA-003、TC-HA-SNAPSHOT-001 |
| Flink TM 全停 / slot 不足 | TC-INT-FLINK-001/002 |
| Warehouse 分叉 | TC-CONTRACT-001~004、TC-INT-SPARK-002 |
| 审计日志无限增长 | TC-PERF-006、`scripts/cleanup_old_logs.sh` |
| Ambari 告警线程卡死 | TC-INT-AMBARI-001、`docs/OPERATIONS_AUTOMATION.md` |
