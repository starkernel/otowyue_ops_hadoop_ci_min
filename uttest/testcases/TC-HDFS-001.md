# TC-HDFS-001 HDFS 读写与副本

- 级别：P0
- 前置：HDFS STARTED，NameNode@h0，DataNode@h1/h2/h3
- 关联：IT-HDFS-001/002

## 步骤

```bash
# 1. 创建目录并写入
docker exec bigtop_hostname0 bash -c '
  echo "hello-hdfs" > /tmp/tc_hdfs.txt
  hdfs dfs -mkdir -p /test
  hdfs dfs -put -f /tmp/tc_hdfs.txt /test/
'
# 2. 读取
docker exec bigtop_hostname0 hdfs dfs -cat /test/tc_hdfs.txt
# 3. 副本检查
docker exec bigtop_hostname0 hdfs dfs -stat "%r %b %n" /test/tc_hdfs.txt
docker exec bigtop_hostname0 hdfs fsck /test/tc_hdfs.txt -files -blocks
# 4. 清理
docker exec bigtop_hostname0 hdfs dfs -rm -r -f /test
```

## 期望

- 步骤 2 输出 `hello-hdfs`
- `fsck` 显示 `Status: HEALTHY`，复制因子 3，无 missing block

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | ⏳ 待执行 | |
