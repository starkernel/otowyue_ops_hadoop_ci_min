# Kerberos 启用事故与回滚记录（2026-11-24）

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


> 结果：**启用尝试失败，已回滚到 `security_type=NONE`；HDFS/Flink/Hive/Kafka 已恢复，HBase 仍不可用**
> 影响窗口：约 2.5 小时（含排障与回滚）
> 关联：T-066 / M-203

## 1. 时间线

| 时间 | 动作 | 结果 |
|---|---|---|
| 20:14 | 保存 Flink savepoint，取消作业 | `savepoint-ff461d-c3d6baabf7d7` |
| 20:15 | 首次 `security_type=KERBEROS` | 400：缺少 KDC admin credential |
| 20:35 | 写入 temporary KDC credential | 成功 |
| 20:36 | 再次 `security_type=KERBEROS` | 请求 1333 完成，keytab 已生成，`security_type=KERBEROS` |
| 20:40 | 重启 HDFS | HDFS 配置变为 kerberos，但 DataNode 无法注册 |
| 20:45–21:20 | 排查 DataNode/NN/JN | 发现 `_HOST` 解析为 `bigtop_hostnameX.ambari3_hodoopforge`，与 Ambari 的 `bigtop-hostnameX.bigtop.apache.org` 不一致 |
| 21:20–21:40 | 为 dn/nn 添加双 principal + keytab | DataNode 仍 `GSS initiate failed` |
| 21:28 | `security_type=NONE` | 请求长时间 PENDING，最终 FAILED，但字段变为 NONE |
| 21:40–22:30 | 手工回滚 core-site/hbase-site、重启 NN/JN/DN | HDFS 恢复 3 DataNode，0 missing |
| 22:30–23:30 | 恢复 Flink/HBase | Flink 作业 `fe6ee153` RUNNING；HBase 仍失败 |

## 2. 根因

1. **主机名不一致**
   - 容器内 `hostname` 是 `bigtop_hostnameX`；
   - Docker DNS 的 canonical name 是 `bigtop_hostnameX.ambari3_hodoopforge`；
   - Ambari/KDC 生成的是 `bigtop-hostnameX.bigtop.apache.org`；
   - Hadoop `_HOST` 替换使用 canonical name，导致 `nn/_HOST`、`dn/_HOST` 与 keytab 不匹配。

2. **Ambari 的 `security_enabled` 未随 `security_type` 回滚**
   - `cluster-env/security_enabled` 仍为 `true`；
   - 即使 `security_type=NONE`，Ambari 重启服务时仍生成 Kerberos JAAS/配置；
   - 这是 HBase 反复失败的主要原因之一。

3. **HBase ZK 状态残留**
   - Kerberos 尝试期间创建了 `/hbase-secure`、`/hbase-unsecure*`；
   - 简单认证的 HBase 创建 znode 时仍报 `AuthFailed`；
   - 需要清理 ZK 路径或使用干净的 znode parent。

## 3. 已回滚/已恢复

| 项 | 状态 |
|---|---|
| `security_type` | `NONE` |
| `cluster-env/security_enabled` | `false` |
| `core-site` | `hadoop.security.authentication=simple` |
| HDFS | 3 DataNode，0 missing，active/standby 正常 |
| Hive | HMS/HS2 端口正常 |
| Kafka | 3 broker 正常 |
| Flink | 作业 `fe6ee153…` RUNNING，checkpoint 正常 |
| Spark | ThriftServer 正常 |
| MySQL | 主/副本正常 |
| HBase | 已恢复（simple 认证 + 独立 ZK 路径 `/hbase-simple-20261124`） |

## 4. HBase 恢复记录（2026-11-24）

- 根因：HBase 进程仍带 Kerberos JAAS / ZK SASL 参数，且旧 `/hbase-*` znode 不可写；
- 处理：`cluster-env/security_enabled=false`、`hbase-env.sh` 去除 JAAS、`hbase-site` 切 simple，
  使用新的 `zookeeper.znode.parent=/hbase-simple-20261124`，手工启动 HMaster 后再启动 RegionServer；
- 结果：16000/16020/16010/16030 均正常，Ambari 100/100 OK。

### 4.1 原残留处理建议

1. 停止 HBase 所有进程；
2. 使用带权限的 ZK 客户端删除 `/hbase-secure`、`/hbase-unsecure*`；
3. 确认 `hbase-env.sh` 无 `zookeeper.sasl.client=true` / JAAS 行；
4. 先启动 HMaster，确认 16000，再启动 RegionServer；
5. 若仍 AuthFailed，检查 ZK 服务端 SASL 与 ACL。

在 HBase 恢复前，数据湖主链路（HDFS/Hive/Kafka/Flink/Spark/MySQL）可用。

## 5. 重试 Kerberos 前必须完成

1. **统一主机名**：容器 hostname / Docker DNS / Ambari hostname 三者一致为
   `bigtop-hostnameX.bigtop.apache.org`（需要重建容器或修改 Docker DNS）；
2. 或在 Ambari 中为每个 `_HOST` 服务配置**显式 principal**（不用 `_HOST`）；
3. `cluster-env/security_enabled` 的回滚/启用必须纳入流程；
4. HBase ZK 路径在启用前清理并验证；
5. 先在单节点/测试集群验证，再全集群切换。

## 6. 结论

本次 Kerberos 启用未成功。KDC/realm/keytab 生成链路是通的，失败点在
**主机名与 `_HOST` 不一致**，以及 Ambari 回滚不完整。  
在修复主机名/显式 principal 之前，不建议再次直接翻 `security_type`。

## 7. 第二次尝试（2026-11-25）

- 已将 4 个容器 hostname 统一为 `bigtop-hostnameX.bigtop.apache.org`，
  并用 Java `InetAddress.getCanonicalHostName()` 验证返回 FQDN；
- 再次执行 `security_type=KERBEROS`（请求 2083）；keytab/配置生成成功；
- 重启 HDFS 时仍失败，`core-site` 在磁盘上仍为 `simple`，Ambari 未按预期应用
  Kerberos 配置，NN/JN 无法形成可用集群；
- 已再次回滚到 `security_type=NONE`，并恢复 HDFS/HBase/Hive/Kafka/Flink/Spark/MySQL；
- 结论：hostname 问题已解决，但 **Ambari 的 `security_type` 单步 API 不能可靠完成
  “配置下发 + 全栈重启”**；必须使用 Ambari Kerberos 向导或分阶段手工迁移。

## 8. 第三次尝试（2026-11-25，HDFS 单服务验证）

- 已确认 4 节点 hostname 为 FQDN，Java canonical name 返回 FQDN；
- 手工把 `core-site`/`hdfs-site` 切到 Kerberos，keytab 为
  `nn|dn|jn/bigtop-hostnameX...`；
- 重启 JN/NN/DN 后，NameNode 8020 可监听，但 DataNode 连接 NN 报
  `EOFException / SASL`，无法注册；
- 立即回滚 `core-site`/`hdfs-site` 到 simple，重启 JN/NN/DN/ZKFC；
- 当前 HDFS 3 DataNode、0 missing，HBase/Hive/Kafka/Flink/Spark/MySQL 正常，
  Ambari 100/100 OK。

结论：即使 hostname 已统一，HDFS 的 Kerberos DataNode 认证仍未打通；
当前 Ambari 生成的 keytab/配置不足以直接启用，需在测试集群或重建镜像上验证。

## 9. 双 principal 验证结果（2026-11-25）

- 执行 `kerberos_align_hosts.sh` 后，DataNode 能登录：
  `dn/bigtop_hostname1.ambari3_hodoopforge@HODOOPFORGE.LOCAL`；
  但 Hadoop 仍使用 Docker DNS 名，而不是 FQDN；
- 以 root + `HDFS_DATANODE_SECURE_USER=hdfs` 启动后 DN 可绑定 1019；
- NameNode 在 Kerberos 模式下仍不稳定，无法稳定形成 3 DataNode 集群；
- 已回滚到 simple，HDFS/HBase/Hive/Kafka/Flink/Spark 全部恢复。

结论：仅修改 Kerberos 的 canonicalization/keytab 还不够，**必须让 Hadoop 不再使用
`_HOST`**。下一步应为每台主机写入显式 principal（`nn/bigtop-hostname0...`、
`dn/bigtop-hostname1...` 等），而不是 `nn/_HOST`。

## 10. 显式 principal 验证（2026-11-25）

按计划为每台主机写入显式 principal（不使用 `_HOST`）：

- h0/h3：`nn/bigtop-hostnameX...`
- h1/h2/h3：`dn/bigtop-hostnameX...`
- JN/HTTP 同样按主机显式配置

结果：

- 使用 `kinit -kt nn.service.keytab nn/bigtop-hostname0...` 成功；
- `hdfs dfs -ls /` 在 Kerberos 模式下成功；
- NameNode h0 active，2 个 DataNode 注册；
- **未通过点**：h1 JN web 报 `Principal not defined in configuration`
  （`hadoop.http.authentication.*` 配置问题）；h1 DataNode 仍出现
  SIMPLE/Kerberos 混用；h3 NameNode 未起来，最终只有 2 个 DataNode。

已回滚到 simple，HDFS 3 DataNode、HBase/Hive/Kafka/Flink/Spark/MySQL 恢复，
watchdog 全绿。  
这证明“显式 principal”方向可行，剩余只需修 JN web auth 与 h1 DN 的认证一致性。
## 11. 显式 principal 第二轮与最终回滚（2026-11-25）

本轮目标是补齐第 10 节剩下的三个点，实际结果如下。

### 11.1 已确认可用

- 统一 web 认证 key 后（`hadoop.http.authentication.*` 与
  `dfs.web.authentication.kerberos.*`），JournalNode 不再报
  `Principal not defined in configuration`；
- 显式 principal 下 `kinit -kt nn.service.keytab
  nn/bigtop-hostname0.bigtop.apache.org@HODOOPFORGE.LOCAL` 成功；
- NameNode 可进入 active，`hdfs dfs -ls /` 在 Kerberos RPC 下成功。

### 11.2 本次暴露的真实故障（与 Kerberos 无关）

验证过程中 NameNode 反复“起来又消失”。根因不是 Kerberos，而是：

- 之前用 Ambari API 把 HDFS 服务置为 `INSTALLED` 以停止 HDFS；
- 该状态残留在 Ambari 中，`ambari-agent` 启动后会按期望状态
  再次停止 NameNode/DataNode；
- 因此手工启动的 NN 会被 agent 周期性杀掉，表现为“Kerberos 不稳定”。

另外，h1 的 RPM 数据库损坏（`BDB0113`/`DB_RUNRECOVERY`），导致
Ambari 的 HDFS `STARTED` 请求在 h1 上失败，进一步放大了问题。

### 11.3 处理

- `rpm --rebuilddb` 修复 h1 RPM 数据库；
- 通过 Ambari 重新将 HDFS 置为 `STARTED`，由 Ambari 下发 simple 配置
  并拉起 JN/NN/DN/ZKFC；
- 结果：h0 Active / h3 Standby，3 DataNode，0 missing；
- HBase、Hive、Kafka、Flink、Spark、MySQL 全部恢复；
- Ambari 告警 96 OK / 4 WARNING（仅磁盘阈值），watchdog 全绿。

### 11.4 结论

HDFS 的 Kerberos 路径已经走到“只差 web 认证与 agent 状态”这一步，
而不是 Kerberos 协议本身不可用。下一轮若继续，必须：

1. 在干净的 Ambari 状态（无残留 `INSTALLED`/停止请求）下做；
2. 先修好 JournalNode 的 web 认证（或者统一改为 HTTP simple，
   仅 RPC 走 Kerberos）；
3. 再验证 3 DataNode，最后才接 HBase/Hive/Flink。

在此之前，集群保持 `security_type=NONE` 与 simple 认证，优先保证业务可用。
## 12. 数据面手工切换结果（2026-11-25）

本轮不再尝试 Ambari 向导，而是逐服务手工切换，结果：

- **HDFS**：3 DataNode、h0 Active / h3 Standby、`put/cat/rm` 成功；
- **HBase**：HMaster + RegionServer，`create/put/get/drop` 成功；
- **Hive**：HMS/HS2 Kerberos，beeline `show databases` / `select 1` 成功；
- **YARN**：RM + 3 NM，`yarn node -list` 全部 RUNNING。

关键修复：

1. 删除 h3 残留的 `dfs.*ns-fed` federation 配置；
2. DN 使用显式 FQDN principal，NN/JN 保留 `_HOST`；
3. YARN RM 的 `yarn.nodemanager.principal` 改为 `nm/_HOST`；
4. `container-executor` 改为 6050 并补 conf 软链；
5. 关闭 Hive ZK killquery / 动态发现，绕开 simple ZK 的 `InvalidACL`；
6. 移除 `hadoop.security.key.provider.path` 与
   `dfs.encryption.key.provider.uri`（无加密 zone），避免客户端反复请求
   Ranger KMS。

未完成：

- Flink 仍尝试 Ranger KMS 委托令牌（404），作业未恢复；
- Kafka 仍 PLAINTEXT，Spark 仍 simple；
- Ambari `security_type=NONE`，手工配置尚未收口。

当前为“部分 Kerberos”状态，详见 `KERBEROS_ENABLEMENT.md` 第 8 节。
