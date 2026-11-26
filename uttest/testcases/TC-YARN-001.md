# TC-YARN-001 YARN 作业提交

- 级别：P1
- 前置：ResourceManager@h0:8088，NodeManager@h1/h2/h3
- 关联：IT-YARN-001/002

## 步骤

```bash
docker exec bigtop_hostname0 bash -c "
  yarn jar /usr/bigtop/current/hadoop-mapreduce-client/hadoop-mapreduce-examples.jar pi 2 10
"
docker exec bigtop_hostname0 bash -c "yarn application -list -appStates ALL | head -5"
```

## 期望

- 作业 `SUCCEEDED`，输出 Pi 近似值
- `yarn application -list` 可查询

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | ⏳ 待执行 | 8088 监听 |
