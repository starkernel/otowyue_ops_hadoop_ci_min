# TC-HBASE-001 HBase 建表读写

- 级别：P0
- 前置：HBase Master@h0:16000，RegionServer@h3:16020
- 关联：IT-HBASE-001/002，BUG-023

## 步骤

```bash
docker exec bigtop_hostname0 bash -c "
hbase shell <<'EOF'
status
create 'tc_t','f'
put 'tc_t','r1','f:c','v1'
get 'tc_t','r1'
count 'tc_t'
disable 'tc_t'
drop 'tc_t'
exit
EOF
"
```

## 期望

- `status` 显示 `1 active master`、`1 servers`
- `get` 返回 `value=v1`
- `count` 返回 1

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | ⏳ 待执行 | 端口正常 |
