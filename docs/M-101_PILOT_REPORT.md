# M-101 小状态卷迁移试点报告

> **状态提示（2026-11-26）**：本文为历史/阶段材料；当前集群架构、Kerberos、HA 与端口以
> [`ARCHITECTURE.md`](ARCHITECTURE.md) 和 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。


> 日期：2026-11-24
> 对象：`bigtop_hostname2`（h2）
> 结果：**试点中止并回滚；无数据丢失，集群已恢复**

## 1. 目标

在不扩容 500G 磁盘的前提下，试点“小状态持久化”：

- 把 Kafka 日志、ZK 数据、Prometheus/Alertmanager 数据复制到宿主机；
- 用 `docker commit` 生成 h2 节点镜像；
- 用同一镜像 + 卷重建 h2，验证容器可重建且小状态不丢。

## 2. 实际执行

| 步骤 | 结果 |
|---|---|
| 停止 h2 上 DATANODE / ZOOKEEPER_SERVER / NODEMANAGER / FLINK_TASKMANAGER | 完成 |
| 停止 Kafka / Prometheus / Alertmanager / prom_proxy | 完成 |
| 复制小状态到 `/var/lib/hodoopforge/h2` | 完成（Kafka 11M、ZK 145M、Prometheus 378M） |
| `docker commit bigtop_hostname2 hodoopforge/h2:smallstate-20261124` | **失败/中止** |
| 回滚：启动 systemd + Ambari 组件 | 完成 |
| 清理未完成的 commit 层 | 完成（释放约 19G） |

## 3. 失败原因

`docker commit` 对 h2 的约 **70GB 可写层**做快照，实际写入速度约 **280MB/min**：

```text
29 分钟仅写入约 8GB
按此速度完成 70GB 需要 4 小时以上
```

宿主机是单块 NVMe，且已有 BUG-043（I/O timeout）历史；这类全量 commit 不适合作为迁移路径。继续等待会造成 h2 长时间停服，因此中止。

## 4. 回滚结果

- h2 原容器未删除、未重建；
- DATANODE / ZOOKEEPER_SERVER / NODEMANAGER / FLINK_TASKMANAGER 全部恢复 STARTED；
- Kafka / Prometheus / Alertmanager / prom_proxy 恢复；
- HDFS 3 个 DataNode，missing/under-replicated 均为 0；
- Flink 作业 `ff461d24…` RUNNING；
- Ambari 告警 100/100 OK；
- 磁盘从 73% 回到 **69%**（清理未完成 commit 层）。

## 5. 结论

**`docker commit` 全量快照方案不可行**，与磁盘容量无关，瓶颈是 I/O 和 70GB 可写层。

M-101 需要改为以下之一：

1. **软件-only 镜像**：在容器内停服务、移出数据后，只提交软件层（约 10–15GB），数据用卷；
   需要先把 HDFS DataNode 数据迁出或接受重建后由 HDFS 再复制。
2. **重建镜像**：用 Dockerfile 安装 Bigtop/Ambari，数据全部走卷；最干净，但工期最长。
3. **扩容后全量 commit**：需要更快存储/更多空间，且仍受 I/O 限制。

当前建议：先做 **软件-only 镜像 + 小状态卷**，HDFS DataNode 数据不做卷，重建后由三副本自动恢复；预计单节点 20–30 分钟窗口。

## 6. 当前禁止事项

- 禁止 `docker compose up/down/restart`；
- 禁止删除现有 4 个容器；
- 禁止再次对 70GB 容器做全量 `docker commit`，除非 I/O 与窗口都满足。
