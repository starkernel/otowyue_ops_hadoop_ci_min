# TC-HIVE-001 HiveServer2 连接与查询（MySQL 元数据库）

- 级别：P0
- 前置：HiveServer2@h0:10000，HiveMetaStore@h0:9083，MySQL 元数据库
- 关联：IT-HIVE-001/002/005，BUG-026

## 步骤

```bash
# 1. 确认元数据库为 MySQL（非 Derby）
docker exec bigtop_hostname0 grep -A1 javax.jdo.option.ConnectionURL \
  /etc/hive/conf/hive-site.xml | grep -o 'jdbc:[^<]*'
# 期望：jdbc:mysql://bigtop-hostname0.bigtop.apache.org/hive

# 2. 连接并查询
docker exec bigtop_hostname0 bash -c "
  beeline -u 'jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default' -n hive -e 'select 1 as ok;'
"
# 3. 建表写入
docker exec bigtop_hostname0 bash -c "
  beeline -u 'jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default' -n hive -e \"
    create table if not exists tc_t(id int);
    insert into tc_t values(1);
    select count(*) from tc_t;
    drop table tc_t;\"
"
```

## 期望

- 步骤 1 输出 `jdbc:mysql://...`（证明未使用 Derby）
- 步骤 2 返回 1
- 步骤 3 count = 1

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | 🟡 部分（连接/端口正常，SQL 待执行） | Derby 问题已排除 |
