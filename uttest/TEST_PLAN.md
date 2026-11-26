# 总体测试方案（TEST PLAN）

> 环境：qixuandata（Ambari 3.1.0 / BIGTOP 3.5.0，4 容器）
> 版本：v1.0 稳定基线

## 1. 测试目标

1. 验证 4 节点小型集群**所有服务可用**（端口 + 功能）。
2. 验证服务间**端到端链路**（存储/计算/查询/消息/流处理）。
3. 建立**性能基线**，支撑后续回归对比。
4. 验证**故障恢复**能力（进程杀死/重启后是否能恢复）。
5. 保证变更（内存/配置/脚本）**不引入回归**。

## 2. 测试范围

| 类别 | 覆盖对象 |
|---|---|
| 基础设施 | 容器运行、网络、DNS/hosts、端口、Swap/内存 |
| 存储 | HDFS 读写、DataNode 副本、Router |
| 资源调度 | YARN RM/NM、队列、容器分配 |
| 数据库 | HBase 读写、RegionServer |
| 数据仓库 | HiveServer2、Metastore、WebHCat、Tez |
| 消息 | Kafka 生产/消费 |
| 批处理 | Spark on YARN、Spark Thrift |
| 流处理 | Flink Standalone 作业 |
| 安全 | Ranger 策略、Ranger KMS |
| 监控 | AMS Collector/Monitor、Grafana |
| 协调 | ZooKeeper 仲裁 |
| 搜索 | Infra Solr |

## 3. 环境准备

```bash
# 主机名解析（容器内已由 docker-compose 挂载 /etc/hosts）
bigtop-hostname0.bigtop.apache.org  172.19.0.2
bigtop-hostname1.bigtop.apache.org  172.19.0.5
bigtop-hostname2.bigtop.apache.org  172.19.0.3
bigtop-hostname3.bigtop.apache.org  172.19.0.4

# Ambari
http://<宿主机>:20609  admin/admin  Header: X-Requested-By: ambari
```

## 4. 测试类型与策略

### 4.1 冒烟测试（每次变更）
- 执行 `SMOKE_TEST.md` 中的端口/进程/HTTP 探活脚本。
- 通过标准：所有期望端口 LISTEN，关键 HTTP 返回 200，告警非 OK = 0。

### 4.2 单元测试
- 脚本类：`setup-nat-forward.sh`、`install-*.sh` 语法检查（`bash -n`）。
- 配置类：JSON/XML 解析校验、YAML 结构校验。
- 工具类：Ambari REST helper、日志解析。

### 4.3 集成测试
- 按 `INTEGRATION_TEST_MATRIX.md` 执行端到端用例。
- 每个用例含前置、步骤、期望、清理。

### 4.4 性能测试
- 见 `PERFORMANCE_TEST.md`。
- 记录吞吐/延迟/资源占用。

### 4.5 故障恢复测试
- 杀进程、重启容器、断开依赖，验证自愈/手工恢复。
- 记录 MTTR（平均恢复时间）。

## 5. 通过标准（Exit Criteria）

| 项 | 标准 |
|---|---|
| 冒烟 | 100% PASS |
| 集成 | ≥ 95% PASS，FAIL 有 BUG 记录 |
| 性能 | 达到 `func/PERFORMANCE_BASELINE.md` 目标 |
| 告警 | 非 OK = 0（或全部有已知原因） |
| 主机 | 全部 HEALTHY |

## 6. 缺陷管理

- 测试 FAIL → 在 `bugtrace/BUG_REGISTRY.md` 登记新 BUG（或关联已有）。
- 修复后回归对应用例，更新 `RESULTS.md`。

## 7. 风险与约束

- 单节点资源有限（40GB），性能测试避免并发过高。
- 部分服务为手工部署（AMS/Grafana），测试前需确认已启动。
- 非安全模式（无 Kerberos），安全测试仅覆盖 Ranger 授权。
