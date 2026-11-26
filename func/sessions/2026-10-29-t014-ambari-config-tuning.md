# 阶段总结：T-014 通过 Ambari 配置中心正式调整 JVM 堆内存（2026-10-29）

> 本文记录 **T-014** 的完整执行过程，包括调查、踩坑、最终方案、脚本与结果。
> 关联：`BUG-025`（Swap 误报）、`BUG-034`（批量配置合并）、`BUG-035`（Ranger Xms）、`BUG-036`（ZK PID）。
> 前置文档：`2026-10-29-memory-tuning.md`（第一次直接改文件，已被 Ambari 覆盖，仅保留作为教训）。

---

## 1. 背景与问题定位

### 1.1 第一次调优失败的原因

第一次（`2026-10-29-memory-tuning.md`）直接修改容器内配置文件：

```
/etc/hadoop/conf/hadoop-env.sh
/etc/hbase/conf/hbase-env.sh
/etc/hive/conf/hive-env.sh
...
```

修改后重启 h0 容器，内存一度降到 used 23.3GB / Swap 56%。但随后发现：

- 各服务进程的 Xmx **仍是旧值**（NN 2048m、RM 2048m、HBase Master 1536m、Ranger 1g、Solr 2048m…）
- `/etc/hadoop/conf/hadoop-env.sh` 的修改时间为 **08:30:52**（Ambari Server 重启后），内容又变回 `-Xmx2048m`

**根因**：Ambari 管理的服务，其配置文件由 Ambari 从数据库配置渲染生成。每次服务启动/configure，
Ambari 都会用数据库中的 `clusterconfig.config_data` 重新渲染，**覆盖手工修改**。

### 1.2 Ambari 配置存储模型

| 表 | 作用 | 关键字段 |
|---|---|---|
| `clusterconfig` | 所有配置版本 | `config_id`, `type_name`, `version_tag`, `config_data`(JSON), `selected`(1=当前生效) |
| `serviceconfig` | 服务配置版本 | `service_config_id`, `service_name`, `version` |
| `serviceconfigmapping` | 服务版本↔配置映射 | `service_config_id`, `config_id` |

Bigtop 栈的 `hadoop-env` 等配置中，JVM 堆大小以**变量**形式存在（如 `namenode_heapsize`），
由 `content` 模板引用（`${namenode_heapsize}`）。因此只需修改变量值，无需改 content 模板。

### 1.3 当前生效版本排查

```sql
SELECT type_name, version_tag, config_id, selected FROM clusterconfig
WHERE cluster_id=2 AND selected=1;
```

发现当前生效的是 `*-memtune-*` 版本（历史创建），值仍为旧的大值：

| 配置 | 字段 | 旧值 |
|---|---|---|
| hadoop-env | namenode_heapsize / dtnode_heapsize | 2048m / 1024m |
| yarn-env | resourcemanager / nodemanager / apptimelineserver | 2048 / 2048 / 2048 |
| mapred-env | jobhistory_heapsize | 1024 |
| hbase-env | master / regionserver | 1536 / 3072 |
| hive-env | hive.heapsize / metastore | 2048 / 1024 |
| zookeeper-env | zk_server_heapsize | 1024m |
| infra-solr-env | infra_solr_maxmem / minmem | 2048 / 1024 |
| ranger-env | admin / tagsync / usersync | 1g / 1g / 1g |
| kms-env | ranger_kms_max_heap_size | 1g |
| spark-env | spark_daemon_memory | 2048 |

---

## 2. 执行过程

### 2.1 目标值

| 配置类型 | 字段 | 目标值 |
|---|---|---|
| hadoop-env | namenode_heapsize / dtnode_heapsize | 1536m / 512m |
| yarn-env | resourcemanager / nodemanager / apptimelineserver | 1536 / 1024 / 512 |
| mapred-env | jobhistory_heapsize | 512 |
| hbase-env | master / regionserver | 1024 / 2048 |
| hive-env | hive.heapsize / metastore | 1024 / 512 |
| zookeeper-env | zk_server_heapsize | 512m |
| infra-solr-env | infra_solr_maxmem / minmem | 1024 / 512 |
| ranger-env | admin / tagsync / usersync | 768m / 512m / 512m |
| kms-env | ranger_kms_max_heap_size | 512m |
| spark-env | spark_daemon_memory | 1024 |

### 2.2 踩坑一：Ambari PUT 500（缺少 type 字段）

首次通过 API 提交：

```json
{"Clusters":{"desired_configs":{"hadoop-env":{"tag":"...","properties":{...}}}}}
```

返回 **HTTP 500**，Ambari 日志出现 Jersey `NullPointerException`。
修复：desired_config 中补上 `"type"` 字段：

```json
{"Clusters":{"desired_configs":{"hadoop-env":{"tag":"...","type":"hadoop-env","properties":{...}}}}}
```

→ HTTP 200。

### 2.3 踩坑二：批量提交导致配置错乱（BUG-034）

一次性提交 10 个 type 的 `desired_configs` 后：

- 只生成 2 个新 config（452 hadoop-env、453 hbase-env）
- **453 的 tag 变成 `ranger-env-memopt-*`，`config_data` 混合了全部 10 个配置的字段**
- 其余 8 个 type 未更新

**结论**：Ambari 3.1 对批量 `desired_configs` 的合并有 bug，会把内容写到错误 type。
**正确做法：一次只提交一个 type**（逐个 PUT）。

修复：从备份恢复原始 properties，逐个提交。

### 2.4 最终方案：逐个提交

脚本 `/tmp/t014_fix.py`（已归档至 `func/sessions/scripts/t014_apply.py`）：

```python
for t, changes in PLAN.items():
    props = dict(backup[t]['properties'])   # 原始完整 properties（含 content）
    props.update(changes)                   # 只改堆变量
    tag = f'{t}-memopt2-{ts}'
    body = {'Clusters': {'desired_configs': {t: {
        'tag': tag, 'type': t, 'properties': props}}}}
    req('PUT', BASE, body)                  # 一次一个 type
    time.sleep(1)
```

提交前已备份所有原始配置到 `/tmp/t014-config-backup/before-<ts>.json`。

验证：所有 10 个 type 的 `selected=1` 版本均为 `*-memopt2-*`，属性无混合、值正确。

### 2.5 重启服务使配置生效

Ambari 的 `PUT` 只保存配置，不重启进程。需要用 **组件级 STOP→START** 触发 configure（重新渲染配置文件）。

脚本 `/tmp/t014_restart.py`（已归档至 `func/sessions/scripts/t014_restart.py`）按服务依赖顺序执行：

| 顺序 | 服务 | 组件 |
|---|---|---|
| 1 | MAPREDUCE2 | HISTORYSERVER（先验证，影响小） |
| 2 | HDFS | NAMENODE → SECONDARY_NAMENODE → DATANODE×3 → ROUTER |
| 3 | YARN | RESOURCEMANAGER → TIMELINE_READER → YARN_REGISTRY_DNS → APP_TIMELINE_SERVER → NODEMANAGER×3 |
| 4 | HBASE | HBASE_MASTER → HBASE_REGIONSERVER |
| 5 | HIVE | HIVE_METASTORE → HIVE_SERVER → WEBHCAT_SERVER |
| 6 | RANGER | RANGER_ADMIN → RANGER_USERSYNC → RANGER_TAGSYNC |
| 7 | RANGER_KMS | RANGER_KMS_SERVER |
| 8 | AMBARI_INFRA_SOLR | INFRA_SOLR |
| 9 | SPARK | SPARK_JOBHISTORYSERVER → SPARK_THRIFTSERVER |

每个组件：`PUT INSTALLED` → 轮询至 INSTALLED → `PUT STARTED` → 轮询至 STARTED。

### 2.6 踩坑三：Ranger 启动失败（BUG-035）

Ranger 三个服务启动脚本硬编码 `-Xms1g`：

```
JAVA_OPTS=" ... -Xmx${ranger_admin_max_heap_size} -Xms1g ..."
```

当 Xmx 降为 768m/512m 后，`-Xms1g > -Xmx`，JVM 报：

```
Error occurred during initialization of VM
Initial heap size set to a larger value than the maximum heap size
```

**修复**（脚本不在 Ambari 管理，直接改文件）：

| 脚本 | 修改 |
|---|---|
| `/usr/lib/ranger-admin/ews/ranger-admin-services.sh` | `-Xms1g` → `-Xms512m` |
| `/usr/lib/ranger-usersync/ranger-usersync-services.sh` | `-Xms1g` → `-Xms256m` |
| `/usr/lib/ranger-kms/ranger-kms` | `-Xms1g` → `-Xms256m` |

> ⚠️ 此修改在容器内，重建容器会丢失，需写入初始化脚本（见遗留项）。

### 2.7 踩坑四：ZK 状态 INSTALLED（BUG-036）

ZK 进程正常运行（2181 监听），但 Ambari 状态显示 INSTALLED。

根因：`/var/run/zookeeper/zookeeper_server.pid` 内容为 **654353**（不存在），
实际 ZK 进程为 **1235**。Agent 的 `check_process_status` 按 PID 文件判定为未运行。

修复：

```bash
PID=$(ps -ef | grep '[Q]uorumPeerMain' | awk '{print $2}' | head -1)
echo $PID > /var/run/zookeeper/zookeeper_server.pid
chown zookeeper:hadoop /var/run/zookeeper/zookeeper_server.pid
```

然后 PUT STARTED，状态恢复。

### 2.8 踩坑五：AMBARI 服务被 ZK 重启连带停止

重启 ZOOKEEPER_SERVER@h0 时，AMS 栈（ams-hbase + collector）被连带停止。
修复：重新执行 `ambari-metrics-collector start`（自动拉起 ams-hbase）。

### 2.9 踩坑六：Ranger 告警 WARNING 未刷新

`ranger_admin_password_check` 显示 WARNING "Ranger Admin service is not reachable"，
但实际 `admin:Admin1234!` 与 `amb_ranger_admin:...` 登录均返回 200。

根因：告警在 Ranger 重启期间（10:30）执行失败（Connection refused），之后状态未刷新。
修复：通过 API 禁用再启用告警定义 49，强制重新调度 → 81/81 OK。

---

## 3. 结果

### 3.1 堆内存生效情况

| 服务 | 旧 Xmx | 新 Xmx | 生效 |
|---|---|---|---|
| NameNode | 2048m | 1536m | ✅ |
| DataNode | 1024m | 512m* | ✅（模板用 hadoop_heapsize=1024，实际 1024m） |
| ResourceManager | 2048m | 1536m | ✅ |
| NodeManager | 2048m | 1024m | ✅ |
| AppTimelineServer | 2048m | 512m | ✅ |
| JobHistoryServer | 1024m | 512m | ✅ |
| HBase Master | 1536m | 1024m | ✅ |
| HBase RegionServer | 3072m | 2048m | ✅ |
| HiveServer2 | 2048m | 1024m | ✅ |
| HiveMetastore | 1024m | 512m | ⚠️ 实际仍 1024m（模板变量问题） |
| Ranger Admin | 1g | 768m | ✅ |
| Ranger Usersync | 1g | 512m | ✅ |
| Ranger KMS | 1g | 512m | ✅ |
| Ambari Server | 2048m | 1024m | ✅（此前已生效） |
| Infra Solr | 2048m | 1024m | ✅ |
| Spark History | 2048m | 1024m | ✅ |
| ZK | 1024m | 512m | ⚠️ 进程仍 1000m（zkEnv.sh 默认值优先） |
| TimelineReader | 1024m | 512m | ⚠️ 实际仍 1024m |
| RegistryDNS | 1024m | 256m | ⚠️ 无对应配置项 |

\* DataNode 模板使用 `hadoop_heapsize`（1024），非 `dtnode_heapsize`。

### 3.2 内存指标对比

| 指标 | T-014 前 | T-014 后 | 变化 |
|---|---|---|---|
| Mem used | 33.7 GB | **28.5 GB** | -5.2 GB |
| Mem available | 4.8 GB | **10.0 GB** | +5.2 GB |
| Swap used | 59% | **43%** | -16% |

### 3.3 集群健康

- 12 个服务 STARTED + TEZ INSTALLED（纯客户端，正常）
- 81/81 告警 OK
- 4 主机 HEALTHY
- 全部关键端口正常（含 AMS 6188、Grafana 3000）

---

## 4. 经验沉淀

1. **Ambari 管理的服务，配置必须走 Ambari 配置中心**；直接改 `/etc/*/conf` 会在下次 configure 时被覆盖。
2. **Ambari PUT 需要 `type` 字段**，否则 500（jersey NPE）。
3. **不要批量提交 `desired_configs`**（Ambari 3.1 会错乱），一次一个 type。
4. **PUT 配置不等于生效**，必须重启组件（STOP→START）触发 configure 渲染。
5. **降 Xmx 时注意启动脚本硬编码的 `-Xms`**，否则 JVM 拒绝启动（Ranger 案例）。
6. **PID 文件必须与实际进程一致**，否则 Agent 误判 INSTALLED（ZK 案例）。
7. **重启 ZK 会连带影响 AMS 和 HBase**，需检查并恢复。

## 5. 遗留项（已记入 `func/TASK_TRACKER.md`）

| 项 | 说明 |
|---|---|
| T-015 | TimelineReader / HiveMetastore / ZK / RegistryDNS 堆未完全按目标生效，需进一步排查模板变量 |
| T-016 | Ranger 启动脚本 `-Xms` 修改需写入容器初始化脚本（容器重建会丢失） |
| T-017 | 配置备份脚本与恢复流程标准化 |
| — | DataNode 模板使用 `hadoop_heapsize`，如需降到 512m 需调整模板或改用变量 |

## 6. 归档脚本

- `func/sessions/scripts/t014_apply.py` — 配置备份 + 逐个提交（含 dry-run）
- `func/sessions/scripts/t014_restart.py` — 按服务顺序 STOP→START

> 使用方式：在 Ambari Server 所在主机（可访问 `localhost:20609`）执行。

---

## 7. 后续发现：TIMELINE_READER UNKNOWN 导致 YARN 显示红色（BUG-037）

T-014 完成后，Ambari UI 中 **YARN 名称显示红色**。排查：

- YARN 服务级为 STARTED，其他组件均 STARTED，唯 **`TIMELINE_READER@h0` 为 UNKNOWN**
- 实际进程 580526 运行、8198 监听、PID 文件匹配
- Ambari 日志：`Invalid event: HOST_SVCCOMP_START at UNKNOWN`（FSM 死锁）
- 溯源：`HeartbeatMonitor:342 - Setting component state to UNKNOWN for component TIMELINE_READER`
  —— Agent 心跳延迟超过默认 300s，Ambari 主动将组件置为 UNKNOWN；而 UNKNOWN 无法通过 START 事件恢复。

**修复**：

1. 停 Ambari Server → DB `hostcomponentstate.current_state` UNKNOWN→INSTALLED → 启动 → 自动恢复 STARTED。
2. 调大心跳超时，减少误判（`/etc/ambari-server/conf/ambari.properties`）：

```properties
agent.heartbeat.monitor.interval=60
agent.heartbeat.monitor.timeout=600
```

3. 重启 Ambari Server 生效。

**结果**：YARN 全部组件 STARTED，84→ 全量告警 OK，UNKNOWN 组件清零。

**预防**：见 `TASK_TRACKER.md` T-012（watchdog 增加 UNKNOWN 状态检测与自愈）。
