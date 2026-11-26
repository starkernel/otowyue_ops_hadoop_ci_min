# 测试执行记录（RESULTS）

> 每次执行追加一行。结果：PASS / FAIL / BLOCK / PARTIAL
> FAIL 必须关联 `bugtrace` BUG ID。

| 日期 | 用例/套件 | 环境 | 结果 | 关联 BUG | 备注 |
|---|---|---|---|---|---|
| 2026-10-29 | 冒烟-全端口（31 项） | qixuandata | PASS | — | 全部 LISTEN（含 AMS 6188） |
| 2026-10-29 | 冒烟-告警 | qixuandata | PASS | — | 82/82 OK |
| 2026-10-29 | 冒烟-主机 | qixuandata | PASS | — | 4 主机 HEALTHY |
| 2026-10-29 | Ambari 服务状态 | qixuandata | PASS | BUG-030 | 12 STARTED + TEZ INSTALLED（正常） |
| 2026-10-29 | T-014 堆内存调整 | qixuandata | PASS | BUG-025/034/035/036 | 10 项配置生效，12 服务 STARTED，81/81 OK |
| 2026-10-29 | IT-AMS-001/002 | qixuandata | PASS | BUG-033 | 6188 HTTP 200，4 主机有数据 |
| 2026-10-29 | IT-RANGER-001 | qixuandata | PASS | — | 6080 HTTP 200 |
| 2026-10-29 | IT-ZK-001 | qixuandata | PASS | — | ruok=imok |
| 2026-10-29 | TC-HIVE-001（元数据库） | qixuandata | PASS | BUG-026 | 确认为 MySQL |
| 2026-10-29 | TC-HDFS-001 | qixuandata | BLOCK | — | 待执行（需 HDFS 客户端确认） |
| 2026-10-29 | TC-YARN-001 | qixuandata | BLOCK | — | 待执行 |
| 2026-10-29 | TC-HBASE-001 | qixuandata | BLOCK | — | 待执行 |
| 2026-10-29 | TC-KAFKA-001 | qixuandata | BLOCK | — | 待执行 |
| 2026-10-29 | TC-SPARK-001 | qixuandata | BLOCK | — | 待执行 |
| 2026-10-29 | TC-FLINK-001 | qixuandata | BLOCK | — | 待执行 |
| 2026-11-03 | Flink 实时链路 E2E | qixuandata | PASS | BUG-038/039 | 2 作业 RUNNING；新消息 45s 内同步且仅 1 行；零重复 |
| 2026-11-03 | flink-health-check.sh | qixuandata | PASS | — | 9/9 PASS：2 作业 RUNNING、4 slots、checkpoint 50、lag 0、bridge 停止、零重复 |
| 2026-11-03 | iceberg-maintenance.sh --dry-run | qixuandata | PASS | — | llm 15 文件/rag 15 文件，脚本正常 |
| 2026-11-03 | Flink Prometheus endpoint | qixuandata | PASS | — | h0/h2/h3:9249 可抓取，含 numRecordsIn |
| 2026-11-03 | Prometheus+Grafana 接入 | qixuandata | PASS | — | :9090 3 targets up；Dashboard uid=wKbnD5Gnk |
