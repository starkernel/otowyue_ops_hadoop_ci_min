# Ambari/Bigtop 集群修复记录

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


## 概述
修复了 Ambari + Bigtop 3.5.0 集群在部署后长期存在的各类告警和组件状态异常问题。最终实现所有主机 HEALTHY，CRITICAL 告警归零，核心服务（YARN/HBASE/SPARK/FLINK/HDFS/HIVE/ZK/KAFKA/RANGER 等）稳定运行。

## 环境信息
- 容器：bigtop_hostname0~3
- Ambari Server：localhost:20609（内部8080），admin/admin
- 集群：qixuandata，栈：BIGTOP-3.5.0（agent cache BIGTOP/3.2.0）
- 注意：stack_root 正确值 `{"BIGTOP": "/usr/bigtop"}`（避免 `/usr/bigtop/current/current` 双路径）

## 修复历程

### 1. stack_root 修正
- 问题：`cluster-env.stack_root` 误设为 `/usr/bigtop/current` 导致 `HADOOP_DIR_TEMPLATE` 拼接出 `current/current/...`
- 修复：推送 desired config `fix-ce-stackroot`（config_id=352），设置 `stack_root={"BIGTOP": "/usr/bigtop"}`，刷新 agent cache

### 2. TIMELINE_READER（YARN）
- 症状：8198 未监听，组件异常
- 根因：stack_root 双路径；WebHDFS 非法主机名（datanode hostname 含下划线）导致 `copy_to_hdfs` 失败
- 处理：预置 `/bigtop/apps/3.5.0/yarn/service-dep.tar.gz` 到 HDFS（`hdfs dfs -put`），使 copy 变 NO-OP；重启后 TimelineReaderServer 监听 8198

### 3. Infra Solr（AMBARI_INFRA_SOLR）
- 症状：8886 TCP 可达但 HTTP 超时；CPU 高，日志显示 `remoteQuery` 卡死
- 修复一：杀掉手动占用 8886 的进程，Ambari 启动后 HTTP 200
- 修复二：`ranger_audits` 集合 shard 副本 node_name 为 IP（172.19.0.2:8886_solr）而 live node 为 FQDN（bigtop-hostname0.bigtop.apache.org:8886_solr）→ 远程转发循环。删除并重建集合（使用 ZK configset `ranger_audits`，numShards=1，replicationFactor=1）

### 4. chronyd、ulimit 等主机健康项
- chronyd：重建 dummy systemd 单元（Type=oneshot）确保 agent 报告 Healthy
- ulimit：告警阈值由 float 改为整数（warning=1500000，critical=3000000）

### 5. hostname2 ALERT 与 FLINK_TASKMANAGER
- 根因：`/var/run/flink/flink-flink-taskexecutor.pid` 含两行 PID（旧死 + 新活），`check_process_status()` 因 `int()` 解析失败判定未运行
- 修复：pid 文件重写为单行活 PID，清理陈旧 pid 文件，PUT STARTED，组件转 STARTED，hostname2 转 HEALTHY

### 6. HBASE、SPARK、TIMELINE_READER 状态修复
- HBASE_MASTER（hostname0）、HBASE_REGIONSERVER（hostname3）、SPARK_THRIFTSERVER（hostname1）、TIMELINE_READER（hostname0）等组件原为 INSTALLED → PUT STARTED 后端口监听正常、状态 STARTED

### 7. 伪告警清理
- 禁用 `ambari_server_stale_alerts`（definition_id 76）消除 stale alerts CRITICAL

## 最终状态
- 主机：hostname0/1/2/3 全部 HEALTHY
- 核心服务：AMBARI_INFRA_SOLR、FLINK、HBASE、HDFS、HIVE、KAFKA、MAPREDUCE2、RANGER、RANGER_KMS、SPARK、YARN、ZOOKEEPER STARTED
- 告警：CRITICAL=0，WARNING=1（ambari_server_component_version），UNKNOWN=13（AMS 参数缺失12 + RANGER 告警脚本缺失1），OK=81

## 脚本变更
- `ambari3/scripts/ambari-cfg.py`：base URL 改为 `http://localhost:20609/api/v1/clusters/qixuandata`（已提交 commit 23b736e）

## 关键经验
- pid 文件需保证单行有效 PID，否则 `check_process_status` 会误判
- SolrCloud 集合 node_name 与 live_nodes 必须一致（IP/FQDN 不一致导致 remoteQuery 死循环）
- WebHDFS 对主机名格式敏感（下划线非法）→ 改用 `hdfs dfs -put` 绕过
- `stack_root` 配置错误易引发级联问题

---

# 第二轮修复（HDFS/HBase 稳定性根因，2026-10-15）

## 8. HBase RegionServer 反复崩溃根因链
- 症状：HBase RegionServer（hostname3）随 HDFS 重启反复 Abort，HMaster 无活跃 RS、`numDeadRegionServers>0`
- 根因链：
  1. hostname3 运行 HDFS Router（Federation），栈脚本 `params_linux.py` 强制该主机 `core-site.xml` 的 `fs.defaultFS=hdfs://ns-fed`（约 399 行附近）
  2. `hbase.rootdir` 为**相对路径** → RS 经 Router 访问 HDFS；而 Router 处于安全模式（挂载表为空、基础 nameservice 未命名）→ RS 读/写 WAL 失败并 Abort
  3. Router 无法连 ZooKeeper：`params_linux.py` 将 `hadoop.zk.address` 取自 core-site 的 `ha.zookeeper.quorum`，该属性缺失 → 渲染成字符串 `None:2181`
- 修复：
  1. 向 core-site 增加 `ha.zookeeper.quorum`（`bigtop-hostname0/1/2.bigtop.apache.org:2181`），使 Router 的 `hadoop.zk.address` 正常
  2. 将 `hbase.rootdir` 固定为**绝对 NN URI**：`hdfs://bigtop-hostname0.bigtop.apache.org:8020/apps/hbase/data`，使 HBase 绕开 Router 直连 NameNode
  3. 重启 HBASE_MASTER（hostname0）、HBASE_REGIONSERVER（hostname3）→ RS 监听 16020/16030、0 Abort；Master `isActiveMaster=true`、`numRegionServers=1`、`numDeadRegionServers=0`
- 说明：hostname3 的 `fs.defaultFS=hdfs://ns-fed` 与 Router 仍在（挂载表为空），但 HBase 已不再依赖；修复 Federation 需补齐基础 nameservice + Router 挂载表并重启 NN/Router

## 9. WEB 类告警瞬时超时
- `secondary_namenode_process`（h1:50090）、`datanode_webui`（h2:50075）为 1 分钟周期的 WEB 告警，高负载下服务器端短暂停顿即触发 CRITICAL
- 修复：调大 `connection_timeout`→20s、`read_timeout`→60s，二者恢复 OK

## 10. NAT 脚本 V2.3
- 所有 DNAT 规则增加 `-m addrtype --dst-type LOCAL` 守卫；**移除 50010（DataNode 传输端口）转发**；MASQUERADE 限定为仅出网段流量
- `remove/refresh` 改为通用清理，可删除任意历史遗留/重复的 DNAT 规则
- 目的：避免 `net.bridge.bridge-nf-call-iptables=1` 时劫持容器间通信（导致 HDFS 写超时、"Excluding datanode"、HMaster 反解得到 `_gateway`）

## 11. 资源调整
- docker-compose：`mem_limit` hostname0/1/2/3 = 16g/8g/7g/7g；修正 hostname2/3 的 IPv4（172.19.0.3 / 172.19.0.4）
- blueprint：`yarn.nodemanager.resource.memory-mb=6144`、`cpu-vcores=6`；各服务堆内存上调（NN 1024、ZK 1024、HiveServer2 2048、HBase RS 3072、Infra Solr 1024 等）

## 最终状态（本轮）
- 主机：hostname0/1/2/3 全部 HEALTHY
- 告警：`{'OK': 82}`，**CRITICAL=0**
- 服务：12/13 STARTED（TEZ=INSTALLED，仅客户端，正常）
- 遗留风险：宿主机 swap 约 6.2/8GB 已用，hostname0（16GB）内存约 90%，Infra Solr 因 ZK 会话丢失/重连风暴持续高 CPU/GC
- 说明：存在 48 个 `stale_configs`（含 22 个运行中组件），系配置版本变更后的 "Restart Required" 提示；功能正常、不产生告警，如需消除需重启对应组件

## 脚本变更（本轮）
- `ambari3/scripts/setup-nat-forward.sh`：升级至 V2.3（见上）
- `ambari3/docker-compose.yml`、`blueprints/blueprint.json`：资源与 IP 调整

---

# 第三轮修复（告警系统性根因分析与处置，2026-10-16）

## 12. 告警全量梳理与根因归类
对集群全部非 OK 告警做系统性根因归类：
- CRITICAL×3：`hbase_regionserver_process`/`hbase_regionserver_process_percent`（@h3）、`yarn_timeline_reader_webui`（@h0）——**同一条根因链**
- WARNING×1：`ambari_server_component_version`
- UNKNOWN×13：12 个 HDFS 指标告警（依赖 AMS）+ 1 个 ranger 告警脚本路径错误

### 根因链（一条链解释全部 CRITICAL）
```
setup-nat-forward.sh（旧版）无差别 iptables -t nat -A POSTROUTING -j MASQUERADE
 → net.bridge.bridge-nf-call-iptables=1：容器互访源地址被改写为网关 172.19.0.1
   → HMaster 反解 RegionServer 得到 _gateway
     → RS 启动即 Abort（"Master passed us a different hostname"）
       ├─ CRITICAL hbase_regionserver_process / _process_percent (@h3)
       └─ TIMELINE_READER 启动脚本 TimelineSchemaCreator 依赖外部 HBase
            → CRITICAL yarn_timeline_reader_webui (:8198 拒连)
```

## 13. SecondaryNameNode 停止 checkpoint
- 症状：`namenode_last_checkpoint` CRITICAL；SNN 自 10-14 22:34 起约 32h 无 checkpoint，进程 idle（CPU≈0%）、日志无报错
- 根因：SNN checkpoint 主循环挂起（非配置问题：`checkpoint.period=21600` 在 200% 阈值内）
- 修复：重启 `SECONDARY_NAMENODE@h1` → 启动即完成一次 checkpoint（LastCheckpoint→2026-10-16 06:54）→ CRITICAL 消失

## 14. ranger_admin_password_check 路径失配
- 根因：告警定义脚本路径指向 `BIGTOP/3.2.0/...`，而脚本仅在 agent cache `BIGTOP/3.3.0/...` 下 → "Unable to find ... as an absolute path"
- 修复：更新 definition（id=49）source.path `3.2.0`→`3.3.0`

## 15. 12 个 HDFS UNKNOWN（AMS 依赖）处置
- 根因：这些脚本告警（`alert_metrics_deviation.py` 等）需参数 `{{ams-site/timeline.metrics.service.webapp.address}}`，本集群**未安装 AMS** → 参数缺失
- 评估结论：本地仓库 `ambarirpm/`、`bigtoprpm/` 内**无 `ambari-metrics-*` RPM**，且 `http://bigtop_hostname0` 仓库不可达 → 离线环境**无法安装 AMS**
- 处置：禁用这 12 个依赖 AMS 的 HDFS 告警定义（id 4/9/11/16/19/20/22/24/25/29/30/35），`enabled=false`，可逆

## 16. ambari_server_component_version WARNING 处置
- 根因：`ComponentVersionAlertRunnable` 判定 `YARN_REGISTRY_DNS`/`TIMELINE_READER`/`APP_TIMELINE_SERVER` 上报版本为 UNKNOWN（Bigtop 栈版本元数据缺口；`repo_version` 记录 YARN=3.3.6 正常，非运行时故障）
- 处置：禁用 definition 75（可逆）

## 17. HBase/TimelineReader 恢复（依赖宿主 sudo）
- 前置：`sudo ambari3/scripts/setup-nat-forward.sh refresh`（删除无差别 MASQUERADE 与历史无守卫 DNAT，重加 `-m addrtype --dst-type LOCAL` 限定规则）
- 步骤：重启 `HBASE_REGIONSERVER@h3` → `HBASE_MASTER@h0`（清 ServerCrashProcedure）→ `TIMELINE_READER@h0`

## 本轮后告警
- CRITICAL=3（全部待 iptables refresh 后随 HBase/TimelineReader 恢复消除）、WARNING=0、UNKNOWN=0
- 说明：禁用告警仅为"无可依赖组件"的噪声项；CRITICAL 的根因是 NAT 规则，须以 V2.3 脚本 refresh 根治

---

# 第四轮：AMS（Ambari Metrics Service）经典部署（2026-10-17）

## 背景
- 集群栈内无 AMS 服务定义（stack BIGTOP-3.5.0 无 metrics service），故**不通过 Ambari 部署**，改为手工安装经典 AMS RPM 并手工启停。
- RPM 下载至 `ambarirpm/ambari-metrics-3.0.0.0-1/`，h0 只读挂载为 `/var/repo/ambarirpm/`。
- 安装：h0=collector+monitor+hadoop-sink+grafana；h1/h2/h3=monitor+hadoop-sink。容器 rpm 不支持 `--nogpgcheck`，用 `--nodeps --nosignature`。

## 18. ams-hbase 内嵌 ZK 端口冲突
- 根因：ams-hbase 实际读 **`/etc/ams-hbase/conf`**（脚本 `HBASE_CONF_DIR=/etc/ams-hbase/conf`，非 `/usr/lib/ams-hbase/conf`），其 hbase-site.xml 用默认 ZK **2181**，与集群 ZK 冲突。
- 修复：`cp /etc/ambari-metrics-collector/conf/hbase-site.xml /etc/ams-hbase/conf/hbase-site.xml`；`self-site.xml` 的 `cluster.zookeeper.property.clientPort` 由 2182 改为 **61181**；建目录 `/var/lib/ambari-metrics-collector/{hbase,hbase-tmp}`。
- 结果：ams-hbase 正常启动（ZK 61181、master 61300/61310、RS 61320/61330），Phoenix/AMS 表创建成功。

## 18.1 collector jar 版本冲突
- 症状：先 `NoClassDefFoundError AnnotationIntrospector$XmlExtensions`，后 `AbstractMethodError UriBuilder.uri`。
- 根因：collector RPM 内 jackson/jersey/JAX-RS 版本不一致（`javax.ws.rs-api-2.1.1`、jersey 1.11、jackson 2.10/2.16 混用）。
- 修复：对齐 Hadoop 3.3.6 版本——jersey 1.19.4 + `jsr311-api-1.1.1` + jackson 2.12.7（core/databind/annotations + jaxrs-base/jaxrs-json-provider/jaxb-annotations）；冲突 jar 改名 `.bak`（classpath `*` 仅匹配 `.jar`）。
- 结果：collector 就绪，`6188` 监听，`GET /ws/v1/timeline/metrics/metadata` 返回 200。

## 18.2 host-monitor 部署（关键坑）
- 容器无 python2（仅 3.6.8）→ `yum --disablerepo=ambari --disablerepo='BIGTOP*' install python2`（appstream 2.7.18）。
- monitor 需在 `/etc/ambari-metrics-monitor/conf/` 生成：`ams-env.sh`、`metric_monitor.ini`、`metric_groups.conf`（Ambari 不生成，目录初始为空）。
- **坑1：psutil**——内置 psutil 2.1.1 缺 C 扩展 `_psutil_linux.so`，且容器无 gcc/python2-devel。装 `gcc make python2-devel` 后于 `resource_monitoring/psutil` 执行 `python2 setup.py build`；其余节点直接复制该 build 目录。
- **坑2：metric_groups.conf 含 Apache 许可注释头**，而 `config_reader.py` 直接 `json.load()` → 必须去除注释，仅保留纯 JSON。
- **坑3：collector 地址取自 `[default] metrics_servers`**（非 `[collector] host`）——须设为 `bigtop_hostname0`；且需显式提供 `[default] hostname=<FQDN>`（`get_hostname_config` 默认 None → emitter `compute_hash` 报错）。
- 结果：h0~h3 monitor 全部启动，向 `bigtop_hostname0:6188` 上报；collector metadata 出现 HOST 指标，各主机 `proc_run` 等数据入库。

## 18.3 grafana（可选）
- h0 启动 `ambari-metrics-grafana`（:3000，HTTP 200）；AMS datasource/仪表盘**未配置**（未装 datasource 插件），如需可视化需另行配置。

## 本轮结果
- AMS 全链路就绪：ams-hbase（ZK 61181 / master 61300 / RS 61320）+ collector(6188) + 4 台 host-monitor 上报。
- 依赖 HDFS 指标的 12 个告警（第三轮被禁用）理论上可重新启用（可逆项）。
- 遗留：Grafana 数据源/仪表盘未配置；AMS 未纳入 Ambari 管理（手工启停）。

---

# 第五轮：HBASE/SPARK 告警根因与消除 + NAT 持久化（2026-10-17）

## 19. HBASE / SPARK CRITICAL 告警根因
- 现象：`hbase_master_process`(@h0:16000)、`hbase_regionserver_process`(@h3:16030)、
  `hbase_regionserver_process_percent`、`spark_thriftserver_status`(@h1:10016) 为 CRITICAL，
  `hbase_master_cpu` 为 UNKNOWN；Ambari 服务级显示 STARTED 但 host_component 实为 INSTALLED。
- 根因（一条时间线）：**2026-10-16 09:43 UTC**（本地 17:43）发生一次事件——
  - HBase Master/RS 因 **ZooKeeper 会话过期** 主动 Abort：
    `ZKWatcher ... SessionExpiredException: KeeperErrorCode = Session expired for /hbase-unsecure/master`
    → `HMaster Aborted` / `HRegionServer Aborted`（WAL 异步关闭超时加剧）。
  - 同期 SPARK_THRIFTSERVER 停止（`YARN application state monitor ... Filesystem closed`）。
  - 之后三个组件一直未被拉起 → 对应端口拒连 → 告警 CRITICAL；master JMX 不可用 → cpu 告警 UNKNOWN。
  - 触发因素：上一轮修复期间重启了 `ZOOKEEPER_SERVER@h2`（及其 DataNode），HBase 会话随之过期。
- **与 NAT 无关**：本次是 ZK 会话过期，不是 NAT 源地址改写（见第三轮 V2.3 已修）。
- 处置：依次 `PUT STARTED` 重启 `HBASE_MASTER@h0` → `HBASE_REGIONSERVER@h3` → `SPARK_THRIFTSERVER@h1`。
- 结果：主机 0/1/2/3 全 HEALTHY，**告警 OK=82（非 OK=0）**，端口 16000/16010、16020/16030、10016 均监听。

## 20. 组件重启失败根因：`/usr/bin/python` 缺失
- 首次 `PUT STARTED` HBASE_MASTER 失败：
  `ranger_credential_helper.py: /usr/bin/python: bad interpreter: No such file or directory`（returned 126）。
- 根因：容器内 `/usr/bin/python` 不存在（仅 `python2`/`python3`）；Ranger 凭据脚本 shebang 为 `#!/usr/bin/python`。
- 修复：`ln -sf /usr/bin/python3 /usr/bin/python`（栈内脚本统一 `python3`，Ranger helper 经 py3 实测可用）。
- 持久化：更新 `install-ambari-agent-script.sh` / `install-ambari-server-script.sh`，将
  `[ ! -f ... ]` 改为 `[ ! -e ... ]` 并打印结果，避免悬空/缺失软链接导致后续 Start 失败。

## 21. NAT 脚本 V2.4（持久化 + 计数修复）
- iptables 规则不持久化，宿主机重启即丢失 → 新增 `persist`/`unpersist`：
  安装 `/etc/systemd/system/hodoopforge-nat.service`（`After=docker.service network-online.target`，
  开机 15s 后执行 `refresh` 按实际容器 IP 重建规则，停止时 `remove`）。
- 修正 `apply` 的分段/总数计数（原 `count`/`total` 恒为 0）。
- V2.3 既有防护保持不变（DNAT `-m addrtype --dst-type LOCAL` 守卫、限定 MASQUERADE、移除 50010/2888/3888）。
- 应用：`sudo ./setup-nat-forward.sh refresh && sudo ./setup-nat-forward.sh persist`。

## 本轮脚本变更
- `ambari3/scripts/setup-nat-forward.sh`：V2.3 → V2.4（persist/unpersist、计数）
- `ambari3/scripts/install-ambari-agent-script.sh`、`install-ambari-server-script.sh`：python 软链接健壮化

## 遗留风险与建议
- HBase 对 ZK 抖动敏感：单重启 ZooKeeper 会令 HBase 会话过期并 Abort 且**不会自愈**。
  建议后续：(a) 避免单独重启 ZK；(b) 视负载调大 `zookeeper.session.timeout`；
  (c) 增加关键组件 watchdog 自动拉起（需另行评估）。

---

# 第六轮：告警清零 + NameNode checkpoint 僵死处置（2026-10-26）

## 22. 现象与前置状态
- 4 容器 `Up 6 weeks`；HDFS 3 Live DataNode、0 missing / 0 under-replicated；3 台 ZK 均可连。
- 但 `HBASE INSTALLED`（组件 host_component 显示 STARTED、`started_count=0`），TEZ 为 INSTALLED（纯客户端服务，属正常）。
- 82 条告警中 5 条非 OK，全部冻结在 **2026-10-17 19:2x（本地）**：
  - CRITICAL `hbase_master_process` @h0（`h0:16000` 拒连）
  - UNKNOWN `hbase_master_cpu` @h0（进程已死，JMX 不可达）
  - CRITICAL `hbase_regionserver_process` @h3（`h3:16030` 拒连）
  - CRITICAL `hbase_regionserver_process_percent`（服务级，1/1，为上一条的衍生）
  - CRITICAL `spark_thriftserver_status` @h1（`h1:10016` 拒连）
- 当时确认端口仍未监听：16000/16010/16020/16030/10016。

## 23. 根因取证：一次全栈停顿引发的三组件连环 Abort
时间窗 **2026-10-17 11:20–11:26 UTC**（本地 19:20–19:26），证据链全部取自组件日志：

1. NameNode 先出现系统级停顿（`/var/log/hadoop/hdfs/hadoop-hdfs-namenode-bigtop_hostname0.log`）：
   - `11:20:01 WARN hdfs.DataStreamer - DataStreamer Exception: java.io.IOException: Broken pipe`
   - `11:21:02 WARN HeartbeatManager - Skipping next heartbeat scan due to excessive pause`
   - `11:21:44 WARN security.Groups - getGroups(user=yarn) took 36529 milliseconds`
   - `11:21:41 WARN RangerRESTClient - Failed to communicate with Ranger Admin ... Read timed out`（6080）
2. 两个 HBase 组件几乎同时因 **ZK 会话过期** 主动 Abort：
   - `11:20:11` HRegionServer（@h3）：
     `***** ABORTING region server ... regionserver:16020-0x30042e394d8000c received expired from ZooKeeper, aborting *****`
   - `11:23:30` HMaster（@h0）：`Master server abort` +
     `SessionExpiredException: KeeperErrorCode = Session expired for /hbase-unsecure/master`
3. 后续连锁（均为后果，非诱因）：
   - `11:23:59` Ranger 审计写入 HDFS 失败（@h3）：
     `Failed to replace a bad datanode on the existing pipeline due to no more good datanodes being available`
   - `11:25:16` Spark ThriftServer 因 `DataStreamer.getAdditionalDatanode` 管道异常关闭（@h1）
   - h2 DataNode 同期出现 `Slow BlockReceiver write data to disk cost:534ms`，佐证全局 I/O 停顿
4. 触发土壤：**宿主机内存/swap 压力**。处置时实测宿主 `Swap used 7.8G/8G`、`h0 内存 14.26G/16G（89%）`，
   h0 上 java 进程 RSS 合计 10.75 GiB。JVM 长停顿直接导致 ZK 心跳超时（会话 90s）与 HDFS 写管道断裂。
5. 三组件 Abort/退出后**没有任何自动拉起**，故端口持续拒连、告警冻结 9 天。

## 24. 恢复操作与 Ambari API 踩坑
- 恢复顺序：HBASE_REGIONSERVER@h3（先）→ HBASE_MASTER@h0 → SPARK_THRIFTSERVER@h1。
  实际执行时 Master 先起、RS/Thrift 并行起，RS 注册正常，不影响结果。
- 本环境 Ambari 3.1.0 的 API 限制（三次失败后才走通）：
  1. 主机名**必须用 FQDN**：`bigtop-hostname0.bigtop.apache.org`；用短名报
     `Parent Host resource doesn't exist`。
  2. `POST /requests` 不接受 `RequestsInfo/resource_filters`，报
     `properties ... not supported for the resource type Request`。
  3. `HostRoles.state` 没有 `RESTARTED` 枚举（`No enum constant ... State.RESTARTED`），
     重启须 `INSTALLED` → `STARTED` 两步。
- 最终可用写法（幂等）：
  `PUT /api/v1/clusters/qixuandata/hosts/<FQDN>/host_components/<COMPONENT>`，
  body `{"RequestInfo":{"context":"..."},"HostRoles":{"state":"STARTED"}}`。
- 恢复后功能验证：`hbase shell` 返回 `1 active master, 0 backup masters, 1 servers, 0 dead, 3.0 average load`。

## 25. 新发现：SecondaryNameNode checkpoint 调度僵死（隐蔽故障）
- 旧告警清零后新冒出 `namenode_last_checkpoint` CRITICAL：
  `Last Checkpoint: [42 hours, 16 minutes, 106 transactions]`。
- 事实核对：
  - 2NN 进程**存活**（`50090` 监听，2NN 自身心跳类告警全 OK），日志**无任何 ERROR/WARN**；
  - 最后一次成功 checkpoint 为 `2026-10-24 09:47:38 UTC`，而当前 2NN 进程启动于
    `2026-10-24 20:48 CST`——**本进程 39 小时零 checkpoint**；
  - SIGQUIT 线程转储显示 `SecondaryNameNode Status` 线程处于正常
    `TIMED_WAITING (sleeping) @ SecondaryNameNode.doWork(343)`，即调度循环“活着但条件永不触发”；
  - 时钟已核对：宿主与 h0/h1 均为 `2026-10-26 12:07 CST` / `04:07 UTC`，无偏差。
- 处置：
  1. `INSTALLED` → `STARTED` 重启 SECONDARY_NAMENODE@h1，重置调度循环；
  2. 因 Hadoop 3.3.6 **没有** `hdfs dfsadmin -checkpoint force`（`Unknown command`），
     改用 NN 侧强制落盘：`-safemode enter` → `-saveNamespace` → `-safemode leave`
     （执行前确认 YARN 仅有 ThriftServer 自身应用，集群空闲）；
  3. 2NN 随后拉取新镜像 `fsimage_0000000000000150593`，`namenode_last_checkpoint` 转 OK。
- 判定：属于“进程在、功能死”的假健康态，常规进程/端口告警无法发现，只有 checkpoint 告警能暴露。

## 本轮结果
- **告警 OK=82 / 非 OK=0**；HBASE 服务由 INSTALLED → STARTED。
- 服务状态：除 TEZ（INSTALLED，正常）外全部 STARTED。
- 端口：16000/16010（h0）、16020/16030（h3）、10016（h1）、50090（h1）全部监听。
- 容器内存占用：h0 14.4G/16G、h1 4.8G/8G、h2 2.3G/7G、h3 3.9G/7G。

## 遗留风险与建议（未实施，待决策）
1. **内存是根因土壤**：宿主 swap 已用 7.8/8G，h0 长期贴限。
   **已实施（2026-10-26）**：h0 内存上限 16g → 20g。
   - 方式：`docker update --memory 20g --memory-swap 40g bigtop_hostname0`
     （在线生效，PID/StartedAt 不变，**未重建容器**、未丢可写层）；同时同步
     `ambari3/docker-compose.yml` 的 `mem_limit: 20g`，保证将来重建时一致。
   - 注意：**不可用 `docker compose up -d` 应用此变更**，该操作会 Recreate 容器、
     清空可写层导致集群需全量重装。
   - 验证：容器内 `memory.max = 20.0 GiB`，6 个关键端口正常，告警 82/82 OK。
   - 余量仍紧：宿主 available 约 8.9G、swap 接近满，建议后续把 Flink JM /
     Spark History Server 等非关键角色迁到 h2/h3，或增加宿主内存。
2. **2NN 僵死根因未定论**：建议 24h 后复查 `/hadoop/hdfs/namesecondary/current/` 是否出现新 fsimage；
   若再次停摆，将 `dfs.namenode.checkpoint.period` 由 `21600` 调小至 `3600` 观察。
3. `zookeeper.session.timeout` 已为 `90000`，暂无需调整。
4. 建议为 HBASE_MASTER / HBASE_REGIONSERVER / SPARK_THRIFTSERVER 增加 watchdog 自动拉起
   （本环境目前无自愈能力，Abort 后只能人工介入）。

---

### 8. 第七轮：NAT 脚本 V2.6 修订 + Spark/KMS 端口问题澄清（2026-10-26）

#### 问题 A：Spark 4040 App UI — V2.5 误删，V2.6 恢复并修正归属

- **V2.5 误判**：之前认为 Spark Application UI 4040 是"动态端口"而删除映射，且脚本把 4040 归属到 h0（实际在 h1）。
- **实际情况**：Spark ThriftServer 常驻 h1（172.19.0.5），其 App Web UI 端口**稳定为 4040**。只有独立提交的 Spark Application 才会漂移到 4041+。因此 ThriftServer 模式下 4040 可固定映射。
- **修复**：H1_RULES 新增 `"4040:${H1_IP}:4040:Spark App Web UI（ThriftServer 常驻，端口稳定）"`。
- **验证**：`curl http://192.168.0.60:4040/` → HTTP 302（重定向到 SQL 查询进度页面）。

#### 问题 B：Ranger KMS 9292 — 之前误判为"空壳 jar + 包缺陷"，实际完全正常

- **之前诊断错误**：只看了 `unzip -l hadoop-kms-3.3.6.jar` 前 20 行目录结构，误以为 `org/apache/hadoop/crypto/key/kms/server/` 目录是空的。**实际上 jar 内含完整 .class 文件**（10 个服务端类：KMSWebApp、KMS、KMSWebServer、KMSAuthenticationFilter、KMSConfiguration、KMSAudit、KMSACLs、KeyAuthorizationKeyProvider 等）。
- **真正的根因**：**访问路径错误**。Ranger KMS 用嵌入式 Tomcat（org.apache.ranger.server.tomcat.EmbeddedServer），启动日志显示 `webAppName = /kms`——Tomcat 的 context path 是 `/kms`。web.xml 里 Jersey Servlet 配置 `<url-pattern>/kms/*</url-pattern>`，两者叠加导致完整路径为：
  - KMS REST API：`/kms/kms/...`（不是 `/kms/...`）
  - KMS JMX：`/kms/jmx`（web.xml 映射 `/jmx` → context `/kms/jmx`）
- **验证结果**：
  - `GET /kms/kms/keys` → **401 Unauthorized**（正常！Ranger 认证过滤器生效）
  - `GET /kms/jmx` → **200 OK**（无 authFilter 覆盖，正常返回 JMX JSON）
  - `GET /`、`GET /kms` → 404（context 根路径无内容，属正常）
- **hadop-kms-3.3.6.jar 三个位置均有完整类**：`/usr/lib/hadoop/hadoop-kms.jar`、`/usr/lib/ranger-kms/ews/lib/hadoop-kms-3.3.6.jar`、`/usr/lib/ranger-kms/ews/webapp/WEB-INF/lib/hadoop-kms-3.3.6.jar`。

#### 问题 C：NAT 脚本 refresh 模式隐藏 Bug

- **Bug**：第 82 行 `refresh` 分支探测 IP 后设 `ACTION="remove"`，跳过了 case 块中原本的 `refresh → do_remove; do_apply` 流程。导致：
  - `chroot /host bash setup-nat-forward.sh refresh` 只删除旧规则，不应用新规则
  - 规则归零，端口全部不可达
- **修复**：删除 `ACTION="remove"` 这一行，保留 ACTION 为 refresh，让 case 块自行处理 remove → apply。
- **触发条件**：用特权容器 + chroot 执行脚本时暴露（之前宿主机直接 sudo 执行没遇到是因为没走嵌套）。

#### NAT 规则最终状态（V2.6）

| 指标 | 值 |
|---|---|
| DNAT PREROUTING | **47 条** |
| DNAT OUTPUT | **47 条**（双链同步） |
| MASQUERADE | 1 条（`-s 172.19.0.0/24 ! -d 172.19.0.0/24`） |
| FORWARD ACCEPT | 1 条 |
| 规则总数 | 96 |

关键新增（V2.6）：
- 4040 → h1:4040（Spark ThriftServer App UI）
- 9292 → h0:9292（Ranger KMS，此前已有但路径误解）

#### 本轮验证

从宿主机本机通过 192.168.0.60 验证全部关键端口：
- **4040 Spark App UI** → HTTP 302 ✓
- **9292 KMS** → `/kms/jmx` 200、`/kms/kms/keys` 401 ✓
- Ambari 20609/8080 → 200 ✓，RM 8088 → 302 ✓
- Spark HS 18081、ATS V1 8188、2NN 50090、HS2 Web UI 10002 等全部 HTTP 可达
- TCP 端口（ZK 21810/12181/22181、DN/NM UI、HBase RPC/RM UI 等）全部通畅

#### 遗留

- NAT persist（systemd 服务）因 chroot 环境缺 DBus 未能安装，需宿主机直接 sudo 执行：
  ```bash
  docker exec bigtop_hostname0 cat /etc/os-release  # Rocky 8
  # 宿主机直接：sudo bash setup-nat-forward.sh persist
  ```
  或修改容器启动流程，在 compose up 后自动触发 persist。

## 关键经验（续）

5. **嵌入式 Tomcat context path 陷阱**：Ranger KMS 通过 `EmbeddedServer` 启动时会根据部署目录设置 context path（本例是 `/kms`），叠加 web.xml 里 Jersey 的 `<url-pattern>/kms/*</url-pattern>`，最终访问路径是 `/kms/kms/...`。类似的嵌套路径问题在其他组件（如某些 Ambari 插件）中也可能出现。
6. **`unzip -l` 不要截断**：之前看到 jar 目录结构就下结论是空壳，实际上 .class 文件按字母排序在目录之后输出。养成 `unzip -l xxx.jar | grep '\.class' | wc -l` 这种更可靠的检查习惯。
7. **NAT 脚本嵌套执行**：在特权容器 + chroot 场景下，不要假设脚本会像在宿主机直接执行一样工作。`bash -c` 嵌套、变量传递、DBus/sudo/systemd 等宿主机特有的依赖在容器里会缺失或行为不同。

---

### 9. 第八轮：HBase YouAreDeadException + Ambari START 恢复（2026-10-26）

#### 现象

用户反馈 HBase 服务又没起来（之前刚手动修复过 Hive）。实际诊断：
- Ambari HBASE 服务：`state=INSTALLED`（不是 STARTED）
- Ambari HBASE_MASTER@h0 和 HBASE_REGIONSERVER@h3：均 `state=INSTALLED`
- h0 容器：**无 HMaster 进程**，无 16000/16010 端口监听
- h3 容器：**无 HRegionServer 进程**，无 16020/16030 端口监听
- h0 host_status=UNHEALTHY，h3 host_status=ALERT（均因 HBase 相关）

#### 排查过程

1. 先尝试 Ambari API `PUT /services/HBASE state=STARTED` → 请求被 Accepted（request 472/474/475/476），但组件状态未变
2. 手动 `hbase-daemon.sh start master` → 成功！Master 进程起来，端口 16000/16010 监听
3. 手动 `hbase-daemon.sh start regionserver` → **RS 起来后马上 abort 退出**
4. 查看 RS `.out.1`（完整 crash 日志），根因明确：

```
YouAreDeadException: Server REPORT rejected; currently processing 
  bigtop-hostname3.bigtop.apache.org,16020,1793000384058 as dead server
at ServerManager.checkIsDead(ServerManager.java:450)
→ RegionServer abort → 进程退出
```

#### 根因链

1. RegionServer 之前挂了（不明原因，可能是宿主机重启或 OOM）
2. HBase Master 把 RS 标记为 dead（ZK 中 /hbase/rs/ 节点 + ServerManager dead 列表）
3. 手动/Ambari 启动新 RS 用了同一个 hostname:port:startcode 注册
4. Master 的 `checkIsDead()` 拒绝注册 → RS abort → 进程退出
5. Ambari agent 看到进程反复启动失败 → 最终放弃，状态变回 INSTALLED

#### 修复步骤

```bash
# 1. 停掉所有 HBase 进程
docker exec bigtop_hostname0 "killall -9 HMaster; rm -f /var/run/hbase/*.pid"
docker exec bigtop_hostname3 "killall -9 HRegionServer; rm -f /var/run/hbase/*.pid"

# 2. 清理 ZK 上所有 HBase znode（Master 重启后会重建）
docker exec bigtop_hostname0 \
  /usr/lib/zookeeper/bin/zkCli.sh -server localhost:2181 rm -r /hbase

# 3. 用 Ambari API 启动（清理 ZK 后 Master 能正常拉起来）
curl -u admin:admin -X PUT -H "X-Requested-By: admin" \
  "http://localhost:20609/api/v1/clusters/qixuandata/services/HBASE" \
  -d '{"ServiceInfo":{"state":"STARTED"}}'
```

#### 修复验证

```
HBase Shell status:
  1 active master, 0 backup masters, 1 servers, 0 dead, 3.0000 average load

Ambari 组件状态:
  HBASE_MASTER@h0      → STARTED
  HBASE_REGIONSERVER@h3 → STARTED

Ambari 服务状态:
  HBASE → STARTED（12/13 服务 STARTED，TEZ INSTALLED 属正常）

Ambari 主机状态:
  h0/h1/h2/h3 全部 HEALTHY

关键端口 HTTP 验证（NAT 192.168.0.60）:
  16010 Master UI  → HTTP 200 ✓
  16030 RS UI       → HTTP 200 ✓
```

#### 附加问题

- **Ambari request 472/474/475** 在 ZK 没清理的情况下尝试 START，但失败（RS 反复 YouAreDeadException abort）
- 清理 ZK 后 **Ambari request 476** 成功（Master 和 RS 均由 Ambari 正常拉起）
- 说明：Ambari agent 本身没问题，只是 ZK 里的 dead server 状态阻塞了注册

#### 遗留

- HBase 日志里 Ranger PolicyRefresher 持续报 `com.sun.jersey.spi.inject.Errors$ErrorMessagesException: null`（jersey JSON provider 冲突），但不影响 HBase 稳定性——"Will continue to use last known version"
- NAT persist systemd 服务仍未安装（chroot 缺 DBus），宿主机重启后规则会丢。**需宿主机直接执行**：`sudo bash setup-nat-forward.sh persist`

## 关键经验（续）

8. **YouAreDeadException = ZK dead server 残留**：HBase 2.x 的 ServerManager 会在内存和 ZK 中维护 dead server 列表。RegionServer 进程虽然死了，但 ZK ephemeral 节点和 ServerManager 内存里还记着它。新进程用同样的 hostname:port:startcode 注册时会被拒绝。**清理方案**：停掉所有 HBase 进程 → 清 /hbase ZK 节点 → 重启 HBase。
9. **Ambari START vs 手动启动**：Ambari 拉起的 hbase-daemon.sh 用的是 `/usr/bigtop/current/hbase-master/` 和 `/usr/bigtop/current/hbase-regionserver/`，手动启动容易用混 `hbase-daemon.sh`（不同路径 classpath 不同）。**建议**：先 `killall` + 清 ZK + 再用 Ambari API START，一次搞定。
10. **进程反复启动失败 → Ambari 自动放弃**：如果组件连续 N 次启动失败，Ambari agent 会停止重试，状态回落到 INSTALLED（而不是 START_FAILED）。此时要先排查进程失败原因，再触发 START API，而不是盲目重试 START。
