# 基线报告问题核实答复（v5）

> **文档编号**：HODOOPFORGE-FLINK-REQ-001-RESP-V5  
> **文档属性**：📤 面向业务方（EduLake）的核实答复  
> **日期**：2026-11-04  
> **对应基线报告**：最新基线报告中列出的 3 项问题  
> **核实方**：HodoopForge 大数据平台运维组  
> **核实方式**：集群实测（qixuandata，2026-11-04）

---

## 一、核实结论摘要

| # | 基线报告问题 | 是否真实存在 | 业务方文档是否已记录 | 当前状态 | 定级建议 |
|---|---|---|---|---|---|
| 1 | Kerberos 未启用（ACC-02 FAIL） | ✅ **存在** | ✅ 已记录 | ⏳ 未解决（需维护窗口） | **P0 合理** |
| 2 | Hive/BI 直连（10000 兼容性） | ✅ **存在** | ✅ 已记录，明确降级 | ⏳ 未解决（不阻塞） | P1（与业务方一致） |
| 3 | 实时延迟 ~45s（目标 <30s） | ✅ 存在过 | ✅ 验收要求 30s | ✅ **已优化至 17s** | 已关闭 |

**总体判断**：
- 三项问题**均真实存在**，业务方此前已在交接/审阅文档中记录，**并非遗漏**。
- 其中**延迟问题已由平台于 2026-11-04 解决**（45s → 17s），满足业务验收标准（≤30s）。
- **Kerberos 是当前唯一真正的生产阻断**，需独立维护窗口，非实时链路缺陷。
- **Hive/BI 直连**业务方已明确为 P1、不阻塞本期，与基线报告定级一致。

---

## 二、逐项核实

### 2.1 Kerberos 未启用（ACC-02 FAIL）

#### 实测证据

| 检查项 | 结果 |
|---|---|
| Ambari 服务列表是否含 `KERBEROS` | ❌ 否 |
| `/etc/security/keytabs/` 是否存在 keytab | ❌ 否 |
| `cluster-env.security_enabled` | `false` |
| Ranger | ✅ 已启用（仅授权层） |

复核命令：
```bash
# 1) 服务列表
curl -s -u admin:admin -H 'X-Requested-By: ambari' \
 'http://localhost:20609/api/v1/clusters/qixuandata/services?fields=ServiceInfo/service_name' \
 | grep -o KERBEROS || echo "无 KERBEROS 服务"

# 2) keytab
docker exec bigtop_hostname0 ls /etc/security/keytabs/ 2>/dev/null || echo "无 keytab"
```

#### 业务方文档记录

`19-hodoopforge-flink-handover-2026-11-03.md` 第 456 行：

> `| Kerberos | ⏳ 平台 | 无 KDC/无 KERBEROS 服务，需维护窗口；见 doc/function/18-kerberos-ranger-runbook.md |`

#### 平台判断

| 项 | 结论 |
|---|---|
| 是否真实 | ✅ 是 |
| 是否阻断实时链路 | ❌ 不影响 Flink/Kafka/Iceberg 当前运行 |
| 是否阻断"生产安全合规" | ✅ 是（无强认证） |
| 定级 | **P0（安全合规），但非功能阻断** |

#### 启用工作量与风险（供业务方评估）

| 步骤 | 内容 | 风险 |
|---|---|---|
| 1 | 部署 MIT KDC 或对接企业 AD | 需网络/域名规划 |
| 2 | 生成全服务 keytab（hdfs/hive/hbase/kafka/flink/ranger…） | 遗漏会导致服务启动失败 |
| 3 | Ambari 启用 Kerberos（**全服务重启**） | 停机窗口 |
| 4 | Flink 配置 `security.kerberos.login.keytab/principal` | 作业需重提交 |
| 5 | 业务客户端改造（JDBC/Kafka 认证） | **业务方需配合** |

> **平台建议**：先在测试集群演练，提供回滚方案（禁用 Kerberos + 恢复 keytab），再排生产窗口。

---

### 2.2 Hive/BI 直连（10000 兼容性）

#### 实测证据

| 检查项 | 结果 |
|---|---|
| Hive 10000 端口 | ✅ LISTEN |
| `SELECT 1`（Hive 自身） | ✅ 成功 |
| `SHOW DATABASES` | ✅ 正常（9 个库） |
| Hive 查 Iceberg 表 | ❌ `Table not found 'ods_llm_inference_log'` |

复核命令：
```bash
# Hive 自身可用
beeline -u 'jdbc:hive2://192.168.0.60:10000/default' -n hive -e 'SELECT 1;'

# Hive 查 Iceberg 表（预期失败）
beeline -u 'jdbc:hive2://192.168.0.60:10000/default' -n hive -e \
 'SELECT count(*) FROM iceberg.edulake_ai.ods_llm_inference_log;'
# 返回：Table not found 'ods_llm_inference_log'
```

#### 根因

1. 集群 Hive 4.0.1 **无 `iceberg-hive-runtime`**，Hive 不识别 Iceberg 表格式；
2. Spark/Flink 使用 **hadoop catalog**，表元数据在 HDFS `metadata/`，**未注册到 HMS**，Hive 无法发现。

> 注：这不是"Hive 10000 端口故障"，而是 **Hive 缺少 Iceberg 读取能力**。Hive 本身对普通 Hive 表工作正常。

#### 业务方文档记录

`11-flink-platform-response-review-2026-11-03.md` 第 28 行：

> "EduLake 当前统一以 **Spark ThriftServer** 作为查询入口，**不要求 Hive/BI 直连 ODS**；Hive Iceberg runtime 可作为 P1 可选能力……**不阻塞 EduLake 上线**"

#### 平台判断

| 项 | 结论 |
|---|---|
| 是否真实 | ✅ 是（Hive 无法查 Iceberg） |
| 是否阻断 EduLake | ❌ 业务方明确以 Spark ThriftServer 为入口 |
| 定级 | **P1（与业务方一致）** |

> **建议**：基线报告若将此项列为"生产阻断"，建议更正为 P1；或明确"仅当 Hive/BI 直连为验收要求时"才升级。

#### 如需解决（P1）

- 部署 `iceberg-hive-runtime-1.11.0.jar` 到 Hive auxlib，或在 Hive 配置 Iceberg handler；
- 预估 1-2 小时，需重启 HiveServer2；
- 注意 Hive 4.0.1 兼容性验证。

---

### 2.3 实时延迟 ~45s → 已优化至 17s

#### 优化前

| 项 | 值 |
|---|---|
| Flink checkpoint 间隔 | 60s |
| 实测端到端延迟 | ~45s |
| 业务验收标准 | **30 秒内 ODS 可查**（`19-handover` 第 405 行） |
| 结论 | ❌ 未达标 |

#### 优化动作（2026-11-04，平台执行）

```sql
-- 变更前
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.min-pause' = '30s';

-- 变更后
SET 'execution.checkpointing.interval' = '20s';
SET 'execution.checkpointing.min-pause' = '10s';
```

作业重新提交，新 Job ID：
- `89501fb855b11b125481f5161270dc0a`
- `218e2ccbe6b58704c3357f6474cda9dc`

#### 优化后实测

| 项 | 值 |
|---|---|
| checkpoint 间隔 | **20s**（REST 确认 `interval=20000ms`） |
| 作业状态 | 2 × RUNNING |
| 端到端延迟 | **17s**（发消息到 ODS 可见） |
| 是否满足验收 | ✅ 是（≤30s） |

实测记录：
```
发送 session=lat_1793757049410
第 1 次（+17s）: rows=1
✅ 首次可见延迟 ≈ 17s
```

复核命令：
```bash
# 1) checkpoint 配置
curl -s http://192.168.0.60:8081/jobs/<jid>/checkpoints/config | grep interval

# 2) 发消息并计时
TS=$(date +%s%3N); SID="lat_$TS"
echo '{"session_id":"'$SID'",...,"ts":'$TS'}' | kafka-console-producer.sh ...
# 轮询
beeline ... -e "SELECT count(*) FROM iceberg.edulake_ai.ods_llm_inference_log WHERE session_id='$SID';"
```

#### 平台判断

| 项 | 结论 |
|---|---|
| 是否真实存在过 | ✅ 是（checkpoint 60s） |
| 是否已解决 | ✅ **是（17s）** |
| 定级 | **已关闭** |

> **建议**：基线报告更新延迟指标为 **17s**，或标注"已优化"。

#### 权衡说明

- checkpoint 20s 会增加一定开销（更频繁的状态持久化），当前数据量小，实测稳定；
- 若后续吞吐增大，可回调至 30s 并观察延迟；
- 已纳入监控（checkpoint 成功率）。

---

## 三、对基线报告定级的建议

| 问题 | 基线报告定级 | 平台建议 | 理由 |
|---|---|---|---|
| Kerberos | P0 | **P0 保持** | 安全合规，但需维护窗口；非功能故障 |
| Hive/BI 直连 | P1 | **P1 保持**（明确不阻断） | 业务方已确认以 Spark 为入口 |
| 延迟 45s | P1 | **已关闭 / 更新为 17s** | 已优化并实测达标 |

> 若基线报告将 Hive/BI 或延迟列为"生产阻断"，建议按上表更正。

---

## 四、待业务方核实/确认事项

| # | 事项 | 需要业务方确认 |
|---|---|---|
| 1 | Kerberos 是否为**本期上线**的强制验收项 | 若是：需排维护窗口 + 客户端改造；若否：可延后 |
| 2 | Hive/BI 直连是否仍为**非必需** | 确认后平台据此保持 P1 |
| 3 | 延迟 17s 是否满足业务预期 | 若需 <10s，可进一步调 checkpoint（成本更高） |
| 4 | 基线报告中"生产阻断"的范围 | 是否仅指 Kerberos |
| 5 | Kerberos 启用窗口 | 建议低峰 + 测试集群预演 |

---

## 五、平台已完成的动作

| 动作 | 状态 |
|---|---|
| 延迟优化（60s→20s） | ✅ 完成，实测 17s |
| 文档更新（性能基线/链路/运维手册） | ✅ 完成 |
| 问题登记（Kerberos P0 / Hive P1 / 延迟已关闭） | ✅ 完成 |

---

## 六、附录：完整复核清单

```bash
# ---------- Kerberos ----------
# 无 KERBEROS 服务 / 无 keytab → 未启用
curl -s -u admin:admin -H 'X-Requested-By: ambari' \
 'http://localhost:20609/api/v1/clusters/qixuandata/services?fields=ServiceInfo/service_name' | grep -o KERBEROS
docker exec bigtop_hostname0 ls /etc/security/keytabs/

# ---------- Hive / Iceberg ----------
# Hive 自身可用
docker exec bigtop_hostname0 bash -c \
 "beeline -u 'jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default' -n hive -e 'SELECT 1;'"
# Hive 查 Iceberg 表失败（预期）
docker exec bigtop_hostname0 bash -c \
 "beeline -u 'jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default' -n hive -e \
  'SELECT count(*) FROM iceberg.edulake_ai.ods_llm_inference_log;'"

# ---------- 延迟 ----------
# checkpoint 间隔
docker exec bigtop_hostname0 bash -c \
 "curl -s http://localhost:8081/jobs/overview"
# 对每个 RUNNING job:
#   curl -s http://localhost:8081/jobs/<jid>/checkpoints/config

# ---------- 健康检查 ----------
bash ambari3/scripts/flink-health-check.sh
```

---

**核实方**：HodoopForge 大数据平台运维组  
**日期**：2026-11-04  
**关联文档**：`docs/manual/*`、`docs/FLINK_OPS_RUNBOOK.md`、`func/*`、`bugtrace/*`
