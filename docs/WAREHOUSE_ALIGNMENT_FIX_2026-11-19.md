# Warehouse 分叉修复（2026-11-19）

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


## 1. 现象

- Flink 写入 `hdfs://qixuandata/iceberg-warehouse-ha/...`
- 业务通过 Spark `iceberg` catalog 读到的表 Location 是
  `hdfs://bigtop-hostname0...:8020/iceberg-warehouse/...`
- `lake-health` 报 `warehouse_aligned:false`，`check_lake_alignment.py` 报 `aligned=0 misaligned=77`

## 2. 根因

两套 catalog 指向不同物理仓库：

| 使用方 | catalog | warehouse |
|---|---|---|
| 业务 Spark | `iceberg` | `hdfs://qixuandata/iceberg-warehouse`（旧目录） |
| Flink | `iceberg` | `hdfs://qixuandata/iceberg-warehouse-ha` |
| 平台核对 | `newice`（临时） | `hdfs://qixuandata/iceberg-warehouse-ha` |

旧仓库表元数据里的 `location` 仍是建表时的 `bigtop-hostname0` authority，所以业务看到旧路径；Flink 写的是 `-ha`，形成 split-brain。

## 3. 修复

1. 补齐 `-ha` 缺失的 7 张表（旧 77 / 新 70）：
   - `demo/{ads_order_city_daily,dwd_order_daily,metrics,ods_orders,users}`
   - `edulake_knowledge/dws_rag_quality_by_chapter`
   - `edulake_meta/data_product_availability`
2. 迁移脚本默认源仓库改为 nameservice：
   `OLD = hdfs://qixuandata/iceberg-warehouse`，避免依赖某一台 NameNode。
3. 通过 Ambari `spark-defaults` 把业务 catalog 切到 `-ha`：
   ```text
   spark.sql.catalog.iceberg.warehouse = hdfs://qixuandata/iceberg-warehouse-ha
   ```
4. 重启 Spark ThriftServer（request 747/748）。
5. 重新 failover `nn2 -> nn1`，h0 回到 Active。

## 4. 验证

```text
$ python3 datalake/tools/check_lake_alignment.py
tables=77 aligned=77 misaligned=0 described=77

$ hdfs haadmin -getAllServiceState
bigtop-hostname0 ... active
bigtop-hostname3 ... standby

$ DESCRIBE EXTENDED iceberg.edulake_learning.dwd_courses
Location  hdfs://qixuandata/iceberg-warehouse-ha/edulake_learning/dwd_courses
```

证据：`datalake/evidence/2026-11-19-warehouse-alignment.json`

## 5. 剩余动作（业务侧）

表位置已对齐，但 `-ha` 的批处理表仍是迁移快照，需要业务在**切换后的 catalog** 上重跑：

```bash
# 业务侧执行
./run_daily_etl.sh 2026-11-18
# 以及 11-09 的定向补跑
```

当前差异示例：

| 表 | 旧仓库 | `-ha` |
|---|---|---|
| `dwd_conversation_messages` | 2564 | 2231 |

重跑后 `-ha` 应补齐 11-18 批处理数据；流式 ODS 已在 `-ha` 且为最新。

## 6. 回滚

旧 `/iceberg-warehouse` 未删除。若需回滚：

1. Ambari `spark-defaults` 的 `iceberg.warehouse` 改回
   `hdfs://qixuandata/iceberg-warehouse`；
2. 重启 Spark ThriftServer；
3. 用 `flink-sql-job-rollback.jar` 重启 Flink。

## 7. 工具

- `datalake/tools/check_lake_alignment.py`：一条命令核对 77 张表 Location
- `datalake/tools/migrate_beeline.py`：old -> new 迁移（默认 nameservice）
