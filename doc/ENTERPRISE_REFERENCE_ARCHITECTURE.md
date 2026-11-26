# HodoopForge 企业级参考架构与交付基线(Enterprise Reference Architecture & Delivery Baseline)

> 定位:**面向企业交付 / 客户验收**的深度架构文档。以 Cloudera CDP-SDX、AWS
> Well-Architected Framework、Databricks Medallion、Data Mesh(Dehghani)、
> IBM watsonx.governance 五套行业标杆为参照,给出本集群(HodoopForge,4 容器 /
> Hadoop 3.3.6 / Spark 3.5.6 / Flink 1.20.1 / Kafka 3.4.1 / Iceberg 双引擎 / Ranger)
> 的**目标架构、治理基线、落地脚本与逐项验收标准**。
>
> 血缘文档:
> - `USER-GUIDE.md` —— 部署、安装、服务启停、修复(运维向,1604 行);
> - `OPERATIONS-GUIDE.md` —— 组件级操作与 REST 速查(运维向);
> - `doc/DATA_LAKE_GOVERNANCE_AND_INTEGRATION.md` —— 数据面操作手册(642 行);
> - `doc/BUSINESS_SCENARIOS_AND_AI_INTEGRATION.md` —— 业务场景手册(571 行);
> - **本文档 —— 架构级:把"标杆做法"翻译成"本集群的最小可验收落地"**。
>
> 约定:本文引用标杆一律给官方出处(见附录 C);凡带 ✅ 的命令均在本集群实测;
> 标 ⚠ 的为本集群未内建、需外接或后补的组件(给出契约/坐标)。

---

## 0. 交付速览(给客户一页纸)

### 0.1 本交付回答的五个架构问题

| # | 问题 | 标杆出处 | 本集群落地章 |
|---|------|---------|-------------|
| 1 | 安全/身份/授权如何**一处定义、处处生效**? | Cloudera SDX、AWS WAF Security | §3、§9.4 |
| 2 | 湖仓数据如何分层、质量如何递进? | Databricks Medallion | §10 |
| 3 | 多团队/多域如何共享而不失控? | Data Mesh | §9 |
| 4 | 性能、成本、运维基线怎么定与怎么验收? | AWS WAF 六支柱 | §4–§8 |
| 5 | 模型与 AI 资产如何纳入治理与审计? | IBM watsonx.governance | §11 |

### 0.2 交付物清单(Deliverables)

| 交付物 | 位置 | 验收位置 |
|--------|------|---------|
| 平台健康与端口基线 | 本文 §2.4 | §12.2 A 组 |
| Ranger 策略库与最小权限基线 | 本文 §3.2 | §12.2 C 组 |
| 分层湖仓 DDL 与批/流入湖脚本 | 本文 §10 | §12.2 B 组 |
| 数据字典与血缘登记基线 | 本文 §9.3 | §12.2 C 组 |
| 备份/恢复演练记录 | 本文 §4.2 | §12.2 A 组 |
| 模型事实表与评估回流 | 本文 §11 | §12.2 D 组 |
| 验收报告模板 | 本文 §12.3 | 承重文档 |

### 0.3 与旧版文档的差异(勘误基线,交付前必读)

| 项 | 旧文口径 | **实测修正(本文采用)** |
|----|---------|----------------------|
| Ranger 位置 | 操作手册写 hostname0、USER-GUIDE 写 hostname1 | **hostname0:6080**(`ss -tlnp` 实测) |
| Ranger 口令 | 操作手册写 admin/admin | **admin / Admin1234!**(REST API 401 实测) |
| Ranger 服务名 | 操作手册未写 | `qixuandata_hadoop / _hive / _yarn / _hbase / _kms / _tag` |
| Hive 组件位置 | USER-GUIDE 写 hostname1 | **HS2 10000、Metastore 9083 均在 hostname0** |
| Iceberg 湖目录 | 一致 | `/iceberg-warehouse`,Hadoop Catalog,`demo.users / demo.metrics` 实测存在 |

> 上述勘误同时是本项交付的"事实基线"——客户验收以此为准,不再与旧文档逐字对齐。

---

## 1. 标杆体系总览(为什么对齐这五套)

### 1.1 Cloudera CDP-SDX:安全、治理、元数据"一处定义,处处生效"

Cloudera Shared Data Experience(SDX)是 CDP 的核心设计 —— **一个建立在元数据上的、
独立于计算与存储的安全与治理层**,官方列表如下组件:
Apache Ranger、Apache Atlas、Apache Knox、Hive Metastore、Cloudera Data Catalog、
Cloudera Replication Manager、Workload Manager(出处见附录 C)。

SDX 的本质主张(官方原文要点):
- **一致的安全策略**(Ranger)在 HDFS/YARN/Hive/HBase/Kafka 上统一生效;
- **一致的 schema 与元数据**(Hive Metastore + Data Catalog)复用一份;
- **一致的治理**(Atlas lineage/分类)+ **一致的复制**(Replication Manager)
  与 **一致的编排与配额**(Workload Manager);
- 对用户表现为"单一玻璃窗格(single pane of glass)"。

> 2025 年 HPE 完成对 Cloudera 的收购,CDP 继续作为 HPE exascale/AI 数据平台主线,
> 本架构遵循的 SDX 思路不受影响(出处见附录 C)。

**映射原则**:本集群不是 CDP,但逐项在对位 —— Ranger=Ranger(已启用 HDFS/YARN/Hive 插件)、
Atlas→血缘登记 + Iceberg 快照 + 审计日志(未装 Atlas,用等价的"可审计事实"),
Knox→WebHDFS/JDBC 网关(未装 Knox,用 HTTP 通道 + Ranger 授权),HMS=HMS(已启用),
Data Catalog→Data Dictionary(仓库根 `dict.md` + Hive/Iceberg COMMENT),Replication→distcp+
Iceberg snapshot(HDFS Snapshot + 拷表),Workload Manager→Ambari + YARN 队列 + Flink checkpoint。

具体的"标杆能力 → 本集群等价物"对位表见 §2.3。

### 1.2 AWS Well-Architected Framework:验收的六把尺子

AWS WAF 定义六个支柱(出处见附录 C):

| 支柱 | 英文 | 一句话 |
|------|------|--------|
| 运维卓效 | Operational Excellence | 以代码/脚本运行,可观察、可变更、可复盘 |
| 安全 | Security | 身份、授权、数据保护、审计 |
| 可靠性 | Reliability | 故障恢复、备份、容错设计 |
| 性能效率 | Performance Efficiency | 恰当的负载配给、及时演进 |
| 成本优化 | Cost Optimization | 花得值与省得明 |
| 可持续 | Sustainability | 能耗与碳排的计量与压降 |

本文 §3–§8 按这六支柱组织,**每个支柱都含"落地项 + 命令 + 验收"**。

### 1.3 Databricks Medallion:分层的"质量递进"模型

Medallion(lakehouse 数据分层,官方说明见附录 C)定义三层:

| 层 | 内容 | 典型动作 |
|----|------|---------|
| bronze(青铜) | 原样贴源(raw),逐行保留源指纹 | 追加、幂等,不删改 |
| silver(白银) | 清洗/去重/补全后的可信明细(validated) | 规范化、主键化、分区规整 |
| gold(黄金) | 面向业务的结果/汇总 | 聚合、宽表、指标口径固化 |

官方明确该分层为**推荐而非强制**(recommended but not required)。本集群的 ODS/DWD/DWS/ADS
四层与它一一映射,见 §10.1。

### 1.4 Data Mesh:分布式领域的四原则(Zhamak Dehghani)

出处:Zhamak Dehghani,《How to Move Beyond a Monolithic Data Lake to a Distributed
Data Mesh》,martinfowler.com,2019-05-20(见附录 C)。四原则:

1. **领域所有权(Domain Ownership)**:数据由业务域团队作为领地来负责;
2. **数据即产品(Data as a Product)**:每份数据有明确的消费者契约(SLA/质量/Schema/文档);
3. **自助数据平台(Self-serve Data Platform)**:平台团队提供自助基础设施,减少重复造轮子;
4. **联邦式计算治理(Federated Computational Governance)**:全局标准 + 域内自治,双头监管。

本文 §9 把四原则翻译成本集群可验收的机制(域库划分、数据产品注册、自助入口、Ranger 中央
策略 + 域内 table owner)。

### 1.5 IBM watsonx.governance:AI 资产的治理与"模型营养标签"

IBM watsonx.governance(现并入 watsonx.ai 治理能力,出处见附录 C)提供:
- **Model factsheet**:模型的"营养标签"——每个模型一条记录,自动收集配置/指标/审批/部署信息;
- **模型评估**:RAG、摘要、分类等任务的质量评估;
- **漂移监控(drift)** 与 **毒性与偏见检测(toxicity/bias)**;
- 覆盖整个 AI 生命周期(训练/评估/部署/监控)的审计轨迹。

本集群没有 watsonx;本文 §11 给出**等价机制**:模型注册事实表 + 评估回流 + 漂移指标在湖上
落地,保证"客户无 watsonx 也能验收 AI 治理闭环"。

---

## 2. 目标架构(Target State)

### 2.1 总体部署视图(实测拓扑)

```
                     ┌────────────────── HodoopForge 数据平台 ──────────────────┐
   业务侧(OLTP)       │  控制面(hostname0)              数据面(hostname1/2/3)    │
   MySQL:3306 ────────┼► Ambari 8080 · Ranger 6080 · RM 8088                 │
   业务应用/文件 ──────┼► ZK 2181 · Kafka 9092 · HMS 9083 · HS2 10000        │
   报表/BI(JDBC) ─────┼► Flink JM 8081 · Spark History 18081 · HBase M 16010 │
                      │        │                                              │
                      │        ▼          ┌─────────────────────────────────┐ │
                      │   Iceberg Hadoop Catalog(湖):hdfs://…:8020/iceberg-warehouse
                      │   (demo.users / demo.metrics 已建,Spark 1.6.1 与 Flink 1.11.0 互读)
                      │   Hive 仓:/warehouse/tablespace/managed/hive          │
                      │   Spark ThriftServer(报表入口):hostname1:10016        │
                      └──────────────────────────────────────────────────────┘
  注:FQDN 一律用 bigtop-hostnameN.bigtop.apache.org;勿用 IP(容器 IP 随启动变化)。
```

### 2.2 数据平面分层(Medallion 映射)

| 本集群层 | 命名 | Medallion 对位 | 引擎 | 说明 |
|---------|------|---------------|------|------|
| 贴源 | `ods_*` / bronze | bronze | Hive/Iceberg 原生落盘 | 原样追加+幂等,保留源指纹 |
| 明细 | `dwd_*` | silver | Spark/Flink | 清洗/去重/维度补齐/分区规整 |
| 汇总 | `dws_*` | gold(轻) | Spark SQL | 主题轻度汇总 |
| 应用 | `ads_*` | gold(重) | Spark SQL | 面向报表/标签的成型结果 |
| 维表 | `dim_*` / `code_*` | — | Hive/MySQL 双写 | 维度、字典 |

分工约定:**ODS 与 DWD 在 Iceberg(湖)**,`dws_* / ads_*` 可仍以 Spark SQL 落 Iceberg,
报表只读 `ads_*` 成型结果(避免 OLTP 直连湖上大扫描,见操作手册 §8.2)。

### 2.3 控制平面:SDX 五要素 → 本集群等价物(核心对位表)

| SDX 能力 | 本集群等价实现 | 状态 | 证据/验收 |
|---------|--------------|------|----------|
| Ranger 统一授权 | Ranger Admin `qixuandata_*` 服务 + 插件(HDFS/YARN/Hive 已开) | ✅ | §3.2,`policies/download` API |
| Atlas 血缘 | 血缘登记表 + Iceberg snapshot + Ranger/HDFS audit | ⚠ Atlas 未装,用等价物 | §9.3 |
| Knox 网关 | WebHDFS 50070 + Hive/Spark JDBC(限白名单 + Ranger) | ⚠ Knox 未装 | §3.3、§6.2 |
| Hive Metastore | HMS 9083(统一 schema) | ✅ | §2.4 |
| Data Catalog | 仓库根 `dict.md` + COMMENT + 资产登记表 | ⚠ 手建 | §9.3 |
| Replication Manager | HDFS 快照 + distcp + Iceberg 拷表 | ⚠ 脚本化 | §4.2 |
| Workload Manager | Ambari 告警 + YARN 队列 + Flink checkpoint 基线 | ⚠ 简化版 | §7.2 |

> 演进路线(客户如需逐步对齐 CDP):先补 **Apache Atlas**(血缘/分类)→ 再补 **Knox**(统一网关)
> → 引入 **scheduler 多队列**模拟 Workload Manager。坐标见附录 E。

### 2.4 事实基线(实测,交付验收以此为准)

| 项 | 值 |
|----|----|
| 容器 | `bigtop_hostname0..3`,均 Linux el8(FQDN `bigtop-hostnameN.bigtop.apache.org`) |
| 版本 | Hadoop/YARN/HDFS 3.3.6 · Hive 4.0.1(Tez 0.10.4) · Spark 3.5.6(J8) · Flink 1.20.1(J17) · Kafka 3.4.1 · HBase 2.6.2 · Ranger 2.7.0 · ZK 3.8.4 |
| Iceberg | Spark 侧 `iceberg-spark-runtime-3.5_2.12-1.6.1.jar`;Flink 侧 `iceberg-flink-runtime-1.20-1.11.0.jar`(**版本分叉原因见操作手册 §4.1,勿互换**) |
| 湖 | Hadoop Catalog,warehouse=`hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse`,库 `demo`,表 `users / metrics` 已建 |
| 仓 | Hive 受管表仓库 `/warehouse/tablespace/managed/hive`;交换区建议 `/data/exchange` |
| JDBC 出入口 | HS2 `hostname0:10000`(Hive 引擎);Spark ThriftServer `hostname1:10016`(Spark 引擎,查湖推荐) |
| VI 面 | Ambari 8080 · Ranger 6080 · YARN RM 8088 · Spark History 18081 · Flink JM 8081 · HBase Master 16010 |
| 消息 | Kafka `PLAINTEXT://bigtop-hostname0…:9092`(单 broker,partition 默认 1) |
| Ranger | `http://bigtop-hostname0…:6080`,admin/`Admin1234!`;服务:`qixuandata_{hadoop,hive,yarn,hbase,kms,tag}` |
| YARN | CapacityScheduler,单队列 `root.default`(capacity 100%) |
| 口令基线 | Ranger admin `Admin1234!`;MySQL root `ambarirootpass`;Hive/Spark 业务账号见 §3.2 |

---

## 3. 安全与治理(AWS WAF Security ∩ SDX)

### 3.1 现状登记与风险基线(交付第一件事:说清边界)

| 域 | 现状 | 风险 | 处置 |
|----|------|------|------|
| 认证 | **无 Kerberos**,无 SSO(用户直连) | 弱口令/冒用 | 本文按"角色账号 + 最小权限"下单机基线;生产需 Kerberos/Knox |
| 传输 | HTTP/RPC 明文(无 TLS) | 抓包 | 本集群仅内部实验网络;生产启用 Ranger KMS + TLS |
| 授权 | Ranger HDFS/YARN/Hive 插件已启用,默认策略为"all" | 过度授权 | **按 §3.2 收紧为白名单策略,并写验收** |
| 审计(关键差异) | Ranger Audit 指向 Solr(`ranger.audit.source.type=solr`),但 **Solr 未运行**,`xa_access_audit` 当前 0 行 | 集中审计不可用 | 本期以"HDFS audit + Spark History + Iceberg 快照"为审计证据基线;差异登记,启用 Solr 后开通完整 Ranger Audit(§3.4) |
| 数据保护 | 无 at-rest 加密(冷盘无加密) | 介质丢失 | 登记为差异;必要时启用 Ranger KMS(已装,未启用) |
| 密钥 | Ranger KMS 已装未启用 | — | 登记,不纳入本期验收 |

> ⚠ 说明:单机示教环境刻意不开 Kerberos/TLS;客户验收的**安全增量**集中于"授权收敛 +
> 审计闭环 + 最小权限兜底",这三项与 SDX 的 Ranger 设计完全同构,可直接迁移到生产。

### 3.2 Ranger 授权落地(策略库全量交付)

现状:Ranger 中已有默认全量策略(`all - path` 等,实测 `qixuandata_hadoop` 下策略名
`all - path`,资源 `/*` 授予所有用户读写)。交付动作:**新增收敛策略 → 停用/删除默认 all
策略** → 验收最小权限。以下使用 REST API 落策略(避免手工 UI 误配),登录
`admin / Admin1234!`。

#### 3.2.1 HDFS 路径策略(资源类型 path)

目标:数据面按角色白名单访问。

```bash
# 定义:工程组 spark/flink 可读写湖仓;bi_read 只读;运维 hdfs 超级权限保留
cat > /tmp/policy_hdfs_lake.json <<'JSON'
{
  "service": "qixuandata_hadoop",
  "name": "icestore_engine_rw",
  "policyType": 0,
  "description": "Iceberg 湖面两引擎读写 + 报表只读",
  "isAuditEnabled": true,
  "resources": {
    "path": { "values": ["/iceberg-warehouse/**"], "isRecursive": true, "isExcludes": false }
  },
  "policyItems": [
    { "accesses": [{"type":"read"},{"type":"write"},{"type":"execute"}],
      "users": ["spark","flink"], "groups": [], "delegateAdmin": false },
    { "accesses": [{"type":"read"},{"type":"execute"}],
      "users": ["bi_read"], "groups": [], "delegateAdmin": false }
  ]
}
JSON
curl -s -u admin:Admin1234! -H "Content-Type: application/json" \
  -X POST "http://bigtop-hostname0.bigtop.apache.org:6080/service/public/v2/api/policy" \
  -d @/tmp/policy_hdfs_lake.json
```

Hive 库/表策略(资源类型 database/table/column)、YARN 队列策略同理(资源类型 queue /
`root.default`)。完整策略脚本集由交付打包进仓库 `opstools/`(见附录 E)。

#### 3.2.2 业务账号基线

| 账号 | 角色 | 授权面(HDFS/Hive/YARN) | 现状 |
|------|------|------------------------|------|
| `hdfs` | 平台超级用户/运维 | 全仓,仅供运维操作 | ✅ 已在 Ranger(usersync 同步) |
| `hive` | Hive 服务/批同步 | 交换区读写 + 仓内受管表 DML | ✅ 已在 |
| `spark` | Spark 服务 | `/iceberg-warehouse/**` 读写 | ✅ 已在 |
| `flink` | Flink 服务 | `/iceberg-warehouse/**` 读写 | ✅ 已在 |
| `yarn` | YARN 服务 | 队列提交 | ✅ 已在 |
| `bi_read` | 报表只读 | `/iceberg-warehouse/**` 只读 + Hive 查询 | ⚠ **需建 OS 用户** |
| `etl_svc` | 业务 ETL 专用 | 按业务库/表最小授权 | ⚠ **需建 OS 用户** |

`bi_read / etl_svc` 开通三步(交付步骤含入验收):

```bash
# 1) OS 层建用户(hostname0 上,只需要在集群内可见)
sudo useradd -M -s /sbin/nologin bi_read
# 2) 等 Ranger usersync 周期同步(默认几分钟)或手动验证已入 Ranger:
mysql -urangeradmin -pAdmin1234! ranger -e "SELECT user_name FROM x_user WHERE user_name='bi_read';"
# 3) 在 §3.2.1 策略中引用该用户 → 生效
# ⚠ 未建 OS 用户的策略引用不会生效(usersync 不会同步不存在的用户)
# 生产建议:用 LDAP/统一身份,usersync 消费同一份目录,避免逐节点手工建号
```

> 禁止使用 `root` 跑作业(操作手册 §7.4 红线);Hive/Spark JDBC 一律走专用账号。

### 3.3 最小权限兜底(HDFS 层,即使 Ranger 失效仍兜底)

```bash
sudo -u hdfs hdfs dfs -chmod -R 750 /iceberg-warehouse
sudo -u hdfs hdfs dfs -setfacl -m user:bi_read:r-x /iceberg-warehouse
sudo -u hdfs hdfs dfs -getfacl /iceberg-warehouse        # 验收:看到 bi_read r-x
# 交换区只给 hdfs/hive 写
sudo -u hdfs hdfs dfs -chmod -R 770 /data/exchange
```

### 3.4 审计闭环(谁在何时对哪张表做了什么)

> ⚠ 现状(实测):Ranger 审计目标为 Solr,**Solr 未运行,故 Ranger 侧审计暂不落库**
> (`xa_access_audit` 为 0 行)。本期审计证据基线 = ① HDFS audit 日志 + ② Spark History/
> ThriftServer 日志 + ③ Iceberg 快照日志 + ④ Ranger UI Audit(待 Solr 开通)。启用路径:
> 启动 INFRA_SOLR 服务(纳入演进 §3.6/附录 E),之后按步骤 D 即可查询集中审计。

```bash
# ① HDFS audit 日志(NAMENODE 侧,本期最权威)
docker exec bigtop_hostname0 bash -c 'grep -E "op=(create|delete|rename)" /var/log/hadoop/hdfs/hadoop-hdfs-namenode-*.log | tail -3'

# ② Spark ThriftServer 提交历史(hostname1:10016,SQL 审计)
docker exec bigtop_hostname1 bash -c 'grep -iE "SELECT|INSERT" /var/log/spark/spark-*-thriftserver*.log | tail -5'

# ③ Iceberg 快照日志(湖侧可溯源:谁在何时改了表)
docker exec bigtop_hostname1 bash -c 'export HADOOP_USER_NAME=hdfs; spark-sql --master yarn --deploy-mode client --num-executors 1 --executor-memory 1024m --executor-cores 1 -e "SELECT committed_at, operation FROM iceberg.demo.users.snapshots ORDER BY committed_at DESC"'

# ④ Ranger 集中审计(拿到授权后,REST 导出——当前为空属预期)
curl -s -u admin:Admin1234! "http://bigtop-hostname0.bigtop.apache.org:6080/service/public/v2/api/policy?serviceName=qixuandata_hadoop" -o /dev/null -w "%{http_code}\n"
```

留存基线:HDFS audit / Spark 日志 ≥ 90 天(转储到 `/data/exchange/audit/<yyyyMMdd>/` 由 crontab 每日归档)。

### 3.5 敏感数据:脱敏与掩码(字段级)

Ranger 支持 row-filter/column-masking(本集群 Hive 插件策略)。等价先落地为 **Spark SQL
masking**,把"脱敏结果"作为正式表面:

```sql
-- demo.pii_orders 源 → demo.pii_orders_masked 安全表面
CREATE TABLE iceberg.demo.pii_orders_masked AS
SELECT order_id,
       CONCAT(LEFT(mobile,3),'****',RIGHT(mobile,4)) AS mobile,
       IF(role='admin', amount, 0) AS amount_safe,
       dt
FROM iceberg.demo.pii_orders;
```

> 生产建议:直接启用 Ranger column-masking(keyword mask / partial mask),验证插件策略生效
> 后以策略为准;本集群作为教学/交付演示用 Spark 等价物即可。

### 3.6 传输与加密演进清单(登记为差异,不阻塞验收)

| 演进项 | 触发条件 | 步骤 |
|--------|---------|------|
| Ranger KMS(at-rest) | 客户要求磁盘级加密 | 启用 ranger-kms 服务 + HDFS encryption zone |
| TLS(Auto-TLS) | 跨安全域互联 | 给 NN/RM/HS2/Kafka 配证书 |
| Kerberos / Knox SSO | 多租户生产 | 启用 KDC + Knox 网关前置于 WebHDFS/JDBC |

---

## 4. 可靠性与韧性(AWS WAF Reliability)

### 4.1 恢复分级(先判定"重启"还是"重建")

| 故障型态 | 处置 | 依据 |
|---------|------|------|
| 容器存活、服务未起 | 按 Ambari 依赖序重启服务(勿重建容器) | USER-GUIDE §9.1 |
| 宿主机崩溃、容器仍在 | `docker start bigtop_hostnameN`(4 个)后按序拉服务 | 本文 §4.1.1 |
| 容器被删/重建 | 重建后按部署手册走 Ambari 安装(时间长) | USER-GUIDE §2 |
| 单节点坏盘/内存不足 | 缩小 executor/并行度后重提 | 操作手册 §10 |

#### 4.1.1 宿主机崩溃恢复清单(本集群已有实战记录)

```bash
# 1) 起 4 容器(不重建)
docker start bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3
# 2) 逐台确认 2 个底层系统就绪:
docker exec bigtop_hostnameN bash -c 'ls /etc/hadoop/conf/hdfs-site.xml && ls /usr/bigtop/current/*'
# 3) Ambari 按依赖序拉服务(ZK → HDFS → YARN → Hive → HBase…),RANGER_KMS 允许 TIMEOUT 但组件须 STARTED
# 4) 端口基线自检(§2.4 逐项):
docker exec bigtop_hostname0 bash -c 'ss -tlnp | grep -cE ":(50070|8020|8088|9083|10000|6080|8081|9092|2181|16010)"'
```

> 历史复盘(2026-09 本集群):≥4 容器 `docker start` 未重建、13 服务 COMPLETED、
> 端口全活;唯一 RANGER_KMS 报 TIMEOUT,但组件最终 STARTED,不影响其余服务。

### 4.2 备份与复制(Replication Manager 等价)

| 对象 | 方案 | 周期 | 命令/说明 |
|------|------|------|----------|
| 元数据/Hive schema | `mysqldump` HMS 库 | 每日 | §3.5 路线一,落 `/data/exchange/backup/hms` |
| 湖(全量) | HDFS 快照 + distcp | 每日 | 见下 |
| 湖(备份) | distcp 到备份目录 | 每周全量 + 每日增量(distcp 增量 mv) | 见下 |
| Ranger 策略 | REST 导出全部 policy JSON | 变更后 | `GET /service/public/v2/api/policy?service=…` |
| 配置面 | `/etc/hadoop/conf /etc/hive/conf` etc. | 变更后 | tar 归档入 `/data/exchange/backup/conf` |

```bash
# HDFS 快照(轻量、秒级,防误删)
sudo -u hdfs hdfs dfsadmin -allowSnapshot /iceberg-warehouse
sudo -u hdfs hdfs dfs -createSnapshot /iceberg-warehouse snap_$(date +%Y%m%d)
# 对账快照里表数量与源表一致:
sudo -u hdfs hdfs dfs -ls /iceberg-warehouse/.snapshot/snap_$(date +%Y%m%d)/demo
```

```bash
# distcp 每日增量(幂等):
sudo -u hdfs hdfs dfs -mkdir -p /data/backup/lake
sudo -u hdfs hadoop distcp \
  -update -delete -prbugp \
  hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse \
  hdfs://bigtop-hostname0.bigtop.apache.org:8020/data/backup/lake
```

Ranger 策略备份(REST):

```bash
for svc in qixuandata_hadoop qixuandata_hive qixuandata_yarn; do
  curl -s -u admin:Admin1234! "http://localhost:6080/service/public/v2/api/policy?serviceName=$svc" \
    > /data/exchange/backup/ranger/${svc}_$(date +%Y%m%d).json
done
```

### 4.3 容错设计(作业级,落入每条 ETL 的编码规范)

| 层 | 机制 | 落地 |
|----|------|------|
| 流式 | Flink checkpoint ≥30s + exactly-once 语义;Kafka offset 持久化 | `SET 'execution.checkpointing.interval'='30 s'` |
| 流式 | Kafka topic 分区数 ≥ 下游并行度 | topic 建 3 分区(见 §5.2) |
| 批式 | 幂等写入:目标表带 `etl_batch_id`,重跑先删后写或 upsert | §10.2 |
| 湖 | Iceberg ACID:snapshot 失败自动回滚;时间旅行可回退 | §10.3 |
| 对账 | 每批"源行数 vs 湖行数 + 分布指纹"登记 | §12.2 B 组 |

### 4.4 可用性验收(进入 §12.2 前先用此清单)

- [ ] `kubectl/docker ps` 4 容器 Up;
- [ ] 端口基线全部 LISTEN(§2.4 全部端口);
- [ ] 冒烟三连(HS2/Spark ThriftServer/Flink JM)通过;
- [ ] 快照删除演练:`createSnapshot` → 删除一文件 → `deleteSnapshot` 恢复(可选,演示时间旅行回退即可);
- [ ] 备份恢复演练记录(最近一次 distcp 时间戳 + 校验和)。

---

## 5. 性能效率(AWS WAF Performance Efficiency)

### 5.1 分区与文件尺寸(最重要的一课)

- **分区裁剪优先保证 `dt` 进入 WHERE**(`PARTITIONED BY (days(ts))` 或 `(dt)` 二选一,不要混用);
- 目标数据文件 128–512MB(parquet 列存);过小就 `rewrite_data_files`;
- 月/季度维护 cron(建议每日 02:00):

```bash
# hostname1 上以 hdfs 身份执行(已实测的维护过程)
export HADOOP_USER_NAME=hdfs
spark-sql --master yarn --deploy-mode client --num-executors 1 \
  --executor-memory 1024m --executor-cores 1 <<'EOF'
CALL iceberg.system.expire_snapshots('demo.users', TIMESTAMP '2026-09-01 00:00:00');
CALL iceberg.system.remove_orphan_files('demo.users');
CALL iceberg.system.rewrite_data_files('demo.users');
EOF
```

### 5.2 YARN 容量与并行度基线

| 项 | 基线 | 原因 |
|----|------|------|
| 队列 | `root.default`(单队列),容量 100% | 教学环境;生产按域拆队列(见 §9.4) |
| executor | `--num-executors 1 --executor-memory 1024m --executor-cores 1` | 宿主机约 28G 内存,防 ACCEPTED 卡死 |
| 并行度 | Spark 默认取 executor 资源;Flink TM 1 slot | 容器内存受限,勿贪大 |
| 分区 | Kafka topic 3 分区(建 topic 时 `--partitions 3`) | 支持 ≥2 并行消费者 |

```bash
# 确认节点健康(交付验收项):
docker exec bigtop_hostname0 curl -s http://localhost:8088/ws/v1/cluster/nodes \
  | python3 -m json.tool | grep -E '"healthReport"|"state"' | head -10
```

### 5.3 查询优化快查表

| 现象 | 处置 | 验证 |
|------|------|------|
| 大扫描慢 | 加 `dt` 过滤 / 建 `ads_*` 结果表 | `EXPLAIN` 看 partition 剪掉 |
| join 倾斜 | 加盐 / broadcast hint(`/*+ BROADCAST(dim) */`) | 看 stage 耗时 |
| 小文件堆积 | `rewrite_data_files` + 控制并行度 | 对比 Graph 前后 stage 数 |
| Flink 背压 | 看 UI 背压指标,扩 TM 或降并行 | Flink 8081 backpressure |

### 5.4 性能验收(进 §12.2 前置)

- [ ] `demo.users` 经 `expire_snapshots` 后 snapshot count ≤ 保留窗口;
- [ ] `rewrite_data_files` 后数据文件数量下降 ≥ 50%(对比 `SELECT file_path,count(*)…`):
```bash
spark-sql -e "SELECT count(DISTINCT file_path) n_files FROM iceberg.demo.users.files"
```
- [ ] 带 `dt` 条件查询 ≤ 3s(小数据演示)。

---

## 6. 成本优化(AWS WAF Cost Optimization)

### 6.1 存储分层与生命周期

| 温度 | 存储 | 策略 |
|------|------|------|
| 热 | `/iceberg-warehouse`(HDFS) | 正常保留 |
| 温 | 保留 30–90 天快照 | `expire_snapshots` 窗口 |
| 冷 | `/data/cold`(HDFS 冻结目录) | `hdfs dfs -mv`,季度迁移 |
| 归档 | 外部对象存储(⚠) | distcp 出湖 + HDFS 删除前双校验 |

```bash
# 冷数据迁移(演示):
sudo -u hdfs hdfs dfs -mkdir -p /data/cold
sudo -u hdfs hdfs dfs -mv /iceberg-warehouse/demo/archive_2025 /data/cold/
```

### 6.2 计算治理(避免重复算)

- 报表统一读 `ads_*`,禁止各业务自建口径(LAYG 原则:少算多查);
- 共享中间层 `dwd_*` 一次加工、多方消费;
- 批作业调度窗集中在低峰(02:00–06:00),配合 YARN 队列限制并发;
- 流作业 idle 检测:Flink `idle state retention` + 低流量 topic 降并行度。

### 6.3 资产登记与成本打点(数据要素入表/入账的湖侧做法)

参照财政部《企业数据资源相关会计处理暂行规定》(2024 起施行)的"成本归集 + 收益衡量 +
可溯源"要求,湖上建资产台账:

```sql
CREATE TABLE iceberg.demo.asset_register (
  asset_id STRING, dataset_name STRING, owner_domain STRING,
  cost_per_day_usd DOUBLE,     -- 存储+计算分摊(按表打点)
  last_accessed DATE, usage_cnt BIGINT,
  rpo INT, rto INT,            -- 可用性承诺(分钟)
  quality_score DOUBLE,        -- 本表质量得分
  dt STRING
) USING iceberg PARTITIONED BY (dt);
```

### 6.4 成本验收

- [ ] `asset_register` 覆盖所有 `ads_* / key dim_*` 资产(≥5 张);
- [ ] 无重复全量计算(每个源表只一条 ETL,去向登记在 `demo.data_lineage` / `doc/dict.md`);
- [ ] 冷数据目录 `/data/cold` 有迁移记录。

---

## 7. 运维卓效(AWS WAF Operational Excellence)

### 7.1 一切以脚本化/可重复为准

| 运维动作 | 形态 | 状态 |
|---------|------|------|
| 服务启停/恢复 | Ambari + 本文 §4.1.1 清单 | ✅ 文档化 |
| 冒烟三连 | 脚本 `smoke.sh`(USER-GUIDE 附录) | ✅ |
| 湖维护 | 每日 cron:`expire/rewrite/remove_orphan` | ✅ 命令 |
| 备份 | 每日 cron:distcp + mysqldump + Ranger 策略导出 | ✅ 命令 |
| 配置变更 | Ambari + 配置 diff 归档 `/data/exchange/backup/conf` | ⚠ 模板化 |

### 7.2 监控与告警基线(SDX Workload Manager 等价)

| 视图 | 地址 | 关键指标 |
|------|------|---------|
| Ambari | hostname0:8080 | 服务级 alerts(metastore/HS2/NN/RM…) |
| YARN RM | hostname0:8088 | 队列利用率、DAG、NM 状态 |
| Spark History | hostname0:18081 | stage 耗时、GC、shuffle |
| Flink UI | hostname0:8081 | 作业状态、checkpoint、背压 |
| Ranger Audit | hostname0:6080 → Audit | 拒绝次数、异常动作 |
| HDFS | NN 50070 | 容量、复制因子、active NN |

最小告警集(交付基线):NN SafeMode、RM 失联、HMS/HS2 down、Flink job FAILED、
Kafka 分区没有 leader、磁盘 >80%。实现:Ambari 内置 alert + 简版健康脚本。

```bash
# 健康脚本骨架(交付进 opstools/health.sh,crond 每 5 分钟):
for p in 50070 8020 8088 9083 10000 6080 8081 9092; do
  nc -z bigtop-hostname0.bigtop.apache.org $p || echo "DOWN:$p"
done
```

### 7.3 变更管理与复盘基线

- 每次变更记录到 `/data/exchange/backup/change_log.md`(时间/人/内容/回滚方法);
- 已发生的两类重大故障(见操作手册/修复总结)已复盘:
  1) **宿主机崩溃** → 全集群按序恢复(§4.1);
  2) **Iceberg 版本分叉** → Spark 1.6.1/Flink 1.11.0 固化,禁止换 jar(操作手册 §4.1);
  3) **Hive metastore 启动崩**(NoSuchMethodError) → 内存上限/软链修复(USER-GUIDE §8.5)。

### 7.4 运维验收

- [ ] `health.sh` 输出 ≥6/8 端口 UP(重试验证);
- [ ] 最近 1 次变更有 change_log 记录;
- [ ] 最近 1 次湖维护 cron 有成败日志。

---

## 8. 可持续(AWS WAF Sustainability,精简)

- 存储即碳:冷/归档策略(§6.1)同时压降存储与副本;
- 计算即碳:低峰调度窗 + 复用中间层(§6.2)减少重复计算;
- 计费/碳表(可选):在 `asset_register` 增列 `co2_kg_per_day`.

---

## 9. 数据网格对齐(Data Mesh 四原则落地)

### 9.1 领域所有权(Domain Ownership)——按域建库

本集群以 **数据库/命名空间** 为域容器:

| 域 | 命名空间(库) | 归属团队 | 表前缀 |
|----|--------------|---------|--------|
| 交易域 | `demo`(演示)/ 建议 `ods_trade` | 交易团队 | `ods_/dwd_/dws_/ads_` |
| 会员域 | 建议 `dm_member` | 会员团队 | `member_*` |
| 风控域 | 建议 `dm_risk` | 风控团队 | `risk_*` |
| 平台域 | `default` | 平台团队 | 平台系统表 |

> 原则:一个域一个库、一套 owner 账号、一张 `dict.md` 页、一份 Ranger 授权域。

### 9.2 数据即产品(Data as a Product)——产品契约模板

每张对外发布表必须以"数据产品"对待,契约字段在 `dict.md + COMMENT + DDL 约束` 三处落:

```sql
COMMENT ON TABLE iceberg.demo.dwd_order_daily IS
'数据产品:日订单明细 | owner=交易域 | 契约:SLA=日 08:00,质量=行数对账≥99.9%,
schema=冻结(变更走新版本表) | 消费者:报表组/算法组';
```

数据产品验收要点:可发现(dict 里有) · 可理解(COMMENT 有口径) · 可信(quality_score 可查)
· 可接入(Ranger 白名单即"使用登录") · 可演进(版本化 = Iceberg 快照)。

### 9.3 自助数据平台(Self-serve Data Platform)——自助入口表

| 消费方式 | 入口 | 适用 | 授权 |
|---------|------|------|------|
| SQL/报表 | Spark ThriftServer hostname1:10016 | BI/分析师 | Ranger(Hive 库/表/列级)→ 见 §3.2 |
| SQL/Hive | HS2 hostname0:10000 | 传统 Hive 表 | 同上 |
| 文件 | WebHDFS 50070(HTTP) | 外部系统/集成 | Ranger path + ACL 双控 |
| 流 | Kafka 9092(生产/消费) | 外部服务订阅增量 | Ranger kafka 策略(可后续开) |
| 训练 | 共享 HDFS 目录 + 快照版本 | 算法/训练集群 | 见 §11 |

### 9.4 联邦式计算治理(Federated Computational Governance)

两级治理模型(SDX Ranger 单一总纲 + 域自治):

```
全局(联邦):Ranger 中央策略(平台团队维护)── 白名单、脱敏、审计开关
   └── 每域(自治):表 owner 在本库内自主开表、在 dict.md 登记契约、自跑质量对账
```

落地:
- 中央:平台团队维护 `qixuandata_hadoop / _hive / _yarn` 的**全局基线策略**;
- 自治:域团队可申请在本库内加表(Ranger hive 策略按库隔离),全局基线不被覆盖;
- 验收:任一域内新表不得到中央授权即不可被其他域读取(Ranger deny/白名单验证)。

### 9.5 血缘登记(Data Mesh 可溯源 + Atlas 未装时的等价物)

仓库根 `doc/dict.md` 与湖上表 `demo.data_lineage`:

```sql
CREATE TABLE iceberg.demo.data_lineage (
  run_id STRING,                 -- etl_batch_id / job_id
  source STRING,                 -- mysql:<db>.<tbl> / kafka:<topic> / file:<path>
  upstream_table STRING,
  job_name STRING, script_path STRING,
  target_table STRING,
  rows_in BIGINT, rows_out BIGINT,
  ts TIMESTAMP, dt STRING   -- Spark/Iceberg 微秒精度,勿写 TIMESTAMP(9)
) USING iceberg PARTITIONED BY (dt);
-- 每次 ETL 结束时 INSERT 一行 → 血缘可查可审计(可比对 spark history)
```

> 演进:装 Apache Atlas 后,由 Atlas 扫描 HDFS/Hive 直接自动建血缘,本表保留为人工兜底。

---

## 10. 湖仓分层在 Iceberg 的最小可验收落地(Medallion)

### 10.1 分层 DDL 与质量递进

三层递进(bronze→silver→gold)对应本集群 `ods_/dwd_/ads_`。**实测要点**:
Spark 3.5 的 Iceberg DDL **只支持 `NOT NULL`,不支持 `CONSTRAINT ... PRIMARY KEY`**
(语法报错);主键语义由"Flink DDL 的 `PRIMARY KEY (..) NOT ENFORCED`"(upsert 写路径)
或"批侧 MERGE/去重"承担(见 §10.2)。直接可跑:

```sql
-- ============ bronze(贴源,原样+幂等) ============
CREATE TABLE iceberg.demo.ods_orders (
  order_id BIGINT NOT NULL,     -- 主键语义由下游 MERGE/去重承担(Spark 不支持 DDL PK)
  user_id BIGINT, amount DECIMAL(12,2), city STRING,
  src_system STRING,            -- 源系统指纹
  etl_batch_id STRING,          -- 幂等键
  etl_time TIMESTAMP, dt STRING -- Iceberg timestamp 为微秒精度
) USING iceberg PARTITIONED BY (dt);

-- 造样本(2 批,order 3 出现两次,验证去重)
INSERT INTO iceberg.demo.ods_orders VALUES
 (1,11,199.90,'shanghai','mysql:orders','b1',TIMESTAMP '2026-09-10 08:00:00','2026-09-10'),
 (2,12,59.00,'beijing','mysql:orders','b1',TIMESTAMP '2026-09-10 08:01:00','2026-09-10'),
 (3,13,9.90,'beijing','mysql:orders','b2',TIMESTAMP '2026-09-10 09:00:00','2026-09-10'),
 (3,13,9.90,'beijing','mysql:orders','b2',TIMESTAMP '2026-09-10 09:01:00','2026-09-10');

-- ============ silver(清洗/去重/补全,可信明细) ============
-- 保留每单 "最后一次写入"(ROW_NUMBER + etl_time),过掉业务规则(amount>0)
CREATE TABLE iceberg.demo.dwd_order_daily AS
SELECT order_id, user_id, COALESCE(city,'unknown') city, amount, etl_batch_id, etl_time, dt
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY etl_time DESC) rn
  FROM iceberg.demo.ods_orders WHERE amount > 0
) t WHERE rn = 1;
-- 期望:dwd 4 行 → 去重后 3 行(order 3 只留最晚一条)

-- ============ gold(业务结果) ============
CREATE TABLE iceberg.demo.ads_order_city_daily AS
SELECT dt, city, count(*) order_cnt, sum(amount) gmv
FROM iceberg.demo.dwd_order_daily GROUP BY dt, city;
```

### 10.2 质量门(gate)与对账(写进每条批链)

```bash
# 每批落库后跑"源 vs 湖"对账,失败即发告警(骨架):
docker exec bigtop_hostname1 bash -c 'export HADOOP_USER_NAME=hdfs; spark-sql --master yarn --deploy-mode client --num-executors 1 --executor-memory 1024m --executor-cores 1 -e "
-- 1) 行数与金额对账
SELECT count(*) rows_lake, sum(amount) amt_lake FROM iceberg.demo.dwd_order_daily WHERE dt=\"2026-09-10\";
-- 2) 主键唯一性(重复=需要修)
SELECT order_id, count(*) c FROM iceberg.demo.dwd_order_daily WHERE dt=\"2026-09-10\" GROUP BY order_id HAVING c>1;
-- 3) 口径抽查:字段缺失率
SELECT count_if(city IS NULL)*1.0/count(*) miss_rate FROM iceberg.demo.dwd_order_daily WHERE dt=\"2026-09-10\";
"'
```

### 10.3 时间旅行与回刷(Silver/Gold 可回溯的根基)

```sql
-- 查某时点的历史快照(监管/回刷证据):
SELECT * FROM iceberg.demo.dwd_order_daily
  TIMESTAMP AS OF TIMESTAMP '2026-09-09 23:00:00'
  WHERE dt = '2026-09-09';

-- 列出快照,确认 operation 类型:
SELECT snapshot_id, committed_at, operation FROM iceberg.demo.dwd_order_daily.snapshots;

-- 回刷=按旧快照重建新表(不覆盖历史):
CREATE TABLE iceberg.demo.dwd_order_daily_FIXED AS
SELECT * FROM iceberg.demo.dwd_order_daily VERSION AS OF <snapshot_id>;
```

### 10.4 分层验收(Medallion 落地证据)

- [ ] `ods_orders / dwd_order_daily / ads_order_city_daily` 三表实测可建(bronze→silver→gold);
- [ ] 对账 SQL 输出 rows_lake > 0 且无重复主键行(或结果为空);
- [ ] 时间旅行 SQL 返回与当前不同的历史快照(证明可回刷)。

---

## 11. AI 治理与模型监管(watsonx.governance 对齐)

IBM watsonx.governance 的能力模型(出处见附录 C):**Model factsheet + 模型评估 +
漂移/毒性监控 + 全生命周期审计**。本集群用湖面事实表 + 批计算复刻这三件事,
无 watsonx 也可验收 AI 治理闭环。

### 11.1 模型事实表(Model Factsheet 等价)

```sql
CREATE TABLE iceberg.demo.model_factsheet (
  model_id STRING,          -- 全局唯一(如 fraud_xgb_v1.3)
  purpose STRING,           -- 业务目的
  framework STRING,         -- xgboost / transformer / llm-rag
  base_model STRING,        -- 基础模型(如 BGE / 开源 Qwen)
  created_by STRING, owner_team STRING,
  status STRING,            -- registered/evaluated/deployed/retired
  approval_chain STRING,    -- 审批链(如 governance-committee@2026-09-10)
  train_snapshot_id BIGINT, -- 训练集对应的 Iceberg 快照(可复现!)
  eval_metrics STRING,      -- {"acc":..,"auroc":..}
  deploy_env STRING, deploy_dt DATE,
  retired_dt DATE, ts TIMESTAMP, dt STRING  -- Spark/Iceberg:用 TIMESTAMP(微秒)
) USING iceberg PARTITIONED BY (dt);
-- 每次部署/升级=插入一条新版本记录 → model lineage 全部留痕
```

### 11.2 评估与漂移监控(批/流回流)

```sql
-- 在线评估指标逐日回流(评估 = 数据产品契约的一部分):
CREATE TABLE iceberg.demo.model_online_eval (
  model_id STRING, eval_date DATE,
  served_cnt BIGINT, avg_latency_ms INT,
  precision DOUBLE, recall DOUBLE,
  drift_score DOUBLE,        -- 特征/输入分布漂移(KL/PSI 等)
  toxicity_hit BIGINT,       -- 毒性/敏感命中数(RAG 场景)
  dt STRING
) USING iceberg PARTITIONED BY (dt);

-- 漂移告警口径(周环比超阈值即拉起 model_factsheet 走评估):
SELECT model_id, avg(drift_score) d7
FROM iceberg.demo.model_online_eval
WHERE dt >= '2026-09-03' GROUP BY model_id HAVING d7 > 0.05;
```

### 11.3 AI 资产与数据闭环(衔接 §6.3 资产台账)

- 训练数据版本 = Iceberg 快照(`train_set_v1_20260910` 之类),见场景手册 §7;
- 评估回流 = `model_eval` 表(acc/reward per 版本),见场景手册 §7.2;
- AI 过程数据(对话/推理)入湖三张表(`ai_conversations / ai_messages / ai_feedback`)
  见场景手册 §5,为质量审计与再训练提供证据链。

### 11.4 AI 治理验收

- [ ] `model_factsheet` 至少登记 1 个模型,含 `train_snapshot_id`(指向真实快照);
- [ ] `model_online_eval` 有 ≥1 天回流数据,漂移 SQL 可跑;
- [ ] 任一模型"部署/回滚"在表中有状态变更记录(审计证据)。

---

## 12. 交付验收基线(客户验收主清单)

### 12.1 验收前提

- 前置文档就绪:USER-GUIDE、操作手册、场景手册、本文档版本一致(以本文 §0.3 勘误为准);
- 集群健康:`docker ps` 4 容器 UP,端口基线全活;
- 登录凭证:Ranger `admin/Admin1234!`,Ambari `admin`(按部署记录),MySQL `root/ambarirootpass`。

### 12.2 验收用例(逐项可执行 + 期望结果)

**A 组 · 平台与恢复基线**

| # | 操作 | 期望 |
|---|------|------|
| A1 | `docker ps` | 4 容器 Up 3h+ |
| A2 | hostname0 上 `ss -tlnp` | 50070/8020/8088/9083/10000/6080/8081/9092/2181/16010 全部 LISTEN |
| A3 | Beeline 冒烟:`beeline -u "jdbc:hive2://localhost:10000/" -e "SELECT 1"` | 返回 1 |
| A4 | Spark ThriftServer:`echo "SELECT 1" \| beeline -u "jdbc:hive2://localhost:10016/" -n spark` | 返回 1 |
| A5 | Flink JM:`curl localhost:8081/overview` | taskmanagers=1, slots-available≥0 |
| A6 | 恢复演练:停一台容器(刻意),再 `docker start`,按 §4.1 起服务 | ≤N 分钟恢复,端口回基线 |

**B 组 · 数据链路与湖仓分层**

| # | 操作 | 期望 |
|---|------|------|
| B1 | §3.3 建 topic + 生产 3 条 JSON | console 消费能读到 |
| B2 | Kafka→Flink→Iceberg 入湖(§5.2/操作手册 §8.4) | 湖表 `dt` 分区行数增长 |
| B3 | Spark 读 Flink 写入表(`SELECT * FROM iceberg.demo.<表>`) | 行数=写入数(跨引擎互认) |
| B4 | §10.1 bronze→silver→gold 三表 CTAS(样本 4 行含重复) | 建表成功;分层行数=**bronze 4 / silver 3 / gold 2**(实测) |
| B5 | §10.2 对账 SQL | rows_lake=3, amt_lake=268.80, 无重复主键, 缺失率 0(实测) |
| B6 | §10.3 时间旅行 | 历史快照可见且可查 |

**C 组 · 安全与治理**

| # | 操作 | 期望 |
|---|------|------|
| C1 | Ranger 登录 `admin/Admin1234!` | 200(UI 可进) |
| C2 | §3.2 REST 建/查 `icestore_engine_rw` 策略 | 策略在 GET 列表中 |
| C3 | HDFS ACL 兜底 | `getfacl` 含 bi_read r-x |
| C4 | §3.4 审计查证(①HDFS ②Spark ③快照) | 均能看到最近动作(集中审计待 Solr 开通,登记差异) |
| C5 | 收敛验证:停用默认 `all - path` 后,`hive` 读 `/iceberg-warehouse/**` | 被 Ranger 拒绝(非白名单用户) |

**D 组 · AI 与资产治理**

| # | 操作 | 期望 |
|---|------|------|
| D1 | §11.1 `model_factsheet` 可建可查 | 表存在、含 1 行模型 |
| D2 | §9.5 `data_lineage` 有血缘行 | 关联了 job/目标表 |
| D3 | §6.3 `asset_register` 登记 ≥5 资产 | 表有 ≥5 行 |
| D4 | §7.2 `health.sh` 跑一遍 | ≥6/8 端口 UP |

### 12.3 验收报告模板(承重文档,直接交付)

```markdown
# 交付验收报告
集群:HodoopForge · 日期:<date> · 验收人:<role>
## 1) 平台基线  A1–A6      通过/不通过 + 佐证截图
## 2) 数据链路  B1–B6      通过/不通过 + 对账输出
## 3) 安全治理  C1–C5      通过/不通过 + 审计证据
## 4) AI/资产   D1–D4      通过/不通过 + 表行数
## 5) 差异与遗留:参照 §0.3、附录 E(未装组件清单)逐项打钩,注明计划
## 6) 变更记录:本次交付新增的策略/表/脚本清单 + 回滚方法
```

---

## 13. 附录

### 附录 A:端口 / 事实基线(实测修正版)

| 服务 | 端口 | 节点 |
|------|------|------|
| Ambari Web | 8080 | hostname0 |
| NameNode Web / RPC | 50070 / 8020 | hostname0 |
| YARN RM | 8088 | hostname0 |
| Hive Metastore | 9083 | hostname0 |
| HiveServer2 | 10000 | hostname0 |
| Spark ThriftServer | 10016 | **hostname1** |
| Spark History | 18081 | hostname0 |
| Flink JM REST / RPC | 8081 / 6123 | hostname0 |
| Kafka | 9092 | hostname0 |
| ZooKeeper | 2181 | hostname0 |
| HBase Master | 16010 | hostname0 |
| Ranger Admin | 6080 | **hostname0**(旧文档误写 hostname1) |
| MySQL | 3306 | hostname0 |

### 附录 B:版本矩阵与 Iceberg 分叉(交付基线)

| 组件 | 版本 | 关键约束 |
|------|------|---------|
| Hadoop/YARN/HDFS | 3.3.6 | — |
| Hive/Tez | 4.0.1 / 0.10.4 | 注意 timestamp 精度(见操作手册 §10) |
| Spark | 3.5.6 + Iceberg **1.6.1** | **必须 JDK8**;1.7+ 不可用(YARN 容器 class 52) |
| Flink | 1.20.1 + Iceberg **1.11.0** | **JDK17**;需 `HADOOP_CLASSPATH` 与 `--add-opens` |
| Kafka | 3.4.1 | 单 broker,PLAINTEXT |
| Ranger | 2.7.0 | HDFS/YARN/Hive 插件已启用 |
| HBase | 2.6.2 | RS 在 hostname3 |

> 分叉根因与证据:USER-GUIDE §8.7.1。**任何升级/换 jar 必须走变更流程并重跑 A/B 验收。**

### 附录 C:标杆引用出处(官方核实)

| 标杆 | 出处 |
|------|------|
| Cloudera SDX 组件与"一致 policy/schema/metadata" | docs.cloudera.com → CDP Private Cloud Base → Security Overview → "Shared Data Experience (SDX)" |
| CDP Private Cloud Base 7.1.x / 7.3.x 定位 | 同上 + HPE/Cisco 参考架构(CVD,CDP Private Cloud Base 7.1.9) |
| HPE 收购 Cloudera(2025) | HPE/Cloudera 新闻稿与 8-K(SEC EDGAR) |
| AWS WAF 六支柱 | docs.aws.amazon.com/wellarchitected → "The six pillars of the AWS Well-Architected Framework" |
| Databricks Medallion(bronze/silver/gold,推荐非强制) | docs.databricks.com → Data engineering → "What is the Medallion architecture?" |
| Data Mesh 四原则 | martinfowler.com → Zhamak Dehghani,《How to Move Beyond a Monolithic Data Lake to a Distributed Data Mesh》,2019-05-20 |
| IBM watsonx.governance(factsheet/评估/漂移/毒性) | ibm.com/products / watsonx.ai → "Govern AI" / watsonx.governance overview |
| 数据资产入表 | 财政部《企业数据资源相关会计处理暂行规定》(2024 起施行) |

### 附录 D:术语表(交付口径统一)

| 术语 | 本文口径 |
|------|---------|
| SDX | Shared Data Experience;元数据驱动的安全/治理/复制/编排层 |
| 湖仓一体(lakehouse) | 湖(Iceberg)存一切 + 仓(HMS/元数据与约束)管一切 |
| Medallion | bronze→silver→gold 的质量递进分层(推荐非强制) |
| Data Mesh | 域所有权 + 数据即产品 + 自助平台 + 联邦治理 |
| Factsheet | 模型的"营养标签":配置/指标/审批/部署状态一条记录 |
| 数据资产入表 | 把数据资源计入资产负债表(成本/收益/溯源三要素) |
| 联邦计算治理 | 中央策略总纲 + 域内自治(本文 §9.4) |

### 附录 E:未建组件与演进计划(验收时明确"不在本期")

| 组件 | 作用 | 本文等价物 | 演进触发 | 坐标/参考 |
|------|------|-----------|---------|----------|
| Apache Atlas | 自动血缘/分类 | 人工 `data_lineage` 表 + dict | 客户要求仪表盘血缘 | atlas.apache.org |
| Apache Knox | 统一网关/SSO | WebHDFS/JDBC 直连 | 跨安全域/多租户 | knox.apache.org |
| Infra Solr(Ranger audit 后端) | Ranger 集中审计 | HDFS/Spark/Iceberg 三路证据 | 完成交付审计要求即启用 Solr | 启动 INFRA_SOLR 服务即可 |
| Cloudera Data Catalog | 数据目录 | dict.md + COMMENT | 需要搜索/分类 UI | 依赖 SDX |
| Replication Manager | 复制/DR | distcp + 快照 + 策略导出 | RPO/RTO 要求提升 | 依赖 SDX |
| Scheduler 多队列 | 配额隔离 | 单队列 root.default | 多域同时上线 | YARN CapacityScheduler |
| Ranger KMS / TLS / Kerberos | 加密与强认证 | 未启用(登记差异) | 生产化 | 见 §3.6 |
| Milvus / ES / Tika / OCR | RAG 在线检索与解析 | 文件/向量落地(湖) | AI 场景上线 | 见场景手册附录 A |

---

*本文档依据 2026-09 当前集群实测事实撰写;客户验收以 §0.3 勘误与 §12 清单为准,
与旧文档(V0)不再逐字对齐。标杆引用的正确性以附录 C 的官方链接为准,本仓库不转述其原文。*