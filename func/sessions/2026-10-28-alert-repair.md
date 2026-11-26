# 阶段总结：HBASE/SPARK 告警根因与消除 + NAT 持久化（2026-10-28）

> 详细内容见 `../../docs/AMBARI_CLUSTER_REPAIR_RECORD.md` 第五轮。

## 背景

- 告警：`hbase_master_process`(@h0:16000)、`hbase_regionserver_process`(@h3:16030)、
  `hbase_regionserver_process_percent`、`spark_thriftserver_status`(@h1:10016) 为 CRITICAL，
  `hbase_master_cpu` 为 UNKNOWN。
- Ambari 服务级显示 STARTED，但 host_component 实为 INSTALLED（状态不一致）。

## 根因

- 2026-10-16 09:43 UTC：HBase Master/RS 因 **ZooKeeper 会话过期**主动 Abort
  （`SessionExpiredException for /hbase-unsecure/master` → `HMaster/RegionServer Aborted`）。
- 同期 SPARK_THRIFTSERVER 停止（`YARN state monitor ... Filesystem closed`）。
- 触发因素：上一轮修复期间单独重启了 `ZOOKEEPER_SERVER@h2` 及其 DataNode，HBase 会话随之中断。
- **与 NAT 无关**（NAT 源地址改写问题已在 V2.3 修复）。
- 后续重启失败的直接原因：容器内 `/usr/bin/python` 不存在，Ranger 凭据脚本 `bad interpreter`（126）。

## 动作

1. `ln -sf /usr/bin/python3 /usr/bin/python`（栈内脚本统一 python3，Ranger helper 兼容）。
2. 依次重启 `HBASE_MASTER@h0` → `HBASE_REGIONSERVER@h3` → `SPARK_THRIFTSERVER@h1`。
3. install 脚本加固：`[ ! -f ]` → `[ ! -e ]` 并打印结果。
4. NAT 脚本 V2.3 → V2.4：`persist`/`unpersist`（systemd 开机重建规则）+ 修复计数。

## 结果

- 主机 h0-h3 全 HEALTHY；告警 OK=82，非 OK=0。
- 端口 16000/16010、16020/16030、10016 均监听。

## 经验

- 单独重启 ZooKeeper 会让 HBase 会话过期并 Abort，且**不会自愈**。
- 组件启动前先确认 `/usr/bin/python` 等基础解释器存在。
- Ambari PUT 只改状态，不保证进程重启。
