# 快照后巡检与自动恢复 Runbook

> 自动化：`sudo bash scripts/install_ops_automation.sh` 安装开机自愈与 10 分钟巡检；
> 详见 [`OPERATIONS_AUTOMATION.md`](OPERATIONS_AUTOMATION.md)。

> 适用：宿主机/虚拟机拍快照后（快照会短暂挂起 guest，Hadoop 进程可能收到 SIGTERM 后不再拉起）。

## 1. 一条命令

```bash
cd /home/rkam/hadoop-ops-course
bash scripts/post_snapshot_recover.sh --check   # 只巡检，不改动
bash scripts/post_snapshot_recover.sh           # 巡检 + 自动拉起
```

脚本做的事：

| 步骤 | 行为 |
|---|---|
| Ambari 连通性 | 最多等 60s |
| 服务状态 | 依次检查 ZK/HDFS/YARN/MR2/Hive/HBase/Kafka/Spark/Flink/Ranger，非 STARTED 则通过 Ambari 启动并等待完成 |
| Flink TM | **以 Flink REST `/taskmanagers` 为准**；为 0 时才通过 Ambari 启动 INSTALLED 的 TM |
| HDFS HA | `hdfs haadmin -getAllServiceState`，输出 active/standby |
| Flink 作业 | 有 RUNNING 作业则打印 checkpoint 计数；没有则提示（加 `--submit-flink` 可自动提交） |
| 告警 | 统计 OK/WARNING/CRITICAL，并列出 CRITICAL 名称 |

退出码：`0` 正常；`1` 有检查失败（HDFS HA 异常 / Flink REST 不可达 / 启动后仍非 STARTED）。

## 2. 常用参数

```bash
# 只巡检
bash scripts/post_snapshot_recover.sh --check

# 巡检 + 自动拉起 + 没有作业时重新提交 Flink JAR
bash scripts/post_snapshot_recover.sh --submit-flink

# 自定义地址
AMBARI_URL=http://localhost:20609 FLINK_URL=http://172.19.0.2:8081 \
  bash scripts/post_snapshot_recover.sh
```

## 3. 快照后仍需人工确认的两点

1. **Ambari HA 向导弹窗**
   若快照回滚到旧时间点，服务端 persist 可能又带回 `step9`：

   ```bash
   bash scripts/ambari_reset_ha_wizard.sh
   ```

   然后浏览器 `Ctrl+Shift+R` 刷新一次。

2. **业务验证**
   - Flink：`curl -s http://172.19.0.2:8081/jobs/overview`
   - Spark：`beeline -u 'jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/default;transportMode=binary' -n spark -e 'SELECT 1'`
   - HBase：`echo status | hbase shell`

## 4. 建议

- 每次拍快照**结束后**跑一次 `post_snapshot_recover.sh`，不要等业务报障。
- 拍快照前如条件允许，先 `ambari` 停止写入类服务或做 `fsfreeze`/应用静默，减少不一致风险。
- 该脚本只做“拉起 + 巡检”，不做数据修复；若发现 `missing blocks` 或作业反复失败，按事故流程处理。
