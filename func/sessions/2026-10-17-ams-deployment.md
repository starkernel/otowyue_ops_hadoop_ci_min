# 阶段总结：AMS 经典部署（2026-10-17）

> 详细内容见 `../../docs/AMBARI_CLUSTER_REPAIR_RECORD.md` 第四轮。

## 背景

- 集群栈内无 METRICS 服务定义（BIGTOP 3.5.0 无 metrics service），无法通过 Ambari 部署。
- 采用手工安装经典 AMS RPM：h0=collector+monitor+hadoop-sink+grafana；h1-h3=monitor+hadoop-sink。

## 关键问题与修复

| 问题 | 根因 | 修复 |
|---|---|---|
| ams-hbase ZK 端口冲突 | 读 `/etc/ams-hbase/conf`（默认 2181），非 `/usr/lib/ams-hbase/conf` | 复制 collector `hbase-site.xml`，改 ZK 61181，建数据目录 |
| collector jar 版本冲突 | jackson/jersey/JAX-RS 版本不一致 | 对齐 Hadoop 3.3.6：jersey 1.19.4 + jsr311 + jackson 2.12.7 |
| collector 启动成功 | — | 6188 监听，metadata HTTP 200 |
| monitor 需 python2 | 容器仅 python3.6.8 | `yum install python2`（appstream 2.7.18） |
| psutil 缺 C 扩展 | 内置 2.1.1 无 `_psutil_linux.so` | 装 gcc/python2-devel 后 `setup.py build`，其余节点复制 build 目录 |
| metric_groups.conf JSON 解析失败 | 含 Apache 许可注释头 | 去注释，仅保留纯 JSON |
| collector 地址错误 | 取自 `[default] metrics_servers`（非 `[collector] host`） | 设为 `bigtop_hostname0`，显式 `hostname=<FQDN>` |
| Grafana 无数据源 | 未装 datasource 插件 | 遗留项（P1） |

## 结果

- ams-hbase（ZK 61181 / master 61300 / RS 61320）、collector(6188)、4 台 monitor 上报正常。
- Grafana :3000 运行，HTTP 200。

## 遗留

- Grafana 数据源/仪表盘未配置。
- AMS 未纳入 Ambari 管理（手工启停）。
