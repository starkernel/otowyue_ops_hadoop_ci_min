# HodoopForge 大数据底座组件操作指导书

> **平台名称**：HodoopForge 企业级 Hadoop 集群部署与管理平台  
> **底座版本**：Ambari 3.1.0 + Bigtop 3.5.0  
> **文档版本**：V1.0  
> **编写日期**：2026年9月  
> **口号**：*锻造稳定 · 连接未来 | Forge Stability. Connect the Future.*

---

## 文档说明

本指导书面向大数据平台运维人员、开发人员及测试人员，详细描述 HodoopForge 底座中各大数据组件的访问方式、常用操作、运维命令、故障排查及最佳实践。读者应具备基本的 Linux 操作系统知识和 Hadoop 生态系统背景。

### 环境概述

| 节点 | 容器名 | 内网 IP | 主机名 |
|------|--------|---------|--------|
| 主节点 | bigtop_hostname0 | 172.19.0.2 | bigtop-hostname0.bigtop.apache.org |
| 工作节点1 | bigtop_hostname1 | 172.19.0.5 | bigtop-hostname1.bigtop.apache.org |
| 工作节点2 | bigtop_hostname2 | 172.19.0.3 | bigtop-hostname2.bigtop.apache.org |
| 工作节点3 | bigtop_hostname3 | 172.19.0.4 | bigtop-hostname3.bigtop.apache.org |

### 宿主机端口映射概览

| 服务 | 宿主机端口 | 目标节点 | 目标端口 |
|------|-----------|---------|---------|
| Ambari Web UI | 20609 | hostname0 | 8080 |
| HDFS NameNode UI | 50070 | hostname0 | 50070 |
| HDFS NameNode RPC | 8020 | hostname0 | 8020 |
| YARN ResourceManager UI | 8088 | hostname0 | 8088 |
| HBase Master UI | 16010 | hostname0 | 16010 |
| Kafka Broker | 9092 | hostname0 | 9092 |
| Spark History Server | 18081 | hostname0 | 18081 |
| ZooKeeper(h0) | 21810 | hostname0 | 2181 |
| HiveServer2 JDBC | 10000 | hostname1 | 10000 |
| HiveServer2 UI | 10002 | hostname1 | 10002 |
| Hive Metastore | 9083 | hostname1 | 9083 |
| Ranger Admin UI | 6080 | hostname1 | 6080 |
| MR History Server | 19888 | hostname1 | 19888 |
| MySQL | 3306 | hostname1 | 3306 |
| ZooKeeper(h1) | 12181 | hostname1 | 2181 |
| ZooKeeper(h2) | 22181 | hostname2 | 2181 |
| HBase RegionServer UI | 16030 | hostname3 | 16030 |
| DataNode UI | 50075 | hostname3 | 50075 |
| NodeManager UI | 8042 | hostname3 | 8042 |

### 进入容器方式

```bash
# 进入主节点
docker exec -it bigtop_hostname0 bash

# 进入工作节点
docker exec -it bigtop_hostname1 bash
docker exec -it bigtop_hostname2 bash
docker exec -it bigtop_hostname3 bash
```

---

## 目录

1. [Ambari 管理平台操作指南](#第一章-ambari-管理平台操作指南)
2. [HDFS 分布式文件系统操作指南](#第二章-hdfs-分布式文件系统操作指南)
3. [YARN 资源管理操作指南](#第三章-yarn-资源管理操作指南)
4. [MapReduce 作业操作指南](#第四章-mapreduce-作业操作指南)
5. [ZooKeeper 协调服务操作指南](#第五章-zookeeper-协调服务操作指南)
6. [Hive 数据仓库操作指南](#第六章-hive-数据仓库操作指南)
7. [HBase NoSQL 数据库操作指南](#第七章-hbase-nosql-数据库操作指南)
8. [Kafka 消息队列操作指南](#第八章-kafka-消息队列操作指南)
9. [Spark 计算引擎操作指南](#第九章-spark-计算引擎操作指南)
10. [Ranger 权限管理操作指南](#第十章-ranger-权限管理操作指南)
11. [Tez 执行引擎操作指南](#第十一章-tez-执行引擎操作指南)
12. [Flink 流处理操作指南](#第十二章-flink-流处理操作指南)
13. [Zeppelin 数据分析操作指南](#第十三章-zeppelin-数据分析操作指南)
14. [集群运维操作指南](#第十四章-集群运维操作指南)
15. [故障排查手册](#第十五章-故障排查手册)
16. [性能调优指南](#第十六章-性能调优指南)
17. [安全加固指南](#第十七章-安全加固指南)


---

# 第一章 Ambari 管理平台操作指南

## 1.1 Ambari 概述

Apache Ambari 是 HodoopForge 的统一管理平台，提供集群的可视化管理、监控告警、配置管理和服务生命周期管理能力。

### 1.1.1 访问地址

| 访问方式 | 地址 |
|---------|------|
| 宿主机直接访问 | http://localhost:20609 |
| 局域网访问 | http://<宿主机IP>:20609 |
| 容器内访问 | http://bigtop-hostname0.bigtop.apache.org:8080 |

**默认账户**：admin / admin

### 1.1.2 主界面导航

登录后主界面分为以下区域：

- **Dashboard**：集群整体状态概览，包括 HDFS 使用率、YARN 队列、告警汇总
- **Services**：各服务管理入口，可启停服务、查看配置
- **Hosts**：节点列表，显示各节点健康状态、组件分布
- **Alerts**：告警列表和告警定义管理
- **Admin**：集群管理，包括用户管理、Kerberos、Service Auto Start 等

## 1.2 服务管理操作

### 1.2.1 启动单个服务

**通过 UI**：Services → 选择服务 → Service Actions → Start

**通过 API**：
```bash
# 启动 HDFS（将 HDFS 替换为其他服务名）
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Start HDFS via API"},
       "Body":{"ServiceInfo":{"state":"STARTED"}}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/services/HDFS"
```

### 1.2.2 停止单个服务

```bash
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Stop HDFS"},
       "Body":{"ServiceInfo":{"state":"INSTALLED"}}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/services/HDFS"
```

### 1.2.3 启动所有服务

```bash
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Start All Services"},
       "Clusters":{"cluster_name":"qixuandata","desired_service_config_version":{}}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/services"
```

**通过 UI**：Dashboard → Actions → Start All

### 1.2.4 重启服务

```bash
# 先停止再启动（以 Hive 为例）
for STATE in INSTALLED STARTED; do
  curl -u admin:admin -s -X PUT \
    -H "X-Requested-By: ambari" \
    -H "Content-Type: application/json" \
    -d "{\"RequestInfo\":{\"context\":\"Restart Hive\"},
         \"Body\":{\"ServiceInfo\":{\"state\":\"${STATE}\"}}}" \
    "http://localhost:20609/api/v1/clusters/qixuandata/services/HIVE"
  sleep 15
done
```

### 1.2.5 查询服务状态

```bash
# 查看所有服务状态
curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/services?fields=ServiceInfo/state" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d['items']:
    si=s['ServiceInfo']
    print(f\"{si['service_name']:<20} {si['state']}\")
"
```

## 1.3 节点管理操作

### 1.3.1 查看节点列表

```bash
curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/hosts?fields=Hosts/host_name,Hosts/host_status,Hosts/last_heartbeat_time" \
  | python3 -c "
import json,sys,time
d=json.load(sys.stdin)
for h in d['items']:
    hi=h['Hosts']
    ts=hi.get('last_heartbeat_time',0)
    ago=int(time.time()*1000-ts)//1000
    print(f\"{hi['host_name']:<50} {hi['host_status']:<12} 心跳{ago}s前\")
"
```

### 1.3.2 查看节点组件分布

```bash
HOST="bigtop-hostname0.bigtop.apache.org"
curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/hosts/${HOST}/host_components?fields=HostRoles/component_name,HostRoles/state" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for c in d['items']:
    hr=c['HostRoles']
    print(f\"  {hr['component_name']:<40} {hr['state']}\")
"
```

### 1.3.3 维护模式（Maintenance Mode）

维护模式可以抑制节点相关告警，适用于节点维护期间：

```bash
# 开启维护模式
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"Hosts":{"maintenance_state":"ON"}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/hosts/bigtop-hostname3.bigtop.apache.org"

# 关闭维护模式
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"Hosts":{"maintenance_state":"OFF"}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/hosts/bigtop-hostname3.bigtop.apache.org"
```

## 1.4 配置管理

### 1.4.1 查看当前配置

```bash
# 查看 hdfs-site 当前配置
curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/configurations?type=hdfs-site" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d['items']
print(f'共 {len(items)} 个版本')
for i in items:
    print(f\"  tag={i['tag']}  version={i['version']}\")
"
```

### 1.4.2 修改配置并生效

以修改 HDFS 副本数为例：

1. **UI 方式**：Services → HDFS → Configs → 搜索 `dfs.replication` → 修改值 → Save → Restart Affected

2. **API 方式**：
```bash
# 1. 读取当前配置
TAG=$(curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/configurations?type=hdfs-site" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['items'][-1]['tag'])")

# 2. 获取当前属性并修改
curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/configurations?type=hdfs-site&tag=${TAG}" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
props=d['items'][0]['properties']
props['dfs.replication']='2'   # 修改副本数
payload={'Clusters':{'desired_configs':{'type':'hdfs-site','tag':'new-config','properties':props}}}
print(json.dumps(payload))
" | curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d @- \
  "http://localhost:20609/api/v1/clusters/qixuandata"

# 3. 重启受影响服务
```

### 1.4.3 配置版本历史

Ambari 保留所有配置变更历史：

**UI 方式**：Services → 选择服务 → Configs → Config History（右上角时钟图标）

可以查看历史版本并回滚到任意历史配置。

## 1.5 告警管理

### 1.5.1 查看当前告警

```bash
curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/alerts?fields=Alert/definition_name,Alert/host_name,Alert/state,Alert/text" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
critical=[a for a in d['items'] if a['Alert']['state']=='CRITICAL']
warning=[a for a in d['items'] if a['Alert']['state']=='WARNING']
print(f'CRITICAL: {len(critical)}  WARNING: {len(warning)}')
for a in critical+warning:
    al=a['Alert']
    print(f\"  [{al['state']}] {al['definition_name']} @ {al['host_name']}\")
    print(f\"    {al.get('text','')[:80]}\")
"
```

### 1.5.2 禁用/启用告警定义

```bash
# 列出所有告警定义
curl -u admin:admin -s \
  "http://localhost:20609/api/v1/clusters/qixuandata/alert_definitions?fields=AlertDefinition/id,AlertDefinition/name,AlertDefinition/enabled" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d['items']:
    ad=a['AlertDefinition']
    print(f\"  id={ad['id']:<5} enabled={ad['enabled']}  {ad['name']}\")
"

# 禁用某告警（如 id=10）
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"AlertDefinition":{"enabled":false}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/alert_definitions/10"
```

## 1.6 Ambari 日志查看

```bash
# Ambari Server 日志
docker exec bigtop_hostname0 tail -f /var/log/ambari-server/ambari-server.log

# 关键事件过滤
docker exec bigtop_hostname0 bash -c "
grep -E 'ERROR|WARN|cluster|service' /var/log/ambari-server/ambari-server.log \
  | grep -v 'heartbeat' | tail -50
"

# Ambari Agent 日志（各节点）
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  echo "=== $h ==="
  docker exec $h tail -5 /var/log/ambari-agent/ambari-agent.log
done
```

## 1.7 Ambari REST API 常用接口速查

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/v1/clusters` | GET | 列出所有集群 |
| `/api/v1/clusters/{cluster}/services` | GET/PUT | 服务列表/批量操作 |
| `/api/v1/clusters/{cluster}/services/{service}` | GET/PUT | 服务详情/操作 |
| `/api/v1/clusters/{cluster}/hosts` | GET | 节点列表 |
| `/api/v1/clusters/{cluster}/hosts/{host}/host_components` | GET | 节点组件列表 |
| `/api/v1/clusters/{cluster}/configurations` | GET/POST | 配置管理 |
| `/api/v1/clusters/{cluster}/alerts` | GET | 告警列表 |
| `/api/v1/clusters/{cluster}/alert_definitions` | GET/PUT | 告警定义 |
| `/api/v1/clusters/{cluster}/requests` | GET | 操作请求历史 |
| `/api/v1/stacks` | GET | Stack 列表 |


---

# 第二章 HDFS 分布式文件系统操作指南

## 2.1 HDFS 概述

HDFS（Hadoop Distributed File System）是 HodoopForge 底座的核心存储层，提供高容错、高吞吐量的分布式文件存储能力。

### 2.1.1 组件分布

| 组件 | 节点 | 端口 | 说明 |
|------|------|------|------|
| NameNode | hostname0 | 8020(RPC), 50070(UI) | 元数据管理节点 |
| Secondary NameNode | hostname1 | 50090(UI) | 检查点辅助节点 |
| DataNode | hostname3 | 50075(UI), 50010(数据) | 数据存储节点 |
| HDFS Router | hostname3 | 50071(UI), 8888(RPC) | 联邦路由器 |

### 2.1.2 访问 Web UI

```
NameNode Web UI:         http://localhost:50070
Secondary NameNode UI:   http://localhost:50090
DataNode(hostname3) UI:  http://localhost:50075
```

### 2.1.3 HDFS 架构说明

- **NameNode**：存储文件系统的元数据（目录树、文件块映射、权限等），是单点，需定期备份
- **Secondary NameNode**：定期合并 NameNode 的 FsImage 和 EditLog，不是热备
- **DataNode**：存储实际数据块（默认128MB），向 NameNode 汇报心跳和块状态
- **副本策略**：默认3副本，写入策略遵循机架感知（本环境容器均在同一宿主机，机架感知无实际意义）

## 2.2 HDFS 基础操作

### 2.2.1 进入操作环境

```bash
# 所有 HDFS 命令在 hostname0 上执行
docker exec -it bigtop_hostname0 bash

# 或以 hdfs 用户身份执行
docker exec bigtop_hostname0 su - hdfs -s /bin/bash
```

### 2.2.2 目录操作

```bash
# 列出根目录
hdfs dfs -ls /

# 列出目录（含隐藏文件）
hdfs dfs -ls -a /user

# 递归列出目录
hdfs dfs -ls -R /warehouse

# 创建目录
hdfs dfs -mkdir /data
hdfs dfs -mkdir -p /data/project/input   # 递归创建

# 删除目录（非空目录需 -r）
hdfs dfs -rm -r /data/tmp

# 删除目录（跳过回收站）
hdfs dfs -rm -r -skipTrash /data/tmp

# 查看目录权限和所有者
hdfs dfs -ls -d /warehouse/tablespace

# 修改目录权限
hdfs dfs -chmod 755 /data
hdfs dfs -chmod -R 777 /tmp

# 修改所有者
hdfs dfs -chown hdfs:hadoop /data
hdfs dfs -chown -R hive:hadoop /warehouse/tablespace
```

### 2.2.3 文件操作

```bash
# 上传本地文件到 HDFS
hdfs dfs -put /etc/hosts /user/test/
hdfs dfs -put /tmp/data.csv /data/input/

# 上传并覆盖已有文件
hdfs dfs -put -f /tmp/data.csv /data/input/

# 从 HDFS 下载文件到本地
hdfs dfs -get /data/input/data.csv /tmp/
hdfs dfs -get /data/input/ /tmp/download/   # 下载整个目录

# 查看文件内容
hdfs dfs -cat /user/test/hosts
hdfs dfs -cat /data/input/data.csv | head -10   # 只看前10行
hdfs dfs -text /data/input/data.snappy          # 自动解压查看

# 移动/重命名文件
hdfs dfs -mv /data/input/old.csv /data/input/new.csv
hdfs dfs -mv /data/tmp/ /data/archive/

# 复制文件
hdfs dfs -cp /data/input/data.csv /data/backup/
hdfs dfs -cp -p /data/input/ /data/backup/   # 保留权限

# 追加内容到文件
hdfs dfs -appendToFile /tmp/extra.txt /data/input/data.txt

# 合并多个文件
hdfs dfs -getmerge /data/parts/ /tmp/merged.txt

# 查看文件大小
hdfs dfs -du -h /data                  # 各子目录大小
hdfs dfs -du -s -h /data              # 汇总大小
hdfs dfs -count -h /warehouse          # 统计文件和目录数量

# 检查文件是否存在
hdfs dfs -test -e /data/input/data.csv && echo "exists" || echo "not found"
hdfs dfs -test -d /data && echo "is directory" || echo "not a directory"
```

### 2.2.4 HDFS 集群状态查询

```bash
# 集群整体状态报告
hdfs dfsadmin -report

# 详细输出格式
hdfs dfsadmin -report | grep -E "Live|Dead|Configured|Present|Remaining|Used"

# 查看 NameNode 状态
hdfs dfsadmin -safemode get

# 退出安全模式（服务启动时可能进入）
hdfs dfsadmin -safemode leave

# 查看 DataNode 详细信息
hdfs dfsadmin -report | grep -A 15 "Name:"

# 查看各 DataNode 容量
hdfs dfsadmin -report | awk '/^Name:/{name=$2} /Configured Capacity:/{print name, $3$4}'

# 查看文件系统统计
hdfs dfsadmin -fetchImage /tmp/fsimage   # 获取 FsImage

# 检查文件系统健康状态
hdfs fsck /
hdfs fsck / -files -blocks -locations    # 详细块信息
hdfs fsck /data -delete                  # 删除损坏块（谨慎使用）
```

### 2.2.5 文件系统检查（fsck）

```bash
# 基本健康检查
hdfs fsck /

# 查看损坏的块
hdfs fsck / | grep -E "CORRUPT|MISSING|Under"

# 检查特定路径
hdfs fsck /warehouse -files

# 显示详细块信息
hdfs fsck /data/input/data.csv -files -blocks -locations

# 常见输出解读：
# Status: HEALTHY            -- 健康
# Status: CORRUPT            -- 有损坏块，需要处理
# Under replicated blocks    -- 副本不足（DataNode 离线可能导致）
# Missing blocks             -- 完全丢失的块（数据已不可恢复）
```

## 2.3 HDFS 权限管理

### 2.3.1 POSIX 权限模型

HDFS 使用 POSIX 风格的权限控制（owner/group/other）：

```bash
# 查看权限
hdfs dfs -ls /warehouse/tablespace
# 输出格式：权限 副本数 所有者 群组 大小 时间 路径
# drwxr-xr-x   - hdfs hadoop         0 2026-09-03 /warehouse/tablespace

# 修改权限
hdfs dfs -chmod 750 /secure/data       # owner可读写执行，group可读执行
hdfs dfs -chmod -R 755 /data           # 递归修改

# 修改所有者和群组
hdfs dfs -chown hive /warehouse/tablespace/managed/hive
hdfs dfs -chown hive:hadoop /warehouse/tablespace/managed/hive
hdfs dfs -chown -R hive:hadoop /warehouse/tablespace

# 修改群组
hdfs dfs -chgrp hadoop /data
```

### 2.3.2 ACL 访问控制列表

```bash
# 查看 ACL
hdfs dfs -getfacl /data

# 设置 ACL（给 spark 用户读权限）
hdfs dfs -setfacl -m user:spark:r-x /data

# 设置默认 ACL（新创建文件自动继承）
hdfs dfs -setfacl -m default:user:hive:rwx /warehouse

# 删除特定 ACL 条目
hdfs dfs -setfacl -x user:spark /data

# 删除所有 ACL
hdfs dfs -setfacl -b /data

# 批量设置 ACL
hdfs dfs -setfacl -R -m user:spark:r-x /data   # 递归设置
```

### 2.3.3 HDFS 目录配额

```bash
# 设置命名空间配额（最多文件/目录数量）
hdfs dfsadmin -setQuota 1000 /user/alice   # 最多1000个文件

# 设置空间配额（字节数）
hdfs dfsadmin -setSpaceQuota 10g /user/alice   # 最多10GB

# 查看配额使用情况
hdfs dfs -count -q -h /user/alice
# 输出: QUOTA REMAINING_QUOTA SPACE_QUOTA REMAINING_SPACE_QUOTA ...

# 清除配额
hdfs dfsadmin -clrQuota /user/alice
hdfs dfsadmin -clrSpaceQuota /user/alice
```

## 2.4 HDFS 高级操作

### 2.4.1 快照管理

```bash
# 允许目录创建快照
hdfs dfsadmin -allowSnapshot /data/critical

# 创建快照
hdfs dfs -createSnapshot /data/critical backup-20260904

# 列出快照
hdfs lsSnapshottableDir
hdfs dfs -ls /data/critical/.snapshot

# 比较快照差异
hdfs snapshotDiff /data/critical backup-20260904 .    # . 表示当前状态

# 从快照恢复文件
hdfs dfs -cp /data/critical/.snapshot/backup-20260904/important.csv /data/critical/

# 删除快照
hdfs dfs -deleteSnapshot /data/critical backup-20260904

# 禁止目录创建快照
hdfs dfsadmin -disallowSnapshot /data/critical
```

### 2.4.2 均衡 DataNode 数据

当各 DataNode 磁盘使用不均衡时，运行 balancer：

```bash
# 启动 balancer（默认阈值 10%）
hdfs balancer

# 指定阈值（百分比）
hdfs balancer -threshold 5

# 后台运行并记录日志
nohup hdfs balancer -threshold 5 > /var/log/hadoop-hdfs/balancer.log 2>&1 &

# 查看均衡进度（另一终端）
tail -f /var/log/hadoop-hdfs/balancer.log

# 停止 balancer
hdfs dfsadmin -shutdownDatanode   # 不建议，直接 kill 进程
```

### 2.4.3 NameNode 联邦（本环境 HDFS Router）

本环境部署了 HDFS Router（Federation Router）在 hostname3：

```bash
# 查看 Router 状态
hdfs dfsrouter -getRouterState 2>/dev/null || \
  curl http://localhost:50071/jmx | python3 -c "
import json,sys
d=json.load(sys.stdin)
for b in d.get('beans',[]):
    if 'RouterState' in str(b):
        print(json.dumps(b, indent=2))
        break
"

# Router Web UI
# http://localhost:50071
```

### 2.4.4 HDFS 数据块操作

```bash
# 查看文件的块信息
hdfs fsck /data/input/bigfile.csv -files -blocks -locations

# 强制重新复制副本不足的块（不常用，通常自动处理）
hdfs dfsadmin -setReplication 3 /data/input/bigfile.csv

# 查看块大小配置
hdfs getconf -confKey dfs.blocksize
```

## 2.5 HDFS 运维操作

### 2.5.1 安全模式管理

NameNode 启动时会进入安全模式，等待 DataNode 汇报块信息：

```bash
# 查看安全模式状态
hdfs dfsadmin -safemode get

# 强制进入安全模式（维护时使用）
hdfs dfsadmin -safemode enter

# 退出安全模式
hdfs dfsadmin -safemode leave

# 等待安全模式退出
hdfs dfsadmin -safemode wait

# 安全模式下可执行：读文件、查看状态
# 安全模式下不可执行：写文件、创建目录、删除文件
```

### 2.5.2 DataNode 维护模式（退役）

正式环境中退役 DataNode 需通过退役流程，避免数据丢失：

```bash
# 1. 编辑退役列表（在 NameNode 上）
# /etc/hadoop/conf/dfs.hosts.exclude
echo "bigtop-hostname3.bigtop.apache.org" >> /etc/hadoop/conf/dfs.hosts.exclude

# 2. 刷新 NameNode
hdfs dfsadmin -refreshNodes

# 3. 检查退役进度
hdfs dfsadmin -report | grep -A5 "Decommission"

# 4. 等待退役完成（状态变为 Decommissioned）
# 5. 从列表中移除，再次刷新
sed -i '/bigtop-hostname3/d' /etc/hadoop/conf/dfs.hosts.exclude
hdfs dfsadmin -refreshNodes
```

### 2.5.3 NameNode 元数据备份

```bash
# 方式1：通过 HTTP 接口下载 FsImage
curl -L "http://localhost:50070/imagetransfer?getimage=1&txid=latest" \
  -o /backup/fsimage-$(date +%Y%m%d).img

# 方式2：通过 hdfsadmin
docker exec bigtop_hostname0 hdfs dfsadmin -fetchImage /tmp/fsimage_backup

# 方式3：直接备份 NameNode 数据目录
# 在容器内找到 dfs.namenode.name.dir 路径
docker exec bigtop_hostname0 bash -c "
  NAMEDIR=$(hdfs getconf -confKey dfs.namenode.name.dir | tr ',' '\n' | head -1)
  echo \"NameNode 数据目录: \$NAMEDIR\"
  ls \$NAMEDIR
"
```

### 2.5.4 HDFS 日志查看

```bash
# NameNode 日志
docker exec bigtop_hostname0 tail -f /var/log/hadoop-hdfs/hadoop-hdfs-namenode-*.log

# Secondary NameNode 日志
docker exec bigtop_hostname1 tail -f /var/log/hadoop-hdfs/hadoop-hdfs-secondarynamenode-*.log

# DataNode 日志（hostname3）
docker exec bigtop_hostname3 tail -f /var/log/hadoop-hdfs/hadoop-hdfs-datanode-*.log

# 审计日志（查看文件操作记录）
docker exec bigtop_hostname0 tail -f /var/log/hadoop-hdfs/hdfs-audit.log

# 过滤特定用户的操作
docker exec bigtop_hostname0 bash -c "
  grep 'ugi=hive' /var/log/hadoop-hdfs/hdfs-audit.log | tail -20
"
```

## 2.6 HDFS 性能测试

```bash
# 写入测试
hadoop jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-client-jobclient-tests.jar \
  TestDFSIO -write -nrFiles 10 -fileSize 128MB

# 读取测试
hadoop jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-client-jobclient-tests.jar \
  TestDFSIO -read -nrFiles 10 -fileSize 128MB

# 清理测试数据
hadoop jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-client-jobclient-tests.jar \
  TestDFSIO -clean

# 结果解读：
# Throughput mb/sec  -- 吞吐量（越大越好）
# Average IO rate    -- 平均IO速率
# IO rate std deviation -- 标准差（越小越稳定）
```

## 2.7 HDFS 常见问题处理

### 2.7.1 磁盘空间不足

```bash
# 查看各 DataNode 剩余空间
hdfs dfsadmin -report | grep -E "Name:|Remaining:"

# 清理 HDFS 回收站（超过保留时间的文件）
hdfs dfs -expunge

# 查找大文件
hdfs dfs -du -s -h /warehouse/* | sort -rh | head -20

# 清理 Spark 历史日志
hdfs dfs -rm -r /spark-history/*

# 压缩小文件（HAR 归档）
hadoop archive -archiveName logs.har -p /data/logs/ /data/archives/
```

### 2.7.2 NameNode 内存不足

```bash
# 查看 NameNode JVM 内存使用
curl -s "http://localhost:50070/jmx?qry=java.lang:type=Memory" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for b in d.get('beans',[]):
    heap=b.get('HeapMemoryUsage',{})
    if heap:
        used=heap.get('used',0)//1024//1024
        max=heap.get('max',0)//1024//1024
        print(f'Heap: {used}MB / {max}MB ({used*100//max}%)')
"

# 如需调整 NameNode 堆内存，在 Ambari UI 修改：
# Services → HDFS → Configs → Advanced → NameNode Java heap size
```

### 2.7.3 块副本不足告警

```bash
# 查看副本不足的块数量
hdfs fsck / 2>/dev/null | grep "Under replicated"

# 强制重新复制
hdfs dfsadmin -metasave /tmp/metasave.txt
cat /tmp/metasave.txt | grep "Under"
```


---

# 第三章 YARN 资源管理操作指南

## 3.1 YARN 概述

YARN（Yet Another Resource Negotiator）是 Hadoop 的资源管理框架，负责集群资源的统一调度和管理。

### 3.1.1 组件分布

| 组件 | 节点 | 端口 | 说明 |
|------|------|------|------|
| ResourceManager | hostname0 | 8088(UI), 8050(RPC) | 全局资源调度器 |
| NodeManager | hostname3 | 8042(UI) | 节点资源管理 |
| App Timeline Server | hostname1 | 8190(UI) | 应用历史信息 |
| Timeline Reader(V2) | hostname0 | 8188(UI) | 时间线读取服务 |

### 3.1.2 访问 Web UI

```
ResourceManager UI: http://localhost:8088
NodeManager UI:     http://localhost:8042    (hostname3)
Timeline Server UI: http://localhost:8190    (hostname1)
```

## 3.2 YARN 应用管理

### 3.2.1 查看应用列表

```bash
# 进入主节点
docker exec -it bigtop_hostname0 bash

# 查看所有应用
yarn application -list

# 按状态过滤
yarn application -list -appStates RUNNING
yarn application -list -appStates FINISHED
yarn application -list -appStates FAILED
yarn application -list -appStates KILLED

# 按类型过滤
yarn application -list -appTypes MAPREDUCE
yarn application -list -appTypes SPARK

# 查看所有状态（包含历史）
yarn application -list -appStates ALL | head -30
```

### 3.2.2 查看应用详情

```bash
# 查看特定应用详情（替换 application_id）
APP_ID="application_1788449905_0001"
yarn application -status ${APP_ID}

# 查看应用日志
yarn logs -applicationId ${APP_ID}

# 查看特定容器日志
yarn logs -applicationId ${APP_ID} -containerId container_xxx_yyy

# 查看特定节点上的日志
yarn logs -applicationId ${APP_ID} -nodeAddress bigtop-hostname3.bigtop.apache.org:45454

# 将日志输出到文件
yarn logs -applicationId ${APP_ID} > /tmp/app_logs.txt 2>&1
```

### 3.2.3 终止应用

```bash
# 终止运行中的应用
yarn application -kill application_1788449905_0001

# 批量终止所有 RUNNING 应用
yarn application -list -appStates RUNNING | grep application | \
  awk '{print $1}' | while read app; do
    echo "Killing $app..."
    yarn application -kill $app
  done
```

### 3.2.4 查看节点信息

```bash
# 查看所有节点
yarn node -list

# 查看节点详情
yarn node -status bigtop-hostname3.bigtop.apache.org:45454

# 查看节点可用资源
yarn node -list -all | grep -v "^Total" | awk '{print $1, $3, $4}'

# 输出格式：NodeID  State  NumContainers  MemUsed  MemAvail  CPUUsed  CPUAvail
```

## 3.3 YARN 队列管理

### 3.3.1 查看队列信息

```bash
# 查看所有队列
yarn queue -status default

# 通过 ResourceManager API 查看队列
curl -s "http://localhost:8088/ws/v1/cluster/scheduler" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
def print_queue(q, indent=0):
    name=q.get('queueName','')
    cap=q.get('capacity',0)
    used=q.get('usedCapacity',0)
    print(' '*indent + f'{name}: capacity={cap:.1f}% used={used:.1f}%')
    for child in q.get('queues',{}).get('queue',[]):
        print_queue(child, indent+2)
sched=d.get('scheduler',{}).get('schedulerInfo',{})
print_queue(sched)
"
```

### 3.3.2 容量调度器配置

本环境使用容量调度器（Capacity Scheduler）：

```bash
# 查看当前调度器配置
curl -s "http://localhost:8088/ws/v1/cluster/scheduler" | python3 -m json.tool | head -50

# 通过 Ambari 修改队列配置：
# Services → YARN → Configs → Scheduler → Queue Manager
```

**常见队列配置参数：**

| 参数 | 说明 | 示例 |
|------|------|------|
| `capacity` | 队列容量百分比 | 50 |
| `maximum-capacity` | 最大可用容量 | 80 |
| `user-limit-factor` | 单用户最大使用倍数 | 2 |
| `minimum-user-limit-percent` | 单用户最小资源百分比 | 25 |
| `state` | 队列状态 | RUNNING/STOPPED |

### 3.3.3 动态队列管理

```bash
# 刷新队列配置（不重启 ResourceManager）
yarn rmadmin -refreshQueues

# 刷新节点列表
yarn rmadmin -refreshNodes

# 刷新超级用户代理配置
yarn rmadmin -refreshSuperUserGroupsConfiguration

# 刷新用户组映射
yarn rmadmin -refreshUserToGroupsMappings

# 检查 ResourceManager HA 状态（本环境无 HA）
yarn rmadmin -checkHealth
```

## 3.4 YARN 资源配置

### 3.4.1 NodeManager 资源配置

当前 NodeManager 资源配置（通过 Ambari 设置）：

```xml
<!-- yarn-site.xml 关键配置 -->
<property>
  <name>yarn.nodemanager.resource.memory-mb</name>
  <value>4096</value>  <!-- NodeManager 可用内存 4GB -->
</property>
<property>
  <name>yarn.nodemanager.resource.cpu-vcores</name>
  <value>2</value>    <!-- NodeManager 可用 CPU 核数 -->
</property>
<property>
  <name>yarn.scheduler.minimum-allocation-mb</name>
  <value>512</value>  <!-- 容器最小内存分配 -->
</property>
<property>
  <name>yarn.scheduler.maximum-allocation-mb</name>
  <value>4096</value> <!-- 容器最大内存分配 -->
</property>
```

### 3.4.2 查看当前资源使用

```bash
# 查看集群资源总量
curl -s "http://localhost:8088/ws/v1/cluster/metrics" \
  | python3 -c "
import json,sys
m=json.load(sys.stdin)['clusterMetrics']
print(f\"总内存: {m.get('totalMB',0)/1024:.1f} GB\")
print(f\"已用内存: {m.get('allocatedMB',0)/1024:.1f} GB\")
print(f\"总CPU: {m.get('totalVirtualCores',0)} cores\")
print(f\"已用CPU: {m.get('allocatedVirtualCores',0)} cores\")
print(f\"活跃应用: {m.get('activeApps',0)}\")
print(f\"待处理应用: {m.get('pendingApps',0)}\")
print(f\"活跃节点: {m.get('activeNodes',0)}\")
"
```

## 3.5 YARN Timeline Server 操作

### 3.5.1 查询应用历史

```bash
# 通过 Timeline Server API 查询历史
curl -s "http://localhost:8190/ws/v1/timeline/YARN_APPLICATION_ATTEMPT" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
entities=d.get('entities',[])
print(f'历史记录数: {len(entities)}')
for e in entities[:5]:
    print(f\"  {e.get('entityId','')}\")
"

# 查看 Timeline Server 状态
curl -s "http://localhost:8190/ws/v1/timeline" | python3 -m json.tool
```

## 3.6 YARN 日志聚合

YARN 日志聚合将各 NodeManager 上的容器日志收集到 HDFS：

```bash
# 查看日志聚合配置
yarn application -list -appStates FINISHED | head -5
# 获取 application_id 后查看聚合日志
yarn logs -applicationId application_1788449905_0001

# 日志聚合存储在 HDFS 的 /app-logs 目录
hdfs dfs -ls /app-logs/

# 按用户查看日志
hdfs dfs -ls /app-logs/yarn/

# 配置日志保留时间（默认通过 Ambari 配置）
# yarn.log-aggregation.retain-seconds: 日志保留秒数
# yarn.log-aggregation.retain-check-interval-seconds: 检查间隔
```

## 3.7 YARN Web UI 操作详解

### 3.7.1 ResourceManager UI 导航

访问 `http://localhost:8088`：

- **Cluster → About**：集群版本信息
- **Cluster → Nodes**：节点列表，点击节点可查看详情
- **Cluster → Applications**：应用列表，支持按状态/用户/队列过滤
- **Scheduler**：队列资源分配可视化
- **Tools**：配置、日志等工具链接

### 3.7.2 追踪作业执行

```bash
# 提交测试作业并追踪
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar pi 4 100

# 输出中包含：
# Tracking URL: http://bigtop-hostname0.bigtop.apache.org:8088/proxy/application_xxx/
# 通过宿主机访问：http://localhost:8088/proxy/application_xxx/
```


---

# 第四章 MapReduce 作业操作指南

## 4.1 MapReduce 概述

MapReduce 是 Hadoop 原生的批处理计算框架，运行在 YARN 之上。本环境中 MR History Server 在 hostname1。

### 4.1.1 组件分布

| 组件 | 节点 | 端口 | 说明 |
|------|------|------|------|
| MR History Server | hostname1 | 19888(UI), 10020(IPC) | 历史作业查看 |

访问 History Server：`http://localhost:19888`

## 4.2 提交 MapReduce 作业

### 4.2.1 使用内置示例

```bash
docker exec -it bigtop_hostname0 bash

# WordCount 示例
# 1. 准备输入数据
hdfs dfs -mkdir -p /input/wordcount
echo "hello world hello hadoop" | hdfs dfs -put - /input/wordcount/data.txt

# 2. 运行 WordCount
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar \
  wordcount /input/wordcount /output/wordcount

# 3. 查看结果
hdfs dfs -cat /output/wordcount/part-r-00000

# PI 估算
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar pi 8 1000

# TeraSort 压测（生成1GB数据）
# 生成测试数据
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar \
  teragen 10000000 /input/terasort

# 排序
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar \
  terasort /input/terasort /output/terasort

# 验证
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar \
  teravalidate /output/terasort /output/teravalidate
```

### 4.2.2 提交自定义 JAR

```bash
# 基本提交
yarn jar myapp.jar com.example.MyDriver \
  -Dmapreduce.job.name="My Job" \
  /input /output

# 指定队列和资源
yarn jar myapp.jar com.example.MyDriver \
  -Dmapreduce.job.queuename=default \
  -Dmapreduce.map.memory.mb=1024 \
  -Dmapreduce.reduce.memory.mb=2048 \
  -Dmapreduce.job.reduces=4 \
  /input /output

# 添加依赖 JAR
yarn jar myapp.jar com.example.MyDriver \
  -libjars /usr/lib/hive/lib/hive-exec.jar \
  /input /output
```

### 4.2.3 流式 MapReduce

```bash
# 使用 Hadoop Streaming 运行 Python 脚本
# mapper.py
cat > /tmp/mapper.py << 'PYEOF'
#!/usr/bin/env python3
import sys
for line in sys.stdin:
    words = line.strip().split()
    for word in words:
        print(f"{word}\t1")
PYEOF

# reducer.py
cat > /tmp/reducer.py << 'PYEOF'
#!/usr/bin/env python3
import sys
current_word = None
count = 0
for line in sys.stdin:
    word, val = line.strip().split('\t')
    if word == current_word:
        count += int(val)
    else:
        if current_word:
            print(f"{current_word}\t{count}")
        current_word = word
        count = int(val)
if current_word:
    print(f"{current_word}\t{count}")
PYEOF

# 上传脚本
hdfs dfs -put /tmp/mapper.py /scripts/
hdfs dfs -put /tmp/reducer.py /scripts/

# 提交 Streaming 作业
yarn jar /usr/lib/hadoop-mapreduce/hadoop-streaming-*.jar \
  -files /tmp/mapper.py,/tmp/reducer.py \
  -mapper mapper.py \
  -reducer reducer.py \
  -input /input/wordcount \
  -output /output/streaming_wordcount
```

## 4.3 MapReduce 作业监控

### 4.3.1 实时监控

```bash
# 列出运行中的作业
mapred job -list

# 查看作业状态
mapred job -status job_1788449905_0001

# 查看作业历史
mapred job -history all job_1788449905_0001

# 查看失败任务
mapred job -status job_1788449905_0001 | grep -i fail

# 终止作业
mapred job -kill job_1788449905_0001
```

### 4.3.2 通过 History Server 查看历史

```bash
# API 查询历史作业
curl -s "http://localhost:19888/ws/v1/history/mapreduce/jobs?limit=10" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
jobs=d.get('jobs',{}).get('job',[])
print(f'历史作业数: {len(jobs)}')
for j in jobs:
    print(f\"  {j['id']:<40} {j['state']:<12} {j.get('name','')[:30]}\")
"

# 查看特定作业详情
JOB_ID="job_1788449905_0001"
curl -s "http://localhost:19888/ws/v1/history/mapreduce/jobs/${JOB_ID}" \
  | python3 -m json.tool

# 查看作业 Map/Reduce 任务
curl -s "http://localhost:19888/ws/v1/history/mapreduce/jobs/${JOB_ID}/tasks" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
tasks=d.get('tasks',{}).get('task',[])
failed=[t for t in tasks if t.get('state')=='FAILED']
print(f'总任务: {len(tasks)}, 失败: {len(failed)}')
"
```

## 4.4 MapReduce 调优参数

### 4.4.1 常用性能参数

```bash
# 提交时指定调优参数
yarn jar myapp.jar com.example.MyDriver \
  -Dmapreduce.input.fileinputformat.split.maxsize=134217728 \
  -Dmapreduce.map.cpu.vcores=1 \
  -Dmapreduce.map.memory.mb=1024 \
  -Dmapreduce.map.java.opts=-Xmx819m \
  -Dmapreduce.reduce.cpu.vcores=1 \
  -Dmapreduce.reduce.memory.mb=2048 \
  -Dmapreduce.reduce.java.opts=-Xmx1638m \
  -Dmapreduce.job.reduces=4 \
  -Dmapreduce.task.io.sort.mb=256 \
  -Dmapreduce.map.sort.spill.percent=0.8 \
  /input /output
```

### 4.4.2 关键参数说明

| 参数 | 说明 | 推荐值 |
|------|------|-------|
| `mapreduce.map.memory.mb` | Map 容器内存 | 1024-4096 |
| `mapreduce.reduce.memory.mb` | Reduce 容器内存 | 2048-8192 |
| `mapreduce.map.java.opts` | Map JVM 堆内存 | 容器内存 × 0.8 |
| `mapreduce.task.io.sort.mb` | Map 排序缓冲区 | 256-512 |
| `mapreduce.map.sort.spill.percent` | 排序溢出阈值 | 0.8 |
| `mapreduce.job.reduces` | Reduce 任务数 | 数据量/256MB |
| `mapreduce.input.fileinputformat.split.maxsize` | 最大分片大小 | 128-256MB |

---

# 第五章 ZooKeeper 协调服务操作指南

## 5.1 ZooKeeper 概述

ZooKeeper 是分布式协调服务，为 Hadoop 生态提供分布式锁、配置管理、服务注册等基础能力。本环境部署3节点 ZooKeeper 集群（hostname0、hostname1、hostname2）。

### 5.1.1 组件分布

| 节点 | 宿主机端口 | 容器端口 | 说明 |
|------|-----------|---------|------|
| hostname0 | 21810 | 2181 | ZK Client 端口（宿主机端口为 21810，勿用 2181） |
| hostname1 | 12181 | 2181 | ZK Client 端口（宿主机端口映射） |
| hostname2 | 22181 | 2181 | ZK Client 端口（宿主机端口映射） |
| hostname0 | 2888 | 2888 | Follower 通信（集群内部，不对外转发） |
| hostname0 | 3888 | 3888 | Leader 选举（集群内部，不对外转发） |

> **重要**：2888（Follower 通信）与 3888（Leader 选举）为 ZK 集群内部仲裁端口，
> **绝不能 DNAT 对外转发**，否则会破坏仲裁/被外部冒充 peer，并劫持容器间同端口流量。
> hostname0 的 ZK 客户端对外访问请使用宿主机 **21810**（原本地 2181 已停止对外转发）。

**ZooKeeper 集群连接串**（容器内）：
```
bigtop-hostname0.bigtop.apache.org:2181,bigtop-hostname1.bigtop.apache.org:2181,bigtop-hostname2.bigtop.apache.org:2181
```

## 5.2 ZooKeeper 健康检查

```bash
# 四字命令健康检查
echo ruok | nc bigtop-hostname0.bigtop.apache.org 2181    # 返回 imok 为正常
echo stat | nc bigtop-hostname0.bigtop.apache.org 2181    # 详细统计
echo mntr | nc bigtop-hostname0.bigtop.apache.org 2181    # 监控指标
echo srvr | nc bigtop-hostname0.bigtop.apache.org 2181    # 服务器信息
echo conf | nc bigtop-hostname0.bigtop.apache.org 2181    # 配置信息
echo cons | nc bigtop-hostname0.bigtop.apache.org 2181    # 客户端连接
echo dump | nc bigtop-hostname0.bigtop.apache.org 2181    # 临时节点和会话

# 检查 Leader/Follower 角色
for h in bigtop-hostname0 bigtop-hostname1 bigtop-hostname2; do
  MODE=$(echo srvr | nc ${h}.bigtop.apache.org 2181 2>/dev/null | grep Mode | awk '{print $2}')
  echo "${h}: ${MODE}"
done

# 通过宿主机端口检查
echo ruok | nc localhost 21810   # hostname0（21810）
echo ruok | nc localhost 12181   # hostname1
echo ruok | nc localhost 22181   # hostname2
```

## 5.3 ZooKeeper CLI 操作

### 5.3.1 连接 ZooKeeper

```bash
# 进入容器后连接
docker exec -it bigtop_hostname0 bash
/usr/lib/zookeeper/bin/zkCli.sh -server bigtop-hostname0.bigtop.apache.org:2181

# 连接集群（任意节点均可）
/usr/lib/zookeeper/bin/zkCli.sh \
  -server bigtop-hostname0.bigtop.apache.org:2181,bigtop-hostname1.bigtop.apache.org:2181,bigtop-hostname2.bigtop.apache.org:2181
```

### 5.3.2 节点操作

```bash
# 在 zkCli 中执行以下命令：

# 列出子节点
ls /
ls /hiveserver2
ls /kafka-broker

# 查看节点数据
get /hiveserver2
get /kafka-broker/ids/0

# 查看节点详细信息（包含 ACL 和 stat）
get -s /hiveserver2

# 创建持久节点
create /myapp "application data"

# 创建临时节点（会话结束后删除）
create -e /myapp/session "session data"

# 创建顺序节点
create -s /myapp/node "data"   # 自动追加序号: /myapp/node0000000001

# 更新节点数据
set /myapp "new data"

# 删除节点（必须无子节点）
delete /myapp

# 递归删除（包含子节点）
deleteall /myapp

# 查看节点 ACL
getAcl /hiveserver2

# 查看节点状态
stat /hiveserver2
```

### 5.3.3 查看生产数据

```bash
# 查看 HiveServer2 注册信息
/usr/lib/zookeeper/bin/zkCli.sh -server bigtop-hostname0.bigtop.apache.org:2181 \
  -cmd ls /hiveserver2

# 查看 Kafka Broker 注册信息
/usr/lib/zookeeper/bin/zkCli.sh -server bigtop-hostname0.bigtop.apache.org:2181 \
  -cmd ls /kafka-broker/ids

# 查看 HBase 根节点
/usr/lib/zookeeper/bin/zkCli.sh -server bigtop-hostname0.bigtop.apache.org:2181 \
  -cmd ls /hbase

# 查看 YARN ResourceManager HA 信息（如有）
/usr/lib/zookeeper/bin/zkCli.sh -server bigtop-hostname0.bigtop.apache.org:2181 \
  -cmd ls /yarn-leader-election
```

## 5.4 ZooKeeper 监控

```bash
# 查看 ZooKeeper 性能指标
echo mntr | nc bigtop-hostname0.bigtop.apache.org 2181 | \
  grep -E "zk_avg_latency|zk_max_latency|zk_outstanding_requests|zk_watch_count|zk_znode_count|zk_packets_received|zk_packets_sent"

# 关键指标说明：
# zk_avg_latency         -- 平均延迟（毫秒），正常应 < 10ms
# zk_max_latency         -- 最大延迟
# zk_outstanding_requests -- 排队请求数，正常应接近0
# zk_watch_count         -- Watch 数量
# zk_znode_count         -- ZNode 总数
# zk_packets_received    -- 接收包数（累计）
# zk_packets_sent        -- 发送包数（累计）

# 查看连接客户端数
echo stat | nc bigtop-hostname0.bigtop.apache.org 2181 | \
  grep "Connections"
```

## 5.5 ZooKeeper 日志管理

```bash
# 查看 ZooKeeper 日志
docker exec bigtop_hostname0 tail -f /var/log/zookeeper/zookeeper.log

# 查看 ZooKeeper 事务日志（二进制，需专用工具解析）
docker exec bigtop_hostname0 bash -c "
  ls /var/lib/zookeeper/data/version-2/
"

# 解析事务日志
docker exec bigtop_hostname0 bash -c "
  java -cp /usr/lib/zookeeper/lib/*:/usr/lib/zookeeper/zookeeper-*.jar \
    org.apache.zookeeper.server.LogFormatter \
    /var/lib/zookeeper/data/version-2/log.* 2>/dev/null | head -20
"
```

---

# 第六章 Hive 数据仓库操作指南

## 6.1 Hive 概述

Apache Hive 是构建在 Hadoop 之上的数据仓库工具，提供 SQL 接口（HiveQL）查询存储在 HDFS 中的大规模数据集。本环境使用 Hive 4.0.1。

### 6.1.1 组件分布

| 组件 | 节点 | 端口 | 说明 |
|------|------|------|------|
| HiveServer2 | hostname1 | 10000(JDBC), 10001(HTTP), 10002(UI) | SQL 查询服务 |
| Hive Metastore | hostname1 | 9083 | 元数据服务 |
| MySQL(Hive DB) | hostname1 | 3306 | 元数据存储 |

### 6.1.2 访问地址

```
HiveServer2 Web UI: http://localhost:10002
JDBC URL: jdbc:hive2://localhost:10000/default
Metastore Thrift: thrift://localhost:9083
```

## 6.2 Beeline 客户端操作

### 6.2.1 连接 HiveServer2

```bash
# 进入容器
docker exec -it bigtop_hostname1 bash

# 方式1：直接连接（无认证）
beeline -u "jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000/default" -n hive

# 方式2：交互式连接
beeline
# 在 beeline 提示符中：
# !connect jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000/default hive ""

# 方式3：ZooKeeper 服务发现（HA 模式）
beeline -u "jdbc:hive2://bigtop-hostname0.bigtop.apache.org:2181,bigtop-hostname1.bigtop.apache.org:2181,bigtop-hostname2.bigtop.apache.org:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2"

# 方式4：执行单条命令后退出
beeline -u "jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000/default" \
  -n hive -e "SHOW DATABASES;"

# 方式5：执行 SQL 文件
beeline -u "jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000/default" \
  -n hive -f /tmp/query.sql
```

### 6.2.2 Beeline 常用命令

```sql
-- 在 beeline 中执行（以 ! 开头的是 beeline 命令）

-- 查看帮助
!help

-- 显示所有数据库
SHOW DATABASES;

-- 切换数据库
USE default;

-- 显示所有表
SHOW TABLES;

-- 显示表结构
DESCRIBE tablename;
DESCRIBE FORMATTED tablename;  -- 详细信息（含分区、存储格式等）
DESCRIBE EXTENDED tablename;   -- 最详细信息

-- 查看建表语句
SHOW CREATE TABLE tablename;

-- 显示分区
SHOW PARTITIONS tablename;

-- 查看函数
SHOW FUNCTIONS;
DESCRIBE FUNCTION upper;       -- 查看函数说明

-- 设置参数
SET hive.execution.engine=tez;
SET mapreduce.job.reduces=4;
SET hive.exec.dynamic.partition=true;

-- 查看当前设置
SET;
SET hive.execution.engine;

-- 退出 Beeline
!quit
```

## 6.3 Hive DDL 操作

### 6.3.1 数据库管理

```sql
-- 创建数据库
CREATE DATABASE IF NOT EXISTS mydb
  COMMENT 'My database'
  LOCATION '/warehouse/tablespace/external/hive/mydb.db'
  WITH DBPROPERTIES ('creator'='admin', 'created'='2026-09-04');

-- 查看数据库信息
DESCRIBE DATABASE EXTENDED mydb;

-- 修改数据库属性
ALTER DATABASE mydb SET DBPROPERTIES ('version'='1.0');

-- 删除数据库（含数据）
DROP DATABASE IF EXISTS mydb CASCADE;
```

### 6.3.2 表管理

**创建内部表（Managed Table）：**

```sql
-- 内部表：数据由 Hive 管理，DROP TABLE 时数据一并删除
CREATE TABLE IF NOT EXISTS employees (
  id        INT,
  name      STRING,
  dept      STRING,
  salary    DOUBLE,
  hire_date DATE
)
COMMENT 'Employee information'
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
STORED AS TEXTFILE;
```

**创建外部表（External Table）：**

```sql
-- 外部表：数据不由 Hive 管理，DROP TABLE 只删元数据，不删数据
CREATE EXTERNAL TABLE IF NOT EXISTS logs (
  log_time  TIMESTAMP,
  level     STRING,
  message   STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION '/data/logs/';
```

**创建 ORC 格式表（推荐）：**

```sql
CREATE TABLE orders (
  order_id  BIGINT,
  user_id   INT,
  amount    DECIMAL(10,2),
  status    STRING,
  created   TIMESTAMP
)
STORED AS ORC
TBLPROPERTIES (
  'orc.compress'='ZLIB',
  'orc.stripe.size'='67108864',
  'orc.row.index.stride'='10000'
);
```

**创建分区表：**

```sql
CREATE TABLE sales (
  sale_id   BIGINT,
  product   STRING,
  amount    DECIMAL(10,2)
)
PARTITIONED BY (
  year  INT,
  month INT
)
STORED AS ORC;
```

**创建分桶表：**

```sql
CREATE TABLE user_events (
  user_id   BIGINT,
  event     STRING,
  ts        TIMESTAMP
)
CLUSTERED BY (user_id) INTO 32 BUCKETS
STORED AS ORC;
```

### 6.3.3 表变更操作

```sql
-- 添加列
ALTER TABLE employees ADD COLUMNS (email STRING, phone STRING);

-- 修改列名和类型
ALTER TABLE employees CHANGE COLUMN salary salary DECIMAL(12,2);

-- 重命名表
ALTER TABLE employees RENAME TO staff;

-- 修改表属性
ALTER TABLE orders SET TBLPROPERTIES ('comment'='Order details');

-- 添加分区
ALTER TABLE sales ADD PARTITION (year=2026, month=9)
  LOCATION '/data/sales/2026/09/';

-- 删除分区
ALTER TABLE sales DROP PARTITION (year=2025, month=1);

-- 修复分区（当分区目录手动创建时）
MSCK REPAIR TABLE sales;
```

## 6.4 Hive DML 操作

### 6.4.1 数据加载

```sql
-- 从本地文件加载（复制到 HDFS）
LOAD DATA LOCAL INPATH '/tmp/employees.csv'
INTO TABLE employees;

-- 从 HDFS 加载（移动文件）
LOAD DATA INPATH '/data/employees.csv'
INTO TABLE employees;

-- 覆盖加载（清空后加载）
LOAD DATA LOCAL INPATH '/tmp/employees.csv'
OVERWRITE INTO TABLE employees;

-- 向分区表加载
LOAD DATA INPATH '/data/sales/2026/09/sales.csv'
INTO TABLE sales PARTITION (year=2026, month=9);
```

### 6.4.2 INSERT 操作

```sql
-- 单行插入（效率低，测试用）
INSERT INTO employees VALUES (1, 'Alice', 'Engineering', 85000.00, '2020-01-15');

-- 从查询插入
INSERT INTO TABLE new_employees
SELECT id, name, dept, salary, hire_date
FROM employees
WHERE dept = 'Engineering';

-- 覆盖写入
INSERT OVERWRITE TABLE employees_backup
SELECT * FROM employees;

-- 动态分区插入
SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

INSERT INTO sales PARTITION (year, month)
SELECT sale_id, product, amount,
       YEAR(created_date) as year,
       MONTH(created_date) as month
FROM raw_sales;

-- 多表插入（FROM 子句）
FROM employees
INSERT INTO dept_engineering SELECT * WHERE dept='Engineering'
INSERT INTO dept_marketing SELECT * WHERE dept='Marketing';
```

### 6.4.3 SELECT 查询

```sql
-- 基本查询
SELECT id, name, salary
FROM employees
WHERE dept = 'Engineering'
ORDER BY salary DESC
LIMIT 10;

-- 聚合查询
SELECT dept,
       COUNT(*) as headcount,
       AVG(salary) as avg_salary,
       MAX(salary) as max_salary
FROM employees
GROUP BY dept
HAVING COUNT(*) > 5
ORDER BY avg_salary DESC;

-- JOIN 操作
SELECT e.name, d.dept_name, e.salary
FROM employees e
JOIN departments d ON e.dept = d.dept_id
WHERE e.salary > 50000;

-- LEFT JOIN（保留左表所有行）
SELECT e.name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept = d.dept_id;

-- 子查询
SELECT name, salary
FROM employees
WHERE salary > (
  SELECT AVG(salary) FROM employees
);

-- 窗口函数
SELECT
  name, dept, salary,
  RANK() OVER (PARTITION BY dept ORDER BY salary DESC) as rank,
  AVG(salary) OVER (PARTITION BY dept) as dept_avg
FROM employees;

-- WITH 子句（CTE）
WITH high_earners AS (
  SELECT * FROM employees WHERE salary > 80000
),
dept_summary AS (
  SELECT dept, COUNT(*) cnt FROM high_earners GROUP BY dept
)
SELECT * FROM dept_summary ORDER BY cnt DESC;
```

### 6.4.4 更新和删除（ACID 表）

Hive 4.x 支持 ACID 操作（需要 ORC 格式 + 事务配置）：

```sql
-- 更新记录
UPDATE employees
SET salary = salary * 1.1
WHERE dept = 'Engineering' AND hire_date < '2020-01-01';

-- 删除记录
DELETE FROM employees
WHERE id = 100;

-- MERGE 操作（类似 UPSERT）
MERGE INTO employees AS target
USING new_employees AS source
ON target.id = source.id
WHEN MATCHED THEN UPDATE SET
  target.salary = source.salary,
  target.dept   = source.dept
WHEN NOT MATCHED THEN INSERT
  VALUES (source.id, source.name, source.dept, source.salary, source.hire_date);
```

## 6.5 Hive 性能优化

### 6.5.1 常用优化设置

```sql
-- 使用 Tez 执行引擎（比 MR 快3-10倍）
SET hive.execution.engine=tez;

-- 开启向量化执行（ORC 表效果最佳）
SET hive.vectorized.execution.enabled=true;
SET hive.vectorized.execution.reduce.enabled=true;

-- CBO（基于代价的优化器）
SET hive.cbo.enable=true;
SET hive.compute.query.using.stats=true;
SET hive.stats.fetch.column.stats=true;

-- 动态分区
SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=5000;
SET hive.exec.max.dynamic.partitions.pernode=2000;

-- Map Join（小表 JOIN 优化）
SET hive.auto.convert.join=true;
SET hive.auto.convert.join.noconditionaltask.size=1145324612;  -- 约1GB

-- 并行执行
SET hive.exec.parallel=true;
SET hive.exec.parallel.thread.number=8;

-- 压缩
SET hive.exec.compress.output=true;
SET mapreduce.output.fileoutputformat.compress.codec=org.apache.hadoop.io.compress.SnappyCodec;
```

### 6.5.2 统计信息收集

```sql
-- 收集表级统计信息
ANALYZE TABLE employees COMPUTE STATISTICS;

-- 收集列级统计信息（更准确的 CBO 优化）
ANALYZE TABLE employees COMPUTE STATISTICS FOR COLUMNS id, dept, salary;

-- 查看统计信息
DESCRIBE FORMATTED employees;
-- 查找 numRows, totalSize 等字段
```

### 6.5.3 分区裁剪（Partition Pruning）

```sql
-- 确保查询使用分区过滤
EXPLAIN SELECT * FROM sales WHERE year=2026 AND month=9;
-- 应看到 Partition Filters: year=2026, month=9

-- 不好的写法（全表扫描）
SELECT * FROM sales WHERE YEAR(sale_date) = 2026;
-- 好的写法（使用分区列）
SELECT * FROM sales WHERE year = 2026;
```

## 6.6 Hive 元数据操作

### 6.6.1 通过 Metastore API

```python
# Python 连接 Hive Metastore（需要安装 thrift）
# pip install thrift thrift-sasl PyHive

from thrift.transport import TSocket, TTransport
from thrift.protocol import TBinaryProtocol
from hive_metastore import ThriftHiveMetastore

transport = TSocket.TSocket('localhost', 9083)
transport = TTransport.TBufferedTransport(transport)
protocol = TBinaryProtocol.TBinaryProtocol(transport)
client = ThriftHiveMetastore.Client(protocol)
transport.open()

# 列出数据库
dbs = client.get_all_databases()
print(dbs)

# 列出表
tables = client.get_all_tables('default')
print(tables)

transport.close()
```

### 6.6.2 直接查询元数据库

```bash
# 通过 MySQL 直接查询 Hive 元数据（仅调试用）
docker exec bigtop_hostname1 mysql -uhive -phive hive -e "
SELECT
  d.NAME as db_name,
  t.TBL_NAME as table_name,
  t.TBL_TYPE as type,
  FROM_UNIXTIME(t.CREATE_TIME) as created
FROM TBLS t
JOIN DBS d ON t.DB_ID = d.DB_ID
ORDER BY d.NAME, t.TBL_NAME
LIMIT 30;
"

# 查看分区信息
docker exec bigtop_hostname1 mysql -uhive -phive hive -e "
SELECT
  d.NAME, t.TBL_NAME, p.PART_NAME
FROM PARTITIONS p
JOIN TBLS t ON p.TBL_ID = t.TBL_ID
JOIN DBS d ON t.DB_ID = d.DB_ID
LIMIT 20;
"
```

## 6.7 HiveServer2 日志

```bash
# HiveServer2 日志
docker exec bigtop_hostname1 tail -f /var/log/hive/hiveserver2.log

# Hive Metastore 日志
docker exec bigtop_hostname1 tail -f /var/log/hive/hive-metastore.log

# 查询执行日志（每个查询都有唯一的 Session ID）
docker exec bigtop_hostname1 bash -c "
  grep 'Session ID' /var/log/hive/hiveserver2.log | tail -5
"

# 过滤特定类型的日志
docker exec bigtop_hostname1 bash -c "
  grep 'ERROR\|Exception' /var/log/hive/hiveserver2.log | tail -20
"
```


---

# 第七章 HBase NoSQL 数据库操作指南

## 7.1 HBase 概述

Apache HBase 是构建在 HDFS 之上的分布式 NoSQL 数据库，提供实时随机读写海量结构化数据的能力，适合稀疏的大表场景。

### 7.1.1 组件分布

| 组件 | 节点 | 端口 | 说明 |
|------|------|------|------|
| HBase Master | hostname0 | 16000(RPC), 16010(UI) | 主节点，管理 Region 分配 |
| HBase RegionServer | hostname3 | 16020(RPC), 16030(UI) | 数据存储节点 |

访问地址：
```
HBase Master UI:       http://localhost:16010
RegionServer UI:       http://localhost:16030
```

### 7.1.2 HBase 数据模型

HBase 的核心概念：

- **表（Table）**：由行和列族组成
- **行键（Row Key）**：唯一标识一行，按字典序排列，是主要访问路径
- **列族（Column Family）**：逻辑分组，必须在建表时定义，物理上存储在一起
- **列限定符（Column Qualifier）**：列族内的具体列名，动态添加
- **单元格（Cell）**：由 `{rowkey, column family, column qualifier, timestamp}` 唯一确定
- **版本（Version）**：每个单元格可存储多个时间戳版本

**完整坐标**：`table -> row key -> column family -> column qualifier -> timestamp -> value`

## 7.2 HBase Shell 操作

### 7.2.1 连接 HBase Shell

```bash
# 进入主节点
docker exec -it bigtop_hostname0 bash

# 启动 HBase Shell
hbase shell

# 执行单条命令后退出
echo "status" | hbase shell

# 执行脚本文件
hbase shell /tmp/hbase_script.rb
```

### 7.2.2 集群状态查看

```ruby
# 在 HBase Shell 中执行（Ruby 语法）

# 查看集群状态
status
status 'simple'
status 'detailed'
status 'replication'

# 查看 HBase 版本
version

# 查看当前用户
whoami

# 查看命名空间
list_namespace

# 列出所有表
list

# 查看表详情
describe 'tablename'

# 查看表是否存在
exists 'tablename'

# 查看表是否可用
is_enabled 'tablename'
is_disabled 'tablename'
```

### 7.2.3 表管理操作

```ruby
# 创建表（指定列族）
create 'users', 'info', 'stats'

# 创建表（带详细配置）
create 'users', {
  NAME => 'info',
  VERSIONS => 3,           # 保留3个版本
  TTL => 2592000,          # 30天过期（秒）
  BLOOMFILTER => 'ROW',    # 布隆过滤器
  COMPRESSION => 'SNAPPY'  # 压缩
}, {
  NAME => 'stats',
  VERSIONS => 1,
  COMPRESSION => 'SNAPPY'
}

# 修改表（添加列族）
alter 'users', {NAME => 'logs', VERSIONS => 5}

# 修改列族配置
alter 'users', {NAME => 'info', VERSIONS => 5}

# 删除列族
alter 'users', {NAME => 'logs', METHOD => 'delete'}

# 禁用表（操作前必须禁用）
disable 'users'

# 启用表
enable 'users'

# 删除表（必须先禁用）
disable 'users'
drop 'users'

# 截断表（清空数据，保留结构）
truncate 'users'
```

### 7.2.4 数据写入操作

```ruby
# 写入单个值
put 'users', 'user001', 'info:name', 'Alice'
put 'users', 'user001', 'info:age', '30'
put 'users', 'user001', 'info:email', 'alice@example.com'
put 'users', 'user001', 'stats:login_count', '100'
put 'users', 'user001', 'stats:last_login', '2026-09-04'

# 写入时指定时间戳（毫秒）
put 'users', 'user001', 'info:name', 'Alice Updated', 1725436800000

# 批量写入
['user001', 'user002', 'user003'].each_with_index do |id, i|
  put 'users', id, 'info:name', "User#{i+1}"
  put 'users', id, 'stats:score', (i * 100).to_s
end
```

### 7.2.5 数据读取操作

```ruby
# 读取整行
get 'users', 'user001'

# 读取特定列族
get 'users', 'user001', {COLUMN => 'info'}

# 读取特定列
get 'users', 'user001', {COLUMN => 'info:name'}

# 读取多个列
get 'users', 'user001', {COLUMN => ['info:name', 'info:age', 'stats:score']}

# 读取特定版本数量
get 'users', 'user001', {COLUMN => 'info:name', VERSIONS => 3}

# 读取特定时间戳
get 'users', 'user001', {COLUMN => 'info:name', TIMESTAMP => 1725436800000}

# 读取时间范围
get 'users', 'user001', {
  COLUMN => 'info:name',
  TIMERANGE => [1725436800000, 1725523200000]
}
```

### 7.2.6 扫描操作

```ruby
# 全表扫描（大表慎用）
scan 'users'

# 限制返回行数
scan 'users', {LIMIT => 10}

# 扫描特定列族
scan 'users', {COLUMN => 'info', LIMIT => 20}

# 扫描特定列
scan 'users', {COLUMN => 'info:name', LIMIT => 10}

# 按行键范围扫描（[STARTROW, STOPROW)）
scan 'users', {STARTROW => 'user001', STOPROW => 'user010', LIMIT => 20}

# 前缀扫描
scan 'users', {ROWPREFIXFILTER => 'user0'}

# 时间范围扫描
scan 'users', {TIMERANGE => [1725436800000, 1725523200000], LIMIT => 10}

# 过滤器扫描（复杂过滤）
# 值过滤器：查找 info:age 等于 30 的行
scan 'users', {
  FILTER => "SingleColumnValueFilter('info', 'age', =, 'binary:30')"
}

# 列前缀过滤器
scan 'users', {
  FILTER => "ColumnPrefixFilter('na')"
}

# 行键正则过滤
scan 'users', {
  FILTER => "RowFilter(=, 'regexstring:user00[1-5]')"
}

# 分页过滤（生产环境分页推荐）
scan 'users', {
  FILTER => "PageFilter(10)",
  STARTROW => 'user001'
}

# 统计行数
count 'users'
count 'users', INTERVAL => 1000  # 每1000行输出一次进度
```

### 7.2.7 数据删除操作

```ruby
# 删除特定列值
delete 'users', 'user001', 'info:age'

# 删除特定列特定时间戳的值
delete 'users', 'user001', 'info:name', 1725436800000

# 删除整行
deleteall 'users', 'user001'

# 批量删除（扫描后删除）
scanner = 'users'
scan scanner, {STARTROW => 'user100', STOPROW => 'user200'} do |row, cells|
  deleteall 'users', row
end
```

## 7.3 HBase Java API 操作

### 7.3.1 Maven 依赖

```xml
<dependency>
    <groupId>org.apache.hbase</groupId>
    <artifactId>hbase-client</artifactId>
    <version>2.6.2</version>
</dependency>
```

### 7.3.2 连接配置

```java
// hbase-site.xml 配置
Configuration conf = HBaseConfiguration.create();
conf.set("hbase.zookeeper.quorum",
    "bigtop-hostname0.bigtop.apache.org," +
    "bigtop-hostname1.bigtop.apache.org," +
    "bigtop-hostname2.bigtop.apache.org");
conf.set("hbase.zookeeper.property.clientPort", "2181");
conf.set("hbase.master", "bigtop-hostname0.bigtop.apache.org:16000");

Connection connection = ConnectionFactory.createConnection(conf);
```

### 7.3.3 表操作示例

```java
// 获取表
Table table = connection.getTable(TableName.valueOf("users"));

// 写入数据
Put put = new Put(Bytes.toBytes("user001"));
put.addColumn(Bytes.toBytes("info"), Bytes.toBytes("name"), Bytes.toBytes("Alice"));
put.addColumn(Bytes.toBytes("info"), Bytes.toBytes("age"), Bytes.toBytes("30"));
table.put(put);

// 批量写入
List<Put> puts = new ArrayList<>();
for (int i = 0; i < 1000; i++) {
    Put p = new Put(Bytes.toBytes(String.format("user%05d", i)));
    p.addColumn(Bytes.toBytes("info"), Bytes.toBytes("name"),
                Bytes.toBytes("User" + i));
    puts.add(p);
}
table.put(puts);

// 读取数据
Get get = new Get(Bytes.toBytes("user001"));
get.addColumn(Bytes.toBytes("info"), Bytes.toBytes("name"));
Result result = table.get(get);
byte[] name = result.getValue(Bytes.toBytes("info"), Bytes.toBytes("name"));
System.out.println(Bytes.toString(name));

// 扫描数据
Scan scan = new Scan();
scan.addFamily(Bytes.toBytes("info"));
scan.setStartRow(Bytes.toBytes("user001"));
scan.setStopRow(Bytes.toBytes("user100"));
scan.setLimit(50);

try (ResultScanner scanner = table.getScanner(scan)) {
    for (Result row : scanner) {
        System.out.println(Bytes.toString(row.getRow()));
    }
}

// 删除数据
Delete delete = new Delete(Bytes.toBytes("user001"));
delete.addColumn(Bytes.toBytes("info"), Bytes.toBytes("age"));
table.delete(delete);

table.close();
connection.close();
```

## 7.4 HBase 管理操作

### 7.4.1 Region 管理

```ruby
# 在 HBase Shell 中：

# 查看表的 Region 分布
# 通过 HBase Master UI: http://localhost:16010/table.jsp?name=users

# 手动分裂 Region
split 'users', 'user500'  # 在 user500 处分裂

# 合并 Region（需要 Region 编码）
# merge_region 'ENCODE1', 'ENCODE2'
# 在 Master UI 中查找 Region 编码

# 移动 Region（负载均衡）
move 'REGION_ENCODE', 'bigtop-hostname3.bigtop.apache.org,16020,timestamp'

# 触发 Region 均衡
balancer

# 启用/禁用自动均衡
balance_switch true
balance_switch false
```

### 7.4.2 Compaction 操作

```ruby
# Minor Compaction（合并小 StoreFile，不删除过期数据）
compact 'users'
compact 'users', 'info'  # 指定列族

# Major Compaction（全量合并，删除过期数据和删除标记）
# 注意：Major Compaction 消耗资源多，建议低峰期执行
major_compact 'users'
major_compact 'users', 'info'
```

```bash
# 通过命令行触发
hbase hbck -repair       # 修复一致性问题（谨慎）
hbase hbck -details      # 详细检查
```

### 7.4.3 快照管理

```ruby
# 创建快照
snapshot 'users', 'users_snapshot_20260904'

# 列出快照
list_snapshots

# 恢复快照（先禁用表）
disable 'users'
restore_snapshot 'users_snapshot_20260904'
enable 'users'

# 从快照克隆新表
clone_snapshot 'users_snapshot_20260904', 'users_backup'

# 删除快照
delete_snapshot 'users_snapshot_20260904'

# 导出快照到其他集群
# （在Shell外执行）
# hbase snapshot export -snapshot users_snapshot_20260904 \
#   -copy-to hdfs://other-cluster/hbase
```

## 7.5 HBase 监控

```bash
# HBase Master JMX 指标
curl -s "http://localhost:16010/jmx" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for b in d.get('beans',[]):
    if 'Master' in b.get('name',''):
        print('=== HBase Master ===')
        for k,v in b.items():
            if isinstance(v,(int,float)) and k not in ['modelerType']:
                print(f'  {k}: {v}')
        break
"

# RegionServer JMX 指标
curl -s "http://localhost:16030/jmx" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for b in d.get('beans',[]):
    if 'RegionServer' in b.get('name','') and 'IO' in b.get('name',''):
        print('=== RegionServer IO ===')
        for k in ['readRequestCount','writeRequestCount','fsReadLatencyHistogramMean']:
            print(f'  {k}: {b.get(k,\"N/A\")}')
" 2>/dev/null

# HBase 日志
docker exec bigtop_hostname0 tail -f /var/log/hbase/hbase-hbase-master-*.log
docker exec bigtop_hostname3 tail -f /var/log/hbase/hbase-hbase-regionserver-*.log
```

## 7.6 HBase 数据导入导出

### 7.6.1 ImportTsv（TSV/CSV 导入）

```bash
# 准备 TSV 数据
cat > /tmp/users.tsv << 'EOF'
user001Alice30Engineering
user002Bob28Marketing
user003Carol35Engineering
EOF
hdfs dfs -put /tmp/users.tsv /import/hbase/

# 创建目标表
echo "create 'users_import', 'info'" | hbase shell

# 导入
yarn jar /usr/lib/hbase/lib/hbase-mapreduce-*.jar importtsv \
  -Dimporttsv.separator='\t' \
  -Dimporttsv.columns=HBASE_ROW_KEY,info:name,info:age,info:dept \
  users_import /import/hbase/users.tsv
```

### 7.6.2 Export/Import（HBase 原生格式）

```bash
# 导出表到 HDFS
yarn jar /usr/lib/hbase/lib/hbase-mapreduce-*.jar \
  org.apache.hadoop.hbase.mapreduce.Export \
  users /export/hbase/users

# 导入表
yarn jar /usr/lib/hbase/lib/hbase-mapreduce-*.jar \
  org.apache.hadoop.hbase.mapreduce.Import \
  users_new /export/hbase/users
```


---

# 第八章 Kafka 消息队列操作指南

## 8.1 Kafka 概述

Apache Kafka 是高吞吐量分布式消息系统，用于构建实时数据管道和流式应用。本环境在 hostname0 部署单节点 Kafka Broker。

### 8.1.1 组件配置

| 组件 | 节点 | 宿主机端口 | 容器端口 | 说明 |
|------|------|-----------|---------|------|
| Kafka Broker | hostname0 | 9092 | 9092 | PLAINTEXT 协议 |
| Kafka Broker SSL | hostname0 | 9093 | 9093 | SSL 协议 |
| ZooKeeper | hostname0 | 2181 | 2181 | Broker 元数据存储 |

**Broker 连接串**：`localhost:9092`（宿主机）或 `bigtop-hostname0.bigtop.apache.org:9092`（容器内）

## 8.2 Topic 管理

### 8.2.1 创建 Topic

```bash
# 进入容器
docker exec -it bigtop_hostname0 bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 创建基本 Topic
kafka-topics.sh --create \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 1

# 创建带配置的 Topic
kafka-topics.sh --create \
  --bootstrap-server ${BOOTSTRAP} \
  --topic events \
  --partitions 6 \
  --replication-factor 1 \
  --config retention.ms=86400000 \      # 保留1天
  --config retention.bytes=1073741824 \ # 保留1GB
  --config max.message.bytes=1048576 \  # 最大消息1MB
  --config cleanup.policy=delete        # 删除策略（delete/compact）

# 创建压缩 Topic（适合 CDC/状态流）
kafka-topics.sh --create \
  --bootstrap-server ${BOOTSTRAP} \
  --topic user-state \
  --partitions 4 \
  --replication-factor 1 \
  --config cleanup.policy=compact \
  --config min.cleanable.dirty.ratio=0.5 \
  --config delete.retention.ms=86400000
```

### 8.2.2 查看 Topic 信息

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 列出所有 Topic
kafka-topics.sh --list --bootstrap-server ${BOOTSTRAP}

# 查看 Topic 详情
kafka-topics.sh --describe \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic

# 输出示例：
# Topic: test-topic  Partition: 0  Leader: 0  Replicas: 0  Isr: 0
# Topic: test-topic  Partition: 1  Leader: 0  Replicas: 0  Isr: 0

# 查看所有 Topic 详情
kafka-topics.sh --describe --bootstrap-server ${BOOTSTRAP}

# 查看 Topic 偏移量
kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list ${BOOTSTRAP} \
  --topic test-topic

# 查看 Topic 最新偏移量
kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list ${BOOTSTRAP} \
  --topic test-topic \
  --time -1   # -1=最新, -2=最早
```

### 8.2.3 修改 Topic 配置

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 修改分区数（只能增加，不能减少）
kafka-topics.sh --alter \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --partitions 6

# 修改配置
kafka-configs.sh --alter \
  --bootstrap-server ${BOOTSTRAP} \
  --entity-type topics \
  --entity-name test-topic \
  --add-config retention.ms=172800000   # 改为2天

# 删除配置（恢复默认值）
kafka-configs.sh --alter \
  --bootstrap-server ${BOOTSTRAP} \
  --entity-type topics \
  --entity-name test-topic \
  --delete-config retention.ms

# 查看 Topic 动态配置
kafka-configs.sh --describe \
  --bootstrap-server ${BOOTSTRAP} \
  --entity-type topics \
  --entity-name test-topic
```

### 8.2.4 删除 Topic

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

kafka-topics.sh --delete \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic
```

## 8.3 消息生产与消费

### 8.3.1 控制台生产者

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 基本生产者（每行一条消息，Ctrl+D 结束）
kafka-console-producer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic

# 输入消息：
# > Hello Kafka
# > This is a test message
# > ^D

# 带 Key 的生产者（Key:Value 格式）
kafka-console-producer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --property key.separator=: \
  --property parse.key=true

# 输入：
# > user001:{"name":"Alice","action":"login"}

# 从文件批量发送
cat /tmp/messages.txt | kafka-console-producer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic

# 指定生产者参数
kafka-console-producer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --producer-property acks=all \
  --producer-property linger.ms=100 \
  --producer-property batch.size=16384
```

### 8.3.2 控制台消费者

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 从最新消息开始消费
kafka-console-consumer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic

# 从头开始消费所有消息
kafka-console-consumer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --from-beginning

# 显示 Key 和时间戳
kafka-console-consumer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --from-beginning \
  --property print.key=true \
  --property print.timestamp=true \
  --property key.separator=" | "

# 指定消费组（用于 offset 管理）
kafka-console-consumer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --group my-consumer-group \
  --from-beginning

# 只消费特定数量的消息
kafka-console-consumer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --from-beginning \
  --max-messages 100

# 消费特定分区的特定 offset
kafka-console-consumer.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --partition 0 \
  --offset 100    # 从 offset 100 开始
```

## 8.4 消费者组管理

### 8.4.1 查看消费者组

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 列出所有消费者组
kafka-consumer-groups.sh --list --bootstrap-server ${BOOTSTRAP}

# 查看消费者组详情（含 lag 信息）
kafka-consumer-groups.sh \
  --describe \
  --bootstrap-server ${BOOTSTRAP} \
  --group my-consumer-group

# 输出字段说明：
# GROUP          消费者组名
# TOPIC          Topic 名
# PARTITION      分区号
# CURRENT-OFFSET 当前消费 offset
# LOG-END-OFFSET Topic 最新 offset
# LAG            积压量（LOG-END-OFFSET - CURRENT-OFFSET）
# CONSUMER-ID    消费者实例ID
# HOST           消费者主机

# 查看所有消费者组的 lag
kafka-consumer-groups.sh \
  --describe \
  --bootstrap-server ${BOOTSTRAP} \
  --all-groups

# 只显示有积压的消费者组
kafka-consumer-groups.sh \
  --describe \
  --bootstrap-server ${BOOTSTRAP} \
  --all-groups 2>/dev/null | \
  awk 'NR==1 || $6>0' | column -t
```

### 8.4.2 重置消费 Offset

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"
GROUP="my-consumer-group"
TOPIC="test-topic"

# 重置到最早（--dry-run 先预览，不执行）
kafka-consumer-groups.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --group ${GROUP} \
  --topic ${TOPIC} \
  --reset-offsets --to-earliest \
  --dry-run

# 执行重置（消费者必须停止）
kafka-consumer-groups.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --group ${GROUP} \
  --topic ${TOPIC} \
  --reset-offsets --to-earliest \
  --execute

# 重置到最新
kafka-consumer-groups.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --group ${GROUP} \
  --topic ${TOPIC} \
  --reset-offsets --to-latest \
  --execute

# 重置到特定时间（UTC）
kafka-consumer-groups.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --group ${GROUP} \
  --topic ${TOPIC} \
  --reset-offsets \
  --to-datetime 2026-09-04T00:00:00.000 \
  --execute

# 向前/向后移动 offset
kafka-consumer-groups.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --group ${GROUP} \
  --topic ${TOPIC} \
  --reset-offsets --shift-by -1000 \  # 后退1000条
  --execute

# 删除消费者组（无活跃成员时）
kafka-consumer-groups.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --delete --group ${GROUP}
```

## 8.5 Kafka 性能测试

### 8.5.1 生产者性能测试

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 生产 100 万条 1KB 消息
kafka-producer-perf-test.sh \
  --topic test-topic \
  --num-records 1000000 \
  --record-size 1024 \
  --throughput -1 \
  --producer-props bootstrap.servers=${BOOTSTRAP} acks=1

# 输出解读：
# 1000000 records sent, 85000.000 records/sec (83.01 MB/sec),
# 12.50 ms avg latency, 500.00 ms max latency
```

### 8.5.2 消费者性能测试

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

kafka-consumer-perf-test.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic test-topic \
  --messages 1000000 \
  --group perf-test-group
```

## 8.6 Kafka 监控

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 查看 Broker 配置
kafka-configs.sh --describe \
  --bootstrap-server ${BOOTSTRAP} \
  --entity-type brokers \
  --entity-name 0

# 查看 Broker 日志目录大小
kafka-log-dirs.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --topic-list test-topic \
  --describe

# Kafka 日志
docker exec bigtop_hostname0 tail -f /var/log/kafka/server.log

# 过滤关键事件
docker exec bigtop_hostname0 bash -c "
  grep 'ERROR\|Leader\|partition\|topic' /var/log/kafka/server.log | tail -20
"
```

## 8.7 Kafka 与其他组件集成

### 8.7.1 Kafka + Spark Streaming

```scala
// Spark Streaming 消费 Kafka
import org.apache.spark.streaming.kafka010._
import org.apache.kafka.common.serialization.StringDeserializer

val kafkaParams = Map[String, Object](
  "bootstrap.servers" -> "bigtop-hostname0.bigtop.apache.org:9092",
  "key.deserializer" -> classOf[StringDeserializer],
  "value.deserializer" -> classOf[StringDeserializer],
  "group.id" -> "spark-consumer-group",
  "auto.offset.reset" -> "latest",
  "enable.auto.commit" -> (false: java.lang.Boolean)
)

val topics = Array("test-topic")
val stream = KafkaUtils.createDirectStream[String, String](
  streamingContext,
  LocationStrategies.PreferConsistent,
  ConsumerStrategies.Subscribe[String, String](topics, kafkaParams)
)

stream.map(record => (record.key, record.value))
      .foreachRDD { rdd =>
        rdd.foreach { case (key, value) =>
          println(s"Key: $key, Value: $value")
        }
      }
```

### 8.7.2 Kafka + Flink

```java
// Flink 消费 Kafka
Properties props = new Properties();
props.setProperty("bootstrap.servers", "bigtop-hostname0.bigtop.apache.org:9092");
props.setProperty("group.id", "flink-consumer-group");

FlinkKafkaConsumer<String> consumer = new FlinkKafkaConsumer<>(
    "test-topic",
    new SimpleStringSchema(),
    props
);
consumer.setStartFromLatest();

DataStream<String> stream = env.addSource(consumer);
```


---

# 第九章 Spark 计算引擎操作指南

## 9.1 Spark 概述

Apache Spark 是统一的大数据处理引擎，支持批处理、流处理、机器学习和图计算。本环境 Spark History Server 在 hostname0，运行模式为 YARN。

### 9.1.1 组件分布

| 组件 | 节点 | 宿主机端口 | 说明 |
|------|------|-----------|------|
| Spark History Server | hostname0 | 18081 | 历史作业查看 |

访问地址：`http://localhost:18081`

### 9.1.2 Spark 运行模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| `yarn --deploy-mode client` | Driver 在提交节点 | 交互式开发、调试 |
| `yarn --deploy-mode cluster` | Driver 在 YARN 容器 | 生产环境、长时间作业 |
| `local[N]` | 本地 N 线程 | 本地测试 |
| `local[*]` | 本地所有 CPU | 本地测试 |

## 9.2 spark-submit 提交作业

### 9.2.1 基本提交

```bash
docker exec -it bigtop_hostname0 bash

# 提交 Scala/Java 作业到 YARN
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --class org.apache.spark.examples.SparkPi \
  /usr/lib/spark/examples/jars/spark-examples_*.jar \
  100

# 提交 Python 作业
spark-submit \
  --master yarn \
  --deploy-mode client \
  /tmp/my_spark_app.py

# 提交 R 作业
spark-submit \
  --master yarn \
  --deploy-mode client \
  /tmp/my_spark_app.R
```

### 9.2.2 资源配置

```bash
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --class com.example.MyApp \
  --driver-memory 2g \
  --driver-cores 2 \
  --executor-memory 4g \
  --executor-cores 2 \
  --num-executors 4 \
  --conf spark.sql.shuffle.partitions=200 \
  --conf spark.default.parallelism=200 \
  --conf spark.serializer=org.apache.spark.serializer.KryoSerializer \
  --conf spark.kryoserializer.buffer.max=512m \
  --jars /usr/lib/hive/lib/hive-jdbc.jar \
  myapp.jar \
  arg1 arg2
```

### 9.2.3 动态资源分配

```bash
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --conf spark.dynamicAllocation.enabled=true \
  --conf spark.dynamicAllocation.minExecutors=1 \
  --conf spark.dynamicAllocation.maxExecutors=20 \
  --conf spark.dynamicAllocation.initialExecutors=4 \
  --conf spark.shuffle.service.enabled=true \
  --class com.example.MyApp \
  myapp.jar
```

## 9.3 Spark Shell 交互式操作

### 9.3.1 启动 Spark Shell

```bash
# Scala Shell（YARN client 模式）
spark-shell --master yarn --deploy-mode client \
  --driver-memory 2g \
  --executor-memory 2g \
  --num-executors 2

# PySpark Shell
pyspark --master yarn --deploy-mode client \
  --driver-memory 2g \
  --executor-memory 2g \
  --num-executors 2

# SparkR Shell
sparkR --master yarn --deploy-mode client
```

### 9.3.2 Spark Core 操作（Scala）

```scala
// 在 spark-shell 中执行

// 创建 RDD
val rdd = sc.parallelize(1 to 1000, 4)  // 4个分区

// 读取 HDFS 文件
val textRDD = sc.textFile("hdfs:///data/input/data.txt")
val textRDD = sc.textFile("hdfs:///data/input/*.csv")

// Transformations（懒执行）
val filteredRDD = rdd.filter(_ % 2 == 0)
val mappedRDD = textRDD.map(line => line.split(","))
val flatRDD = textRDD.flatMap(line => line.split(" "))
val pairedRDD = textRDD.map(line => {
  val parts = line.split(",")
  (parts(0), parts(1).toInt)
})

// Actions（触发执行）
rdd.count()
rdd.sum()
rdd.max()
filteredRDD.take(10).foreach(println)
filteredRDD.collect()  // 慎用，会将所有数据收集到 Driver
filteredRDD.saveAsTextFile("hdfs:///output/result")

// Word Count
val wordCount = sc.textFile("hdfs:///data/input/")
  .flatMap(_.split(" "))
  .map(word => (word, 1))
  .reduceByKey(_ + _)
  .sortBy(_._2, ascending=false)

wordCount.take(10).foreach(println)
wordCount.saveAsTextFile("hdfs:///output/wordcount")

// Join 操作
val orders = sc.textFile("hdfs:///data/orders.csv")
  .map(line => { val p=line.split(","); (p(0), p(1).toDouble) })

val users = sc.textFile("hdfs:///data/users.csv")
  .map(line => { val p=line.split(","); (p(0), p(1)) })

val joined = orders.join(users)
// joined: RDD[(String, (Double, String))]

// 持久化 RDD（避免重复计算）
import org.apache.spark.storage.StorageLevel
val cachedRDD = rdd.persist(StorageLevel.MEMORY_AND_DISK)
// 等同于 rdd.cache()（只使用内存）

// 释放缓存
cachedRDD.unpersist()
```

### 9.3.3 Spark SQL 操作

```scala
// 在 spark-shell 中执行（Spark SQL）
import spark.implicits._

// 创建 DataFrame
val df = spark.read
  .option("header", "true")
  .option("inferSchema", "true")
  .csv("hdfs:///data/input/employees.csv")

df.printSchema()
df.show(10)
df.describe().show()

// SQL 查询
df.createOrReplaceTempView("employees")

val result = spark.sql("""
  SELECT dept,
         COUNT(*) as headcount,
         AVG(salary) as avg_salary,
         MAX(salary) as max_salary
  FROM employees
  WHERE hire_date >= '2020-01-01'
  GROUP BY dept
  ORDER BY avg_salary DESC
""")
result.show()

// DataFrame API
df.select("name", "dept", "salary")
  .filter($"dept" === "Engineering")
  .filter($"salary" > 80000)
  .orderBy($"salary".desc)
  .show(20)

// GroupBy 聚合
df.groupBy("dept")
  .agg(
    count("*").as("headcount"),
    avg("salary").as("avg_salary"),
    max("salary").as("max_salary")
  )
  .orderBy($"avg_salary".desc)
  .show()

// Join 操作
val depts = spark.read.option("header","true").csv("hdfs:///data/departments.csv")
val joined = df.join(depts, df("dept_id") === depts("id"), "left")
joined.select("name", "dept_name", "salary").show()

// 写出结果
result.write
  .mode("overwrite")
  .option("header", "true")
  .csv("hdfs:///output/dept_summary")

// 写为 ORC 格式（高效）
result.write
  .mode("overwrite")
  .format("orc")
  .save("hdfs:///output/dept_summary_orc")

// 写入 Hive 表
result.write
  .mode("overwrite")
  .saveAsTable("default.dept_summary")
```

### 9.3.4 读写 Hive 数据

```scala
// spark-shell 中（需要 Hive 支持，本环境已配置）

// 读取 Hive 表
val employees = spark.table("default.employees")
employees.show(5)

// 写入 Hive 表（追加）
result.write
  .mode("append")
  .format("hive")
  .saveAsTable("default.dept_summary")

// 读写分区 Hive 表
spark.sql("""
  INSERT INTO TABLE sales PARTITION (year=2026, month=9)
  SELECT sale_id, product, amount
  FROM raw_sales
  WHERE year=2026 AND month=9
""")
```

## 9.4 Spark Streaming 操作

### 9.4.1 DStream（传统流处理）

```scala
import org.apache.spark.streaming._
import org.apache.spark.streaming.kafka010._
import org.apache.kafka.common.serialization.StringDeserializer

val ssc = new StreamingContext(spark.sparkContext, Seconds(5))

val kafkaParams = Map[String, Object](
  "bootstrap.servers" -> "bigtop-hostname0.bigtop.apache.org:9092",
  "key.deserializer" -> classOf[StringDeserializer],
  "value.deserializer" -> classOf[StringDeserializer],
  "group.id" -> "spark-streaming-group",
  "auto.offset.reset" -> "latest",
  "enable.auto.commit" -> (false: java.lang.Boolean)
)

val topics = Array("events")
val stream = KafkaUtils.createDirectStream[String, String](
  ssc,
  LocationStrategies.PreferConsistent,
  ConsumerStrategies.Subscribe[String, String](topics, kafkaParams)
)

// 处理每批数据
stream.map(_.value())
  .flatMap(_.split(" "))
  .map(word => (word, 1))
  .reduceByKeyAndWindow(_ + _, Seconds(60), Seconds(5))
  .foreachRDD { rdd =>
    if (!rdd.isEmpty()) {
      rdd.sortBy(_._2, false).take(10).foreach(println)
    }
  }

ssc.start()
ssc.awaitTermination()
```

### 9.4.2 Structured Streaming（推荐）

```scala
import org.apache.spark.sql.streaming._

// 从 Kafka 读取流数据
val stream = spark.readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "bigtop-hostname0.bigtop.apache.org:9092")
  .option("subscribe", "events")
  .option("startingOffsets", "latest")
  .load()

// 解析 JSON 消息
import org.apache.spark.sql.types._
import org.apache.spark.sql.functions._

val schema = StructType(Array(
  StructField("user_id", StringType),
  StructField("action", StringType),
  StructField("timestamp", LongType)
))

val events = stream
  .select(from_json(col("value").cast("string"), schema).as("data"))
  .select("data.*")
  .withColumn("event_time", to_timestamp(col("timestamp").divide(1000)))

// 流式聚合（带水位线）
val result = events
  .withWatermark("event_time", "10 minutes")
  .groupBy(
    window($"event_time", "5 minutes"),
    $"action"
  )
  .count()

// 输出到控制台（测试）
val query = result.writeStream
  .outputMode("update")
  .format("console")
  .option("truncate", false)
  .trigger(Trigger.ProcessingTime("10 seconds"))
  .start()

// 输出到 Kafka
val kafkaOutput = result.writeStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "bigtop-hostname0.bigtop.apache.org:9092")
  .option("topic", "output-topic")
  .option("checkpointLocation", "hdfs:///spark/checkpoints/events")
  .outputMode("update")
  .start()

// 输出到 HDFS（Parquet）
val hdfsOutput = events.writeStream
  .format("parquet")
  .option("path", "hdfs:///output/events/")
  .option("checkpointLocation", "hdfs:///spark/checkpoints/events-hdfs")
  .partitionBy("action")
  .start()

query.awaitTermination()
```

## 9.5 Spark 监控与调优

### 9.5.1 History Server 操作

访问 `http://localhost:18081` 查看历史作业。

```bash
# History Server 日志
docker exec bigtop_hostname0 tail -f /var/log/spark/spark-spark-org.apache.spark.deploy.history.HistoryServer*.log

# 创建 Spark 事件日志目录
hdfs dfs -mkdir -p /spark-history
hdfs dfs -chmod 1777 /spark-history
```

### 9.5.2 常用性能调优参数

```bash
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  # 序列化（Kryo 比 Java 序列化快）
  --conf spark.serializer=org.apache.spark.serializer.KryoSerializer \
  --conf spark.kryoserializer.buffer.max=512m \
  # Shuffle 优化
  --conf spark.sql.shuffle.partitions=200 \
  --conf spark.default.parallelism=200 \
  --conf spark.shuffle.compress=true \
  --conf spark.shuffle.spill.compress=true \
  # 内存管理
  --conf spark.memory.fraction=0.8 \
  --conf spark.memory.storageFraction=0.3 \
  # 广播 join 阈值
  --conf spark.sql.autoBroadcastJoinThreshold=52428800 \  # 50MB
  # 压缩
  --conf spark.sql.parquet.compression.codec=snappy \
  # 动态分区裁剪
  --conf spark.sql.optimizer.dynamicPartitionPruning.enabled=true \
  --class com.example.MyApp myapp.jar
```

### 9.5.3 查看作业日志

```bash
# 查看 YARN 容器日志
yarn logs -applicationId application_xxx_yyy

# 查看特定执行器日志
yarn logs -applicationId application_xxx_yyy \
  -containerId container_xxx_yyy_zzz
```

## 9.6 PySpark 操作示例

```python
# PySpark 完整示例（wordcount）
from pyspark.sql import SparkSession
from pyspark.sql.functions import explode, split, col, count

spark = SparkSession.builder \
    .appName("WordCount") \
    .master("yarn") \
    .config("spark.executor.memory", "2g") \
    .enableHiveSupport() \
    .getOrCreate()

# 读取数据
df = spark.read.text("hdfs:///data/input/")

# 处理
wordcount = df \
    .select(explode(split(col("value"), " ")).alias("word")) \
    .filter(col("word") != "") \
    .groupBy("word") \
    .agg(count("*").alias("count")) \
    .orderBy("count", ascending=False)

# 输出
wordcount.show(20)
wordcount.write.mode("overwrite").csv("hdfs:///output/wordcount_py")

spark.stop()
```

---

## 9.7 Iceberg 数据湖操作指南

### 9.7.1 概述

集群已集成 **Iceberg 1.11.0**（`iceberg-spark-runtime-3.5_2.12-1.11.0.jar`，
部署在 hostname0 / hostname3 的 `$SPARK_HOME/jars`）。

| 项目 | 值 |
|------|-----|
| Catalog | `iceberg`（Hadoop Catalog） |
| Warehouse | `hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse` |
| Session | `in-memory`（`spark.sql.catalogImplementation=in-memory`） |
| SQL扩展 | `org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions` |

### 9.7.2 为什么采用 Hadoop Catalog

Iceberg 1.11 runtime 的 `ExtendedParser` 等类以 **Java 17** 编译
（class major 61），而 Bigtop Spark 默认 **Java 8** 运行会报
`UnsupportedClassVersionError`。切到 JDK 17 后，Spark 内置的 Hive 3.1 客户端
（Java 8 时代）又出现 `NoSuchFieldError: out`。因此本集群采用
**Hadoop Catalog + in-memory session**：完全绕过 Hive client 初始化，
Iceberg 元数据（snapshot / manifest / 表目录）以文件形式直接存放于 HDFS。
如需与 Hive 表互通，可后续引入 Hive Catalog（需在 JDK 8 下的独立 Spark 实例）。

### 9.7.3 前置配置（固化在 setup-iceberg.sh）

| 配置项 | 目标值 | 位置 |
|--------|--------|------|
| `dfs.replication` | 1 | Ambari hdfs-site tag=`datanode-hostname` |
| `dfs.datanode.use.datanode.hostname` | true | 同上（DataNode 上报主机名避免网关 IP） |
| `JAVA_HOME` | java-17-openjdk | `/etc/spark/conf.dist/spark-env.sh` |
| `spark-defaults` Iceberg 段 | 见下 | `/etc/spark/conf.dist/spark-defaults.conf` |

```properties
spark.sql.catalog.iceberg org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.iceberg.type hadoop
spark.sql.catalog.iceberg.warehouse hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse
spark.sql.extensions org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.sql.catalogImplementation in-memory
spark.yarn.appMasterEnv.JAVA_HOME /usr/lib/jvm/java-17-openjdk
spark.executorEnv.JAVA_HOME /usr/lib/jvm/java-17-openjdk
spark.sql.hive.metastore.version 3.1.3
```

### 9.7.4 常用操作

```bash
# 以 hdfs 用户进入 Spark SQL（需 HDFS 写权限）
sudo -u hdfs spark-sql --master yarn
```

```sql
-- 1. 建库建表
CREATE DATABASE IF NOT EXISTS iceberg.demo;
CREATE TABLE IF NOT EXISTS iceberg.demo.users (
  id INT, name STRING, city STRING, ts TIMESTAMP
) USING iceberg PARTITIONED BY (city);

-- 2. 写入与覆盖写（每次写生成新快照）
INSERT INTO iceberg.demo.users VALUES
  (1, 'alice', 'beijing', current_timestamp()),
  (2, 'bob', 'shanghai', current_timestamp());
INSERT OVERWRITE iceberg.demo.users
  SELECT 1, 'alice', 'beijing', current_timestamp();

-- 3. 查询
SELECT * FROM iceberg.demo.users;
SELECT city, count(*) FROM iceberg.demo.users GROUP BY city;

-- 4. MERGE INTO（需要 spark.sql.extensions）
MERGE INTO iceberg.demo.users t
USING (SELECT 2 AS id, 'bobby' AS name) s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET name = s.name;

-- 5. 快照查看（时间旅行基础）
SELECT snapshot_id, committed_at, operation
FROM iceberg.demo.users.snapshots;

-- 6. 元数据表
SELECT * FROM iceberg.demo.users.metadata;
```

### 9.7.5 数据文件与清理

Iceberg 表以目录形式存储于 warehouse：

```bash
sudo -u hdfs hdfs dfs -ls -R /iceberg-warehouse/demo.db/users
# data/   → Parquet 数据文件
# metadata/ → version-hint.text、vN.metadata.json、snap-*.avro、manifest 文件
```

过期文件清理（可选，定期执行）：

```sql
CALL iceberg.system.remove_orphan_files('iceberg.demo.users');
CALL iceberg.system.expire_snapshots('iceberg.demo.users');
```

### 9.7.6 容器重启后的恢复

容器重启后 `setup-hostname.sh` 会自动重放 `setup-iceberg.sh`（部署 jar、
恢复 JDK 17 与 spark-defaults 配置、对齐 Ambari desired_configs、确保
warehouse 存在）。若需手动执行：

```bash
cd ambari3 && ./scripts/setup-iceberg.sh
```

---

# 第十章 Ranger 权限管理操作指南

## 10.1 Ranger 概述

Apache Ranger 提供细粒度的、集中化的安全策略管理，支持 HDFS、Hive、HBase、Kafka、YARN 等组件的访问控制和审计。

### 10.1.1 组件分布

| 组件 | 节点 | 宿主机端口 | 说明 |
|------|------|-----------|------|
| Ranger Admin | hostname1 | 6080(HTTP) | Web UI 和 REST API |
| Ranger Usersync | hostname1 | 6083 | 用户同步服务 |
| Ranger Tagsync | hostname3 | 6085 | 标签同步服务 |

访问地址：`http://localhost:6080`  
管理员账户：`admin / Admin1234!`

### 10.1.2 Ranger 架构

```
用户/服务 → Ranger Plugin → Ranger Admin → 策略数据库
                 ↑
          本地策略缓存（每30秒更新）
```

- **Ranger Admin**：中央策略管理服务，提供 UI 和 REST API
- **Ranger Plugin**：嵌入各服务（Hive/HDFS/HBase/Kafka），拦截访问请求
- **Ranger Usersync**：从 LDAP/AD 或 Unix 同步用户和组信息
- **Ranger Tagsync**：从 Apache Atlas 同步标签（Tag-based policies）

## 10.2 Ranger Web UI 操作

### 10.2.1 登录和导航

1. 打开浏览器访问 `http://localhost:6080`
2. 使用 `admin / Admin1234!` 登录
3. 主界面分为：
   - **Service Manager**：各服务插件管理
   - **Access Manager → Resource Based Policies**：基于资源的策略
   - **Access Manager → Tag Based Policies**：基于标签的策略
   - **Audit → Access**：访问审计日志
   - **Security Zone**：安全区域管理

### 10.2.2 服务（Service）管理

Ranger 中每个受保护服务对应一个 Service 实例：

| 服务类型 | 说明 |
|---------|------|
| HDFS | HDFS 路径访问控制 |
| Hive | Hive 数据库/表/列访问控制 |
| HBase | HBase 表/列族访问控制 |
| Kafka | Kafka Topic 访问控制 |
| YARN | YARN 队列访问控制 |

**查看服务状态**：Service Manager 页面每个服务右侧有连接状态指示器。

## 10.3 策略管理

### 10.3.1 HDFS 策略

**创建 HDFS 访问策略（UI 操作）**：

1. Access Manager → Resource Based Policies → HDFS
2. 点击 "Add New Policy"
3. 填写：
   - **Policy Name**：策略名称（如 `data-team-read`）
   - **Resource Path**：`/data/project/*`（支持通配符）
   - **Recursive**：勾选（递归应用）
   - **Allow Conditions**：
     - User：`alice, bob`
     - Group：`data-team`
     - Permissions：`read, execute`
4. 点击 "Add"

**通过 REST API 创建策略**：

```bash
curl -u admin:Admin1234! -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "data-team-read-policy",
    "service": "qixuandata_hadoop",
    "resources": {
      "path": {
        "values": ["/data/project"],
        "isRecursive": true,
        "isExcludes": false
      }
    },
    "policyItems": [{
      "accesses": [
        {"type": "read", "isAllowed": true},
        {"type": "execute", "isAllowed": true}
      ],
      "users": ["alice", "bob"],
      "groups": ["data-team"],
      "conditions": [],
      "delegateAdmin": false
    }],
    "isEnabled": true,
    "isAuditEnabled": true
  }' \
  "http://localhost:6080/service/public/v2/api/policy"
```

### 10.3.2 Hive 策略

```bash
# 创建 Hive 数据库访问策略
curl -u admin:Admin1234! -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "hive-analyst-policy",
    "service": "qixuandata_hive",
    "resources": {
      "database": {
        "values": ["analytics"],
        "isExcludes": false,
        "isRecursive": false
      },
      "table": {
        "values": ["*"],
        "isExcludes": false,
        "isRecursive": false
      },
      "column": {
        "values": ["*"],
        "isExcludes": false,
        "isRecursive": false
      }
    },
    "policyItems": [{
      "accesses": [
        {"type": "select", "isAllowed": true},
        {"type": "update", "isAllowed": false}
      ],
      "users": [],
      "groups": ["analysts"],
      "conditions": [],
      "delegateAdmin": false
    }],
    "isEnabled": true,
    "isAuditEnabled": true
  }' \
  "http://localhost:6080/service/public/v2/api/policy"

# 列脱敏策略（隐藏敏感列）
curl -u admin:Admin1234! -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "mask-phone-number",
    "service": "qixuandata_hive",
    "policyType": 1,
    "resources": {
      "database": {"values": ["users"]},
      "table": {"values": ["customer"]},
      "column": {"values": ["phone"]}
    },
    "dataMaskPolicyItems": [{
      "dataMaskInfo": {"dataMaskType": "MASK_SHOW_LAST_4"},
      "accesses": [{"type": "select", "isAllowed": true}],
      "users": [],
      "groups": ["analysts"]
    }]
  }' \
  "http://localhost:6080/service/public/v2/api/policy"
```

### 10.3.3 Kafka 策略

```bash
# 创建 Kafka Topic 访问策略
curl -u admin:Admin1234! -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "events-producer-policy",
    "service": "qixuandata_kafka",
    "resources": {
      "topic": {
        "values": ["events"],
        "isExcludes": false,
        "isRecursive": false
      }
    },
    "policyItems": [{
      "accesses": [
        {"type": "publish", "isAllowed": true},
        {"type": "describe", "isAllowed": true}
      ],
      "users": ["app-producer"],
      "groups": [],
      "conditions": []
    }],
    "isEnabled": true
  }' \
  "http://localhost:6080/service/public/v2/api/policy"
```

## 10.4 用户和组管理

### 10.4.1 创建用户

```bash
# 创建用户
curl -u admin:Admin1234! -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "alice",
    "password": "Alice123!",
    "firstName": "Alice",
    "lastName": "Smith",
    "emailAddress": "alice@company.com",
    "userRoleList": ["ROLE_USER"]
  }' \
  "http://localhost:6080/service/xusers/secure/users"

# 创建组
curl -u admin:Admin1234! -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "data-team",
    "description": "Data Engineering Team"
  }' \
  "http://localhost:6080/service/xusers/groups"

# 将用户加入组
curl -u admin:Admin1234! -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "userId": <user_id>,
    "groupId": <group_id>
  }' \
  "http://localhost:6080/service/xusers/groupusers"
```

### 10.4.2 查询用户和组

```bash
# 列出所有用户
curl -u admin:Admin1234! -s \
  "http://localhost:6080/service/xusers/users?pageSize=100" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
users=d.get('vXUsers',[])
print(f'用户数: {len(users)}')
for u in users[:20]:
    print(f\"  {u['name']:<20} {u.get('userRoleList',[''])[0]}\")
"

# 列出所有组
curl -u admin:Admin1234! -s \
  "http://localhost:6080/service/xusers/groups?pageSize=100" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
groups=d.get('vXGroups',[])
for g in groups:
    print(f\"  {g['name']}\")
"
```

## 10.5 审计日志

### 10.5.1 查看审计记录

```bash
# 查看最近的访问审计
curl -u admin:Admin1234! -s \
  "http://localhost:6080/service/assets/accessAudit?pageSize=20&sortBy=eventTime&sortType=desc" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
audits=d.get('vXAccessAudits',[])
print(f'审计记录: {len(audits)}')
for a in audits[:10]:
    status='ALLOW' if a.get('accessResult',0)==1 else 'DENY'
    print(f\"  [{status}] {a.get('requestUser',''):<15} {a.get('resourceType',''):<10} {a.get('resourcePath','')[:40]}\")
"

# 过滤拒绝的访问
curl -u admin:Admin1234! -s \
  "http://localhost:6080/service/assets/accessAudit?pageSize=50&accessResult=0" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('vXAccessAudits',[]):
    print(f\"DENIED: {a.get('requestUser')} -> {a.get('resourcePath')}\")
"
```

## 10.6 Ranger 与 Hive 集成测试

```bash
# 1. 确认 Ranger-Hive Plugin 已启用（查看 hive-site.xml）
docker exec bigtop_hostname1 grep -i ranger /etc/hive/conf/hive-site.xml | head -5

# 2. 测试权限控制（以 hive 用户无权限查询为例）
# 先在 Ranger 创建拒绝 alice 访问 sales 表的策略，然后：
docker exec bigtop_hostname1 bash -c "
  beeline -u 'jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000/default' \
    -n alice -p Alice123! \
    -e 'SELECT * FROM sales LIMIT 1;' 2>&1 | head -10
"

# 3. 验证审计日志中出现拒绝记录
curl -u admin:Admin1234! -s \
  "http://localhost:6080/service/assets/accessAudit?pageSize=5&accessResult=0&resourceType=HIVE"
```

---

# 第十一章 Tez 执行引擎操作指南

## 11.1 Tez 概述

Apache Tez 是 Hive 的默认执行引擎，相比 MapReduce 性能提升显著。Tez 将复杂查询表示为 DAG（有向无环图），减少中间数据落盘，提升执行效率。

### 11.1.1 访问 Tez UI

Tez UI 通过 YARN Timeline Server 提供：

```
YARN Timeline Server UI: http://localhost:8190
Tez UI（通过 YARN）:     http://localhost:8088/tez-ui
```

## 11.2 Tez 配置优化

### 11.2.1 关键配置参数

```sql
-- 在 Hive Beeline 中设置
-- 启用 Tez（已默认）
SET hive.execution.engine=tez;

-- Tez 容器内存（需与 YARN 配置匹配）
SET hive.tez.container.size=4096;   -- MB

-- Tez JVM 参数
SET hive.tez.java.opts=-server -Djava.net.preferIPv4Stack=true
  -XX:NewRatio=8 -XX:+UseNUMA -XX:+UseG1GC;

-- Tez 并发 Session
SET hive.server2.tez.sessions.per.default.queue=1;

-- 最大分区（动态分区）
SET tez.counters.max=10000;
```

### 11.2.2 查看 Tez DAG 执行情况

```bash
# 通过 YARN Timeline Server API 查询 Tez DAG
curl -s "http://localhost:8190/ws/v1/timeline/TEZ_DAG_ID" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
entities=d.get('entities',[])
print(f'DAG 数量: {len(entities)}')
for e in entities[:5]:
    info=e.get('otherinfo',{})
    print(f\"  {e['entityId']}: status={info.get('status','?')}\")
" 2>/dev/null || echo "Timeline Server 数据暂无"

# 查看 Hive 查询的 Tez 执行计划
# 在 Beeline 中执行：
# EXPLAIN SELECT * FROM employees GROUP BY dept;
```

---

# 第十二章 Flink 流处理操作指南

## 12.1 Flink 概述

Apache Flink 是有状态流处理框架，提供低延迟、高吞吐的流批一体计算能力。

### 12.1.1 Flink Standalone 集群（JobManager + TaskManager）

> 本环境同时部署了一套 **Standalone（独立进程）Flink 集群**，用于脱离 YARN 的轻量运行：
>
> | 组件 | 主机 | 端口 |
> |------|------|------|
> | FLINK_HISTORYSERVER | hostname0 | 8082 |
> | FLINK_JOBMANAGER | hostname0 | 6123 (RPC) / 8081 (Web UI) |
> | FLINK_TASKMANAGER | hostname1 | 动态 (连接 6123) |
>
> 该集群通过 Ambari 管理（服务 FLINK → FLINK_JOBMANAGER / FLINK_TASKMANAGER 组件）。
> 跨主机配置已写入 flink-conf（`jobmanager.rpc.address` / `rest.address` → hostname0，
> `bind-host` → 0.0.0.0）。

```bash
# 查看 Standalone 集群 TaskManager 注册情况
docker exec bigtop_hostname0 curl -s http://localhost:8081/overview

# 提交作业到 Standalone 集群（-m 指定 JobManager）
docker exec bigtop_hostname0 \
  /usr/bigtop/current/flink/bin/flink run -m bigtop-hostname0.bigtop.apache.org:8081 \
  /usr/lib/flink/examples/streaming/WordCount.jar

# 通过 Ambari 启停（可选，完整级联重启）
# 在 Ambari UI 选择 FLINK 服务 → JobManager/TaskManager Host 上的组件 → Start/Stop
```

### 12.1.2 Flink 在 YARN 上运行

本环境 Flink 亦支持以 YARN Application 模式运行：

```bash
docker exec -it bigtop_hostname0 bash

# 查看 Flink 版本
flink --version

# Flink YARN Session 模式（长驻集群）
yarn-session.sh \
  -n 2 \            # TaskManager 数量
  -jm 1024m \       # JobManager 内存
  -tm 2048m \       # TaskManager 内存
  --detached        # 后台运行

# 提交作业到 Session
flink run /usr/lib/flink/examples/streaming/WordCount.jar \
  --input hdfs:///data/input/ \
  --output hdfs:///output/flink-wordcount/

# YARN Per-Job 模式（每次提交独立集群）
flink run -m yarn-cluster \
  -yn 2 -yjm 1024m -ytm 2048m \
  /usr/lib/flink/examples/streaming/WordCount.jar

# YARN Application 模式（推荐，Flink 1.11+）
flink run-application -t yarn-application \
  -Djobmanager.memory.process.size=1g \
  -Dtaskmanager.memory.process.size=2g \
  /usr/lib/flink/examples/streaming/WordCount.jar
```

## 12.2 Flink SQL

```bash
# 启动 Flink SQL Client
sql-client.sh

# 或连接已有的 Flink Session
sql-client.sh -s yarnSessionId
```

```sql
-- Flink SQL 操作示例

-- 创建 Kafka Source 表
CREATE TABLE kafka_events (
  user_id   STRING,
  action    STRING,
  ts        TIMESTAMP(3),
  WATERMARK FOR ts AS ts - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'events',
  'properties.bootstrap.servers' = 'bigtop-hostname0.bigtop.apache.org:9092',
  'properties.group.id' = 'flink-sql-group',
  'scan.startup.mode' = 'latest-offset',
  'format' = 'json'
);

-- 创建 HDFS Sink 表
CREATE TABLE hdfs_output (
  window_start  TIMESTAMP(3),
  window_end    TIMESTAMP(3),
  action        STRING,
  event_count   BIGINT
) WITH (
  'connector' = 'filesystem',
  'path' = 'hdfs:///output/flink-agg/',
  'format' = 'json'
);

-- 流式聚合并写出
INSERT INTO hdfs_output
SELECT
  TUMBLE_START(ts, INTERVAL '1' MINUTE),
  TUMBLE_END(ts, INTERVAL '1' MINUTE),
  action,
  COUNT(*) AS event_count
FROM kafka_events
GROUP BY TUMBLE(ts, INTERVAL '1' MINUTE), action;
```

## 12.3 Flink 监控

```bash
# 查看 Flink YARN 作业
yarn application -list -appTypes APACHE_FLINK

# 通过 Flink REST API 查看（需要知道 JobManager 地址）
# 从 YARN UI 获取 JobManager URL：http://localhost:8088
# 找到 Flink 作业 → 点击 ApplicationMaster 链接

# 取消 Flink 作业
flink cancel <job-id>

# Flink 日志
yarn logs -applicationId application_xxx_yyy
```

---

# 第十三章 Zeppelin 数据分析操作指南

## 13.1 Zeppelin 概述

Apache Zeppelin 是交互式数据分析和可视化 Notebook，支持 Spark、Hive、Shell 等多种解释器。

### 13.1.1 访问地址

```
Zeppelin Web UI: http://localhost:9995
```

## 13.2 创建 Notebook

### 13.2.1 基本操作

1. 访问 `http://localhost:9995`
2. 点击 "Create new note"，输入 Notebook 名称
3. 选择默认解释器（推荐 `spark`）
4. 在段落（paragraph）中输入代码，按 `Shift+Enter` 执行

### 13.2.2 常用解释器

| 解释器 | 前缀 | 说明 |
|--------|------|------|
| Spark (Scala) | `%spark` | Spark Scala 交互式 |
| PySpark | `%pyspark` | Python Spark |
| SparkSQL | `%sql` 或 `%spark.sql` | Spark SQL |
| Shell | `%sh` | Shell 命令 |
| Hive | `%hive` | HiveQL（需配置） |
| Markdown | `%md` | Markdown 文档 |

### 13.2.3 示例 Notebook

**Spark SQL 数据分析**：

```sql
%spark.sql
-- 查询 Hive 表
SELECT dept, COUNT(*) as headcount, AVG(salary) as avg_salary
FROM default.employees
GROUP BY dept
ORDER BY avg_salary DESC
```

**PySpark 数据处理**：

```python
%pyspark
# 读取 HDFS 数据
df = spark.read.csv("hdfs:///data/input/", header=True, inferSchema=True)
df.show(5)

# 统计分析
from pyspark.sql.functions import col, count, avg
result = df.groupBy("dept").agg(
    count("*").alias("headcount"),
    avg("salary").alias("avg_salary")
).orderBy("avg_salary", ascending=False)
result.show()
```

**Shell 命令**：

```bash
%sh
hdfs dfs -ls /data/input/
hdfs dfs -du -h /warehouse/tablespace/
```

## 13.3 Zeppelin 配置

```bash
# Zeppelin 配置文件
docker exec bigtop_hostname0 ls /etc/zeppelin/conf/

# 查看 Spark 解释器配置
# 通过 UI：右上角 → Interpreter → spark → 编辑
# 关键配置：
# master: yarn
# spark.executor.memory: 2g
# spark.driver.memory: 1g
```


---

# 第十四章 集群运维操作指南

## 14.1 日常运维流程

### 14.1.1 每日检查清单

```bash
#!/bin/bash
# 每日巡检脚本 - 保存为 daily-check.sh

echo "====== HodoopForge 集群每日巡检报告 ======"
echo "时间: $(date)"
echo ""

# 1. Ambari Agent 心跳状态
echo "【1】Ambari Agent 心跳状态"
curl -s -u admin:admin \
  "http://localhost:20609/api/v1/clusters/qixuandata/hosts?fields=Hosts/host_name,Hosts/host_status,Hosts/last_heartbeat_time" \
  | python3 -c "
import json,sys,time
d=json.load(sys.stdin)
for h in d['items']:
    hi=h['Hosts']
    ts=hi.get('last_heartbeat_time',0)
    ago=int(time.time()*1000-ts)//1000
    status='✓' if hi['host_status']=='HEALTHY' else '✗'
    print(f'  {status} {hi[\"host_name\"]:<45} {hi[\"host_status\"]:<12} 心跳{ago}s前')
"

echo ""
echo "【2】服务运行状态"
curl -s -u admin:admin \
  "http://localhost:20609/api/v1/clusters/qixuandata/services?fields=ServiceInfo/service_name,ServiceInfo/state" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in sorted(d['items'], key=lambda x: x['ServiceInfo']['service_name']):
    si=s['ServiceInfo']
    status='✓' if si['state']=='STARTED' else '✗'
    print(f'  {status} {si[\"service_name\"]:<25} {si[\"state\"]}')
"

echo ""
echo "【3】HDFS 磁盘使用"
docker exec bigtop_hostname0 bash -c "
  hdfs dfsadmin -report 2>/dev/null | grep -E 'Configured|Present|Remaining|Used%' | head -5
"

echo ""
echo "【4】YARN 资源使用"
curl -s "http://localhost:8088/ws/v1/cluster/metrics" \
  | python3 -c "
import json,sys
m=json.load(sys.stdin)['clusterMetrics']
total_mem=m.get('totalMB',0)
alloc_mem=m.get('allocatedMB',0)
pct=alloc_mem*100//total_mem if total_mem>0 else 0
print(f'  内存使用: {alloc_mem/1024:.1f}GB / {total_mem/1024:.1f}GB ({pct}%)')
print(f'  活跃应用: {m.get(\"activeApps\",0)}  待处理: {m.get(\"pendingApps\",0)}')
"

echo ""
echo "【5】告警状态"
curl -s -u admin:admin \
  "http://localhost:20609/api/v1/clusters/qixuandata/alerts?fields=Alert/state&summary" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d.get('items',[])
critical=sum(1 for a in items if a['Alert']['state']=='CRITICAL')
warning=sum(1 for a in items if a['Alert']['state']=='WARNING')
print(f'  CRITICAL: {critical}  WARNING: {warning}  总计: {len(items)}')
" 2>/dev/null

echo ""
echo "【6】ZooKeeper 状态"
for port in 2181 12181 22181; do
  RESULT=$(echo ruok | nc localhost $port 2>/dev/null)
  HOST="h0(2181)" && [ "$port" = "12181" ] && HOST="h1(12181)" || true
  HOST="h2(22181)" && [ "$port" = "22181" ] && HOST="h2(22181)" || true
  STATUS=$([ "$RESULT" = "imok" ] && echo "✓ OK" || echo "✗ DOWN")
  echo "  ${STATUS} ZooKeeper port=${port}"
done

echo ""
echo "====== 巡检完成 ======"
```

### 14.1.2 集群启动流程（重启后恢复）

> **⚠️ 先判定"重启"还是"重建"**：本流程只适用于**重启（restart）**场景——软件层（Ambari/Hadoop/MySQL）仍在，只是 IP/软链接/包映射被还原。若容器被**重建（recreate）**（如操作过 `docker network rm` 后 `docker compose up -d`），可写层已清空，Ambari 根本不存在，本脚本会在 Step 2 因栈目录缺失报错，**必须走全量重装**（见 15.2.4）。
>
> ```bash
> cd ambari3
> docker compose exec bigtop_hostname0 bash -c \
>   'test -d /usr/lib/ambari-server && echo KEEP=重启 || echo WIPED=重建'
> docker compose ps          # 重建时 Created 时间会被更新为最近一次 up -d 的时刻
> ```
> 输出 `WIPED=重建` 请转到重建恢复章节（见 15.2.4），勿执行下方脚本。

```bash
#!/bin/bash
# restart-cluster.sh - 容器重启后恢复集群

set -e
cd /home/rkam/hadoop-ops-course/ambari3

echo "Step 1: 启动容器..."
# 注意：配置/网络未变化时更推荐 docker compose restart（保层）；
#       任意 up -d 在配置不一致时会触发 Recreate（丢层）
docker compose restart
sleep 10

echo "Step 2: 修复 hosts/软链接/包名..."
cd scripts
./setup-hostname.sh
cd ..

echo "Step 3: 启动 Ambari Server..."
docker exec bigtop_hostname0 ambari-server start
sleep 30

echo "Step 4: 启动所有节点 Agent..."
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  docker exec $h ambari-agent start || true
  echo "  $h: Agent 已启动"
done
sleep 15

echo "Step 5: 刷新 NAT 规则..."
sudo -n bash scripts/setup-nat-forward.sh refresh

echo "Step 6: 检查节点状态..."
curl -s -u admin:admin \
  "http://localhost:20609/api/v1/clusters/qixuandata/hosts?fields=Hosts/host_status" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for h in d['items']:
    hi=h['Hosts']
    print(f\"  {hi['host_name']}: {hi['host_status']}\")
"

echo ""
echo "请在 Ambari UI 启动所有服务: http://localhost:20609"
echo "Actions → Start All"
```

### 14.1.3 集群停止流程

```bash
#!/bin/bash
# stop-cluster.sh - 优雅停止集群

cd /home/rkam/hadoop-ops-course/ambari3

echo "Step 1: 通过 Ambari API 停止所有服务..."
CLUSTER="qixuandata"
curl -s -u admin:admin -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Stop All Services"},
       "Body":{"ServiceInfo":{"state":"INSTALLED"}}}' \
  "http://localhost:20609/api/v1/clusters/${CLUSTER}/services" > /dev/null
echo "  停止请求已提交，等待60秒..."
sleep 60

echo "Step 2: 停止 Ambari Server..."
docker exec bigtop_hostname0 ambari-server stop

echo "Step 3: 停止容器..."
docker compose stop
echo "集群已安全停止"
```

## 14.2 存储管理

### 14.2.1 HDFS 空间管理

```bash
# 查看 HDFS 使用概况
docker exec bigtop_hostname0 hdfs dfs -df -h /

# 查找大目录（TOP10）
docker exec bigtop_hostname0 bash -c "
  hdfs dfs -du -s -h /warehouse/* /data/* /spark-history 2>/dev/null | sort -rh | head -10
"

# 清理 Hive 临时数据
docker exec bigtop_hostname0 bash -c "
  hdfs dfs -rm -r /tmp/hive/* 2>/dev/null || true
  hdfs dfs -expunge
"

# 清理 MapReduce 历史日志（保留7天内）
docker exec bigtop_hostname0 bash -c "
  # 找出7天前的日志目录并删除
  hdfs dfs -ls /app-logs/ 2>/dev/null | grep '^d' | awk '{print \$8}' | while read dir; do
    # 实际应检查时间戳，这里仅示例
    echo \"  检查: \$dir\"
  done
"

# 清理 Spark 事件日志（只保留最近100个）
docker exec bigtop_hostname0 bash -c "
  hdfs dfs -ls /spark-history/ 2>/dev/null | sort -k8 | head -n -100 | \
    awk '{print \$8}' | while read f; do
      hdfs dfs -rm -r \$f 2>/dev/null || true
    done
"
```

### 14.2.2 MySQL 备份（Hive/Ranger 元数据）

```bash
# 备份 Hive 元数据库
docker exec bigtop_hostname1 bash -c "
  mysqldump -uroot -pambarirootpass \
    --databases hive ranger ambari \
    > /tmp/metadata_backup_$(date +%Y%m%d).sql
  echo '备份完成'
"

# 将备份复制到宿主机
docker cp bigtop_hostname1:/tmp/metadata_backup_$(date +%Y%m%d).sql /backup/

# 恢复备份（谨慎操作）
# docker exec -i bigtop_hostname1 mysql -uroot -pambarirootpass < /backup/metadata_backup.sql
```

## 14.3 日志管理

### 14.3.1 日志收集

```bash
#!/bin/bash
# collect-logs.sh - 收集所有组件日志

OUTPUT_DIR="/tmp/cluster-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p ${OUTPUT_DIR}

HOSTS="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"
LOG_DIRS=(
  "/var/log/ambari-server"
  "/var/log/ambari-agent"
  "/var/log/hadoop-hdfs"
  "/var/log/hadoop-yarn"
  "/var/log/hive"
  "/var/log/hbase"
  "/var/log/kafka"
  "/var/log/zookeeper"
  "/var/log/ranger-admin"
)

for HOST in ${HOSTS}; do
  echo "收集 ${HOST} 日志..."
  mkdir -p ${OUTPUT_DIR}/${HOST}
  for LOG_DIR in "${LOG_DIRS[@]}"; do
    docker exec ${HOST} bash -c "
      if [ -d ${LOG_DIR} ]; then
        ls ${LOG_DIR}/*.log 2>/dev/null | while read f; do
          tail -1000 \$f > /tmp/log_temp.txt 2>/dev/null
          echo \$f
        done
      fi
    " 2>/dev/null | while read LOG_FILE; do
      BASENAME=$(basename ${LOG_FILE})
      docker cp ${HOST}:/tmp/log_temp.txt \
        ${OUTPUT_DIR}/${HOST}/${BASENAME} 2>/dev/null || true
    done
  done
done

# 压缩
tar -czf ${OUTPUT_DIR}.tar.gz -C /tmp $(basename ${OUTPUT_DIR})
echo "日志已收集到: ${OUTPUT_DIR}.tar.gz"
```

### 14.3.2 日志分析

```bash
# 查找所有节点的错误日志
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  echo "=== ${h} ERRORS ==="
  docker exec ${h} bash -c "
    find /var/log -name '*.log' 2>/dev/null | while read f; do
      COUNT=\$(grep -c 'ERROR\|Exception' \$f 2>/dev/null || echo 0)
      [ \"\$COUNT\" -gt 0 ] && echo \"  \$f: \$COUNT errors\"
    done
  "
done

# 统计特定时间段的错误
docker exec bigtop_hostname0 bash -c "
  grep '2026-09-04' /var/log/ambari-server/ambari-server.log | \
    grep -i error | wc -l
"
```

## 14.4 用户管理

### 14.4.1 添加 Linux 用户（各节点同步）

```bash
#!/bin/bash
# add-user.sh <username> <groups>
USERNAME=${1:-newuser}
GROUPS=${2:-hadoop}

for HOST in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  echo "在 ${HOST} 添加用户 ${USERNAME}..."
  docker exec ${HOST} bash -c "
    useradd -m -G ${GROUPS} ${USERNAME} 2>/dev/null && \
      echo '  用户已创建' || echo '  用户已存在'
  "
done

# 创建 HDFS 用户目录
docker exec bigtop_hostname0 bash -c "
  hdfs dfs -mkdir -p /user/${USERNAME}
  hdfs dfs -chown ${USERNAME}:hadoop /user/${USERNAME}
  hdfs dfs -chmod 700 /user/${USERNAME}
"
echo "用户 ${USERNAME} 已创建完成"
```


---

# 第十五章 故障排查手册

## 15.1 故障排查总体思路

```
1. 确认现象：服务不可用？性能下降？数据异常？
2. 查看 Ambari 告警：第一时间了解告警信息
3. 查看服务状态：通过 Ambari UI 或 API 确认受影响服务
4. 查看日志：从最新日志中找 ERROR/Exception
5. 检查资源：磁盘、内存、CPU、网络
6. 隔离问题：缩小排查范围到特定节点/组件
7. 修复：根据根因修复，而非重启服务
8. 验证：修复后验证功能恢复，检查日志无新错误
```

## 15.2 Ambari 相关故障

### 15.2.1 Agent UNHEALTHY

**现象**：Ambari UI 中某节点显示 UNHEALTHY，无法下发任务

**排查步骤**：

```bash
# 1. 检查 Agent 进程
docker exec bigtop_hostname0 ambari-agent status

# 2. 检查 Agent 日志
docker exec bigtop_hostname0 tail -50 /var/log/ambari-agent/ambari-agent.log | \
  grep -E 'ERROR|WARN|Unhealthy'

# 3. 检查 chronyd（时间同步）
docker exec bigtop_hostname0 systemctl status chronyd

# 4. 如 chronyd 未运行，启动它
docker exec bigtop_hostname0 bash -c "
  printf '[Unit]\nDescription=Dummy NTP\n[Service]\nExecStart=/bin/true\nRemainAfterExit=yes\nType=oneshot\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/chronyd.service
  systemctl daemon-reload && systemctl start chronyd
"

# 5. 重启 Agent
docker exec bigtop_hostname0 ambari-agent restart
```

### 15.2.2 容器重启后服务无法启动

> **前提校验**：仅适用"重启态"。先确认可写层在（`docker compose exec bigtop_hostname0 ls /usr/lib/ambari-server` 有输出）；若目录不存在（重建态），本流程会失败，改用 15.2.4。凡最终根因表明容器被重建，不要再依赖 `setup-hostname.sh`/`post-deploy-fixes.sh` 反复重试，直接全量重装。

```bash
# 必须按顺序执行以下步骤
cd /home/rkam/hadoop-ops-course/ambari3

# Step 1: 修复 hosts 和软链接（最重要）
cd scripts && ./setup-hostname.sh

# Step 2: 启动 Ambari Server
docker exec bigtop_hostname0 ambari-server start

# Step 3: 等待所有 Agent 注册
sleep 30

# Step 4: 刷新 NAT
sudo -n bash setup-nat-forward.sh refresh

# Step 5: 通过 Ambari UI 启动所有服务
echo "请访问 http://localhost:20609 → Actions → Start All"
```

### 15.2.4 容器被"重建"导致集群全量丢失（灾害恢复）

**现象**：执行 `docker network rm ambari3_default`（清理与 compose 网段重叠的残留网络）后再 `docker compose up -d`，4 节点全部被 Recreate，`Created` 时间刷新，Ambari/Hadoop/MySQL 全部消失；`setup-hostname.sh`、`post-deploy-fixes.sh` 报"栈目录/包不存在"。

**根因**：`docker network rm` 把容器从网络剥离 → `docker compose up -d` 发现容器与 compose 定义不一致，执行 **Recreate（先删后建）**。bind mount 卷（RPM 仓库、hosts）保留，但**容器内已装软件全部丢失，无法通过重启恢复**。

**恢复 = 全量重装**（一次成功，勿在缺软件状态下反复跑"修复脚本"）：

```bash
cd /home/rkam/hadoop-ops-course/ambari3

# ① 启动容器（确认冲突网络已清理，避免再次重建循环）
docker compose up -d

# ② 五步自动安装（约 30~60 分钟，以 dnf 缓存热时为参考）
cd scripts
./setup.sh                  # 节点初始化（SSH/SELinux/hosts/dnf update）
./setup-ambari-repo.sh      # 本地 nginx yum 仓库 + 栈注入包
cd ..
./scripts/install-ambari-server.sh   # Ambari Server + MySQL（自动注入 repo_version）
./scripts/install-ambari-agent.sh    # 4 节点 Agent 注册

# ③ Web UI 创建集群（人工，见 USER-GUIDE §5）
#    4 FQDN + Stack=BIGTOP 3.5.0 + 仓库 Bigtop-3.5.0.0-1；组件分配见 §5.5

# ④ Deploy 失败就修（幂等，可反复）：
./scripts/post-deploy-fixes.sh   # 修完点 Retry，直到全部成功
# ⑤ 启动全部服务后执行 Hive 修复：
./scripts/fix-hive.sh
```

**规避**：冲突网络清理务必先 `docker compose down` 再 `docker network rm`；无把握时用 `docker compose restart`（保层）而非 `up -d`（可能重建）。

### 15.2.3 Deploy 安装失败

**按优先级排查**：

```bash
# 1. 运行一键修复脚本
cd /home/rkam/hadoop-ops-course/ambari3
./scripts/post-deploy-fixes.sh

# 2. 检查包名问题（容器重启后 Stack 包名恢复原始 ${stack_version}）
docker exec bigtop_hostname0 bash -c "
  grep 'stack_version' /var/lib/ambari-server/resources/stacks/BIGTOP/3.2.0/services/HDFS/metainfo.xml | head -3
"
# 若出现 ${stack_version}，重新执行
docker compose cp scripts/fix-package-names.sh bigtop_hostname0:/root/fix-package-names.sh
docker exec bigtop_hostname0 bash /root/fix-package-names.sh

# 3. 重启 ambari-server 重载栈定义（必须做——AmbariMetaInfo 只在启动时读盘，
# 不改内存 Server 生成的命令 package_list 仍是占位符，Retry 照旧失败）
docker exec bigtop_hostname0 ambari-server restart

# 4. 清理 Agent 栈缓存并重启 agent（必须做，否则旧缓存里的 ${stack_version} 仍生效）
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  docker exec $h bash -c \
    'rm -rf /var/lib/ambari-agent/cache/stacks/BIGTOP/3.2.0 /var/lib/ambari-agent/cache/stacks/BIGTOP/3.3.0
     find /var/lib/ambari-agent/cache/stacks/BIGTOP -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
     ambari-agent restart'
done

# 5. 仓库新增包后清理各节点 dnf 缓存（重要：否则新收录的 rpm 看不到）
#    例如 ambari-infra-solr(-client) 首次收录时，节点会一直报
#    "Unable to find a match"——元数据已过期，并非包真的缺失
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  docker exec $h bash -c 'rm -rf /var/cache/dnf/ambari-* /var/cache/dnf/BIGTOP-*; dnf clean all'
done

# 5.5 检查 JDK 是否安装
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  echo -n "$h: "
  docker exec $h ls /usr/lib/jvm/java-1.8.0-openjdk/bin/java 2>/dev/null && echo "JDK8 OK" || echo "JDK8 MISSING"
done

# 6. 检查软链接是否完整
docker exec bigtop_hostname1 ls /usr/bigtop/current/hive-client/lib/ 2>/dev/null | wc -l
# 应该 > 0，若为空则软链接丢失

# 7. 校验 INFRA_SOLR(_CLIENT) 与 ROUTER
#    solrCloudCli.sh 由真实 ambari-infra-solr-client rpm 提供，缺失说明包未装成功
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  echo -n "$h: "
  docker exec $h ls /usr/lib/ambari-infra-solr-client/solrCloudCli.sh >/dev/null 2>&1 && echo "solrCloudCli OK" || echo "solrCloudCli MISSING"
done
#    ROUTER 安装失败：agent 节点 distro-select 缺 dfsrouter 映射时补打补丁
#    （post-deploy-fixes.sh Fix 3f 已自动执行；手动示例）：
#    docker exec bigtop_hostname3 bash -c '
#      sed -i "s/\"hadoop-hdfs-namenode\": \"hadoop-hdfs\",/\"hadoop-hdfs-namenode\": \"hadoop-hdfs\",\n           \"hadoop-hdfs-dfsrouter\": \"hadoop-hdfs\",/" /usr/lib/bigtop-select/distro-select'
```

## 15.3 HDFS 故障排查

### 15.3.1 NameNode 进入安全模式

```bash
# 查看安全模式状态
docker exec bigtop_hostname0 hdfs dfsadmin -safemode get

# 查看进入安全模式原因
docker exec bigtop_hostname0 tail -50 /var/log/hadoop-hdfs/hadoop-hdfs-namenode-*.log | \
  grep -i "safe mode"

# 退出安全模式（确认数据完整后）
docker exec bigtop_hostname0 hdfs dfsadmin -safemode leave

# 如果自动进入，可能是 DataNode 未全部启动
# 等待 DataNode 全部注册后会自动退出，或手动退出
```

### 15.3.2 磁盘空间不足

```bash
# 快速定位大文件/目录
docker exec bigtop_hostname0 bash -c "
  hdfs dfs -du -s -h /* 2>/dev/null | sort -rh | head -10
"

# 清理常见垃圾数据
docker exec bigtop_hostname0 bash -c "
  # 清理回收站
  hdfs dfs -expunge

  # 清理 YARN 应用日志（超过7天）
  CUTOFF=\$(date -d '7 days ago' +%Y-%m-%d)
  echo '超过7天的日志目录（待手动确认删除）:'
  hdfs dfs -ls /app-logs/ 2>/dev/null | grep \"^\$(date -d '7 days ago' +'%Y-%m')\" | awk '{print \$8}' | head -10

  # 清理 Spark 历史事件日志（超过30天，谨慎操作）
  hdfs dfs -ls /spark-history/ 2>/dev/null | wc -l
"
```

### 15.3.3 块损坏（Corrupt blocks）

```bash
# 检查损坏块
docker exec bigtop_hostname0 hdfs fsck / 2>/dev/null | grep -E "CORRUPT|Status"

# 查找损坏的文件
docker exec bigtop_hostname0 hdfs fsck / 2>/dev/null | \
  grep "CORRUPT" | awk '{print $1}'

# 删除损坏文件（数据已不可恢复，谨慎操作）
docker exec bigtop_hostname0 hdfs fsck / -delete 2>/dev/null

# 如果是副本不足（未完全损坏）
docker exec bigtop_hostname0 hdfs fsck / 2>/dev/null | \
  grep "Under replicated"
# 通常等待 DataNode 恢复后自动修复
```

## 15.4 YARN 故障排查

### 15.4.1 应用一直 PENDING

```bash
# 查看等待中的应用
yarn application -list -appStates ACCEPTED

# 查看集群资源
curl -s "http://localhost:8088/ws/v1/cluster/metrics" | python3 -c "
import json,sys
m=json.load(sys.stdin)['clusterMetrics']
print(f'可用内存: {m.get(\"availableMB\",0)/1024:.1f}GB')
print(f'待处理应用: {m.get(\"pendingApps\",0)}')
print(f'待处理容器: {m.get(\"pendingContainers\",0)}')
"

# 查看 NodeManager 状态
yarn node -list | grep -i "lost\|unhealthy"

# 如果 NodeManager 离线，检查其日志
docker exec bigtop_hostname3 tail -50 /var/log/hadoop-yarn/yarn-yarn-nodemanager-*.log | \
  grep -E "ERROR|Exception"
```

### 15.4.2 应用频繁 FAILED

```bash
# 查看失败原因
APP_ID="application_xxx_yyy"
yarn logs -applicationId ${APP_ID} 2>/dev/null | grep -E "ERROR|Exception|FAILED" | tail -20

# 查看容器退出码
curl -s "http://localhost:8088/ws/v1/cluster/apps/${APP_ID}/appattempts" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('appAttempts',{}).get('appAttempt',[]):
    print(f\"Attempt: {a['id']}  State: {a['appAttemptState']}  Container: {a.get('amContainerId','')}\")
"
```

## 15.5 Hive 故障排查

### 15.5.1 HiveServer2 启动失败

**常见原因及修复**：

```bash
# 1. 查看 HiveServer2 日志
docker exec bigtop_hostname1 tail -100 /var/log/hive/hiveserver2.log | \
  grep -E "ERROR|Exception|FATAL" | tail -20

# 2. 检查 Metastore 是否运行
docker exec bigtop_hostname1 ss -tlnp | grep 9083 || echo "Metastore NOT running"

# 3. 如果是 HadoopMetrics2Reporter 错误（NoSuchMethodError）——**必须改 hivemetastore-site，
#    不是 hive-site**（metastore 配置优先级：hivemetastore-site.xml 覆盖 hive-site.xml，
#    只改 hive-site 不生效）。且要同时去掉 reporter=HADOOP2（它才是触发构造该类的开关）：
curl -s -u admin:admin \
  "http://localhost:20609/api/v1/clusters/qixuandata/configurations?type=hivemetastore-site" | \
  python3 -c "
import json,sys
d=json.load(sys.stdin)
props=d['items'][-1]['properties'] if d['items'] else {}
print('metrics.enabled:', props.get('hive.metastore.metrics.enabled', 'NOT SET'))
print('metrics.reporter:', props.get('hive.service.metrics.reporter', 'NOT SET'))
"
# 修复（改配置后对 HIVE 逐次 STOP→START）：
#   hive.metastore.metrics.enabled = false
#   hive.service.metrics.reporter  = JMX
# 用仓库脚本一次性部署（自动继承当前 hivemetastore-site 的全部属性）：
#   docker compose cp ambari3/scripts/ambari-cfg.py bigtop_hostname0:/tmp/
#   docker exec bigtop_hostname0 bash -c \
#     'python3 /tmp/ambari-cfg.py hivemetastore-site auto \
#        hive.metastore.metrics.enabled=false hive.service.metrics.reporter=JMX'
# 根因：Hive 4.0.1 的 metastore Metrics 调用重打阴影包 org.apache.hive.com.codahale，
#       而 dropwizard-metrics-hadoop-metrics2-reporter jar 仍是原生 com.codahale 签名，
#       HADOOP2 reporter 一构造就 NoSuchMethodError，metastore 崩溃、9083 从未监听，
#       HS2 连锁报 ZooKeeper node /hiveserver2 is not ready。

# 4. 如果 hive.heapsize 过大导致 OOM（CommitMemoryError: Cannot allocate memory）
curl -s -u admin:admin \
  "http://localhost:20609/api/v1/clusters/qixuandata/configurations?type=hive-env" | \
  python3 -c "
import json,sys
d=json.load(sys.stdin)
props=d['items'][-1]['properties'] if d['items'] else {}
print('hive.heapsize:', props.get('hive.heapsize', 'NOT SET'))  # 应 <= 1024
print('hive.metastore.heapsize:', props.get('hive.metastore.heapsize', 'NOT SET'))
"
# 根因与前提：4 容器默认 mem_limit 曾为 8g（spark 服务独占堆外内存），
# hive.heapsize=6371 时 HS2 直接 OOM。已把 docker-compose mem_limit 改为
# 16g/12g/12g/12g，并把两个 heapsize 降到 1024（对照 §1.2.4 重启服务）。
# 若只是线上临时调内存，可用 docker update --memory 动态修改（不重建、不丢层）。
```

### 15.5.2 Hive 查询执行缓慢

```bash
# 检查查询是否使用了全表扫描
# 在 Beeline 中执行：
# EXPLAIN SELECT ...;
# 关注是否有 TableScan 而非 PartitionFilter

# 检查统计信息是否过期
docker exec bigtop_hostname1 bash -c "
  beeline -u 'jdbc:hive2://localhost:10000/default' -n hive -e '
    ANALYZE TABLE employees COMPUTE STATISTICS;
    ANALYZE TABLE employees COMPUTE STATISTICS FOR COLUMNS;
  ' 2>/dev/null
"

# 检查 Tez 是否正常
docker exec bigtop_hostname1 bash -c "
  beeline -u 'jdbc:hive2://localhost:10000/default' -n hive -e '
    SET hive.execution.engine;
  ' 2>/dev/null | grep -v '^$'
"
```

## 15.6 HBase 故障排查

### 15.6.1 RegionServer 崩溃

```bash
# 查看 RegionServer 日志
docker exec bigtop_hostname3 tail -100 /var/log/hbase/hbase-hbase-regionserver-*.log | \
  grep -E "ABORT|ERROR|Exception" | tail -20

# 检查 ZooKeeper 中 RegionServer 注册状态
docker exec bigtop_hostname0 bash -c "
  echo 'ls /hbase/rs' | /usr/lib/zookeeper/bin/zkCli.sh \
    -server bigtop-hostname0.bigtop.apache.org:2181 2>/dev/null | \
    grep 'bigtop-hostname'
"

# 检查 Region 分配是否正常（通过 Master UI）
curl -s "http://localhost:16010/master-status" | grep -i "region" | head -5
```

### 15.6.2 HBase 读写性能下降

```bash
# 查看 RegionServer 指标
curl -s "http://localhost:16030/jmx" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for b in d.get('beans',[]):
    name=b.get('name','')
    if 'RegionServer' in name and 'Runtime' not in name:
        read_lat=b.get('Get_mean',b.get('readRequestCount','N/A'))
        write_lat=b.get('Put_mean',b.get('writeRequestCount','N/A'))
        if read_lat != 'N/A' or write_lat != 'N/A':
            print(f'Read count: {read_lat}  Write count: {write_lat}')
            break
" 2>/dev/null || echo "RegionServer JMX 暂不可达"

# 手动触发 Major Compaction（清理过期数据）
echo "major_compact 'users'" | hbase shell 2>/dev/null
```

## 15.7 Kafka 故障排查

### 15.7.1 Kafka Broker 不可用

```bash
# 检查 Broker 状态
echo ruok | nc bigtop-hostname0.bigtop.apache.org 9092 2>/dev/null || \
  echo "Broker 无响应"

# 查看 Kafka 日志
docker exec bigtop_hostname0 tail -100 /var/log/kafka/server.log | \
  grep -E "ERROR|Exception|WARN" | tail -20

# 检查 Kafka 在 ZooKeeper 中的注册
docker exec bigtop_hostname0 bash -c "
  echo 'ls /kafka-broker/ids' | /usr/lib/zookeeper/bin/zkCli.sh \
    -server bigtop-hostname0.bigtop.apache.org:2181 2>/dev/null | \
    grep '\[' | tail -1
"

# 重启 Kafka（通过 Ambari UI 或 API）
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Restart Kafka"},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/services/KAFKA" > /dev/null
sleep 10
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Start Kafka"},"Body":{"ServiceInfo":{"state":"STARTED"}}}' \
  "http://localhost:20609/api/v1/clusters/qixuandata/services/KAFKA" > /dev/null
```

### 15.7.2 消费者积压（Lag 过大）

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# 查看所有消费组积压
kafka-consumer-groups.sh \
  --describe \
  --bootstrap-server ${BOOTSTRAP} \
  --all-groups 2>/dev/null | \
  awk 'NR==1 || $6>1000' | column -t

# 如果积压是因为消费者速度慢，考虑：
# 1. 增加消费者并发（增加分区数）
# 2. 优化消费者处理逻辑
# 3. 临时跳过积压（重置 offset 到最新）
kafka-consumer-groups.sh \
  --bootstrap-server ${BOOTSTRAP} \
  --group slow-group \
  --topic events \
  --reset-offsets --to-latest \
  --execute
```

---

# 第十六章 性能调优指南

## 16.1 HDFS 性能调优

### 16.1.1 NameNode 堆内存

每百万个文件/块约需 1GB NameNode 内存：

```bash
# 在 Ambari UI 调整：
# Services → HDFS → Configs → Advanced → NameNode Java heap size
# 推荐：生产环境最少 8GB

# 查看当前 NameNode 对象数量
curl -s "http://localhost:50070/jmx?qry=Hadoop:service=NameNode,name=FSNamesystemState" | \
  python3 -c "
import json,sys
d=json.load(sys.stdin)
for b in d.get('beans',[]):
    print(f'文件数: {b.get(\"FilesTotal\",0)}')
    print(f'块数: {b.get(\"BlocksTotal\",0)}')
    print(f'Live DN: {b.get(\"NumLiveDataNodes\",0)}')
"
```

### 16.1.2 DataNode 块大小和副本

```bash
# 查看当前块大小配置
docker exec bigtop_hostname0 hdfs getconf -confKey dfs.blocksize

# 创建特定块大小的文件
hdfs dfs -D dfs.blocksize=268435456 -put /tmp/bigfile.dat /data/
# 即 256MB 块大小（适合大文件，减少 NameNode 元数据压力）

# 对特定路径设置副本数
hdfs dfs -setrep 2 /data/archive/   # 归档数据降副本
hdfs dfs -setrep 3 /data/hot/       # 热数据保持3副本
```

### 16.1.3 短路读取（Short-circuit Read）

短路读取允许客户端直接从 DataNode 本地磁盘读取，绕过网络：

```xml
<!-- 在 hdfs-site.xml 中配置（通过 Ambari 修改） -->
<property>
  <name>dfs.client.read.shortcircuit</name>
  <value>true</value>
</property>
<property>
  <name>dfs.domain.socket.path</name>
  <value>/var/lib/hadoop-hdfs/dn_socket</value>
</property>
```

## 16.2 YARN 性能调优

### 16.2.1 资源配置原则

```
NodeManager 内存 = 物理内存 × 0.8（留20%给系统）
容器最大内存 = NodeManager 内存
容器最小内存 = 512MB ~ 1GB
CPU vcores = 物理 CPU 核数（超线程算2倍）
```

### 16.2.2 队列配置优化

```bash
# 查看队列配置模板（通过 Ambari API 获取当前配置）
curl -s -u admin:admin \
  "http://localhost:20609/api/v1/clusters/qixuandata/configurations?type=capacity-scheduler" | \
  python3 -c "
import json,sys
d=json.load(sys.stdin)
if d['items']:
    props=d['items'][-1]['properties']
    for k,v in sorted(props.items()):
        print(f'{k}={v}')
" | head -30
```

## 16.3 Hive 性能调优

### 16.3.1 文件格式选择

| 格式 | 读性能 | 写性能 | 压缩支持 | 推荐场景 |
|------|--------|--------|---------|---------|
| TextFile | 低 | 高 | 行级 | 数据导入临时表 |
| ORC | 高 | 中 | 高 | 生产环境首选 |
| Parquet | 高 | 中 | 高 | Spark 集成较好 |
| Avro | 中 | 中 | 行级 | 流式数据 |
| SequenceFile | 中 | 高 | 行级 | MR 中间结果 |

```sql
-- 将 TextFile 表转换为 ORC（性能提升显著）
CREATE TABLE orders_orc
STORED AS ORC
AS SELECT * FROM orders_text;

-- ORC 配置推荐
CREATE TABLE orders (
  ...
)
STORED AS ORC
TBLPROPERTIES (
  "orc.compress"="ZLIB",           -- ZLIB压缩（平衡）/ SNAPPY（快）/ NONE（不压缩）
  "orc.stripe.size"="67108864",    -- Stripe 大小 64MB
  "orc.row.index.stride"="10000",  -- 行组大小
  "orc.bloom.filter.columns"="id,user_id",  -- 布隆过滤器列
  "orc.bloom.filter.fpp"="0.05"    -- 假阳性率
);
```

### 16.3.2 分区策略

```sql
-- 好的分区策略：低基数、查询常用过滤条件
-- 按时间分区（高基数的列不适合分区，如 user_id）
CREATE TABLE events (
  event_id BIGINT,
  user_id  INT,
  action   STRING,
  amount   DECIMAL(10,2)
)
PARTITIONED BY (
  event_date DATE,    -- 每天一个分区，约365个/年（合理）
  event_type STRING   -- 少量类型（如 click/buy/view）
)
STORED AS ORC;

-- 避免：按 user_id 分区（百万用户 = 百万分区，NameNode 压力极大）
```

## 16.4 Spark 性能调优

### 16.4.1 数据倾斜处理

```scala
// 检测数据倾斜：查看 Spark UI 中各 Task 的执行时间差异
// 最慢 Task 比平均时间长 5 倍以上，即为数据倾斜

// 方法1：倾斜 Key 加盐（Salting）
val salted = df.withColumn("salted_key",
  concat($"skewed_key", lit("_"), (rand() * 100).cast("int")))
val result = salted.groupBy("salted_key").agg(sum("amount"))
  .withColumn("orig_key", split($"salted_key", "_")(0))
  .groupBy("orig_key").agg(sum("sum(amount)"))

// 方法2：大表广播小表（避免 Shuffle Join）
import org.apache.spark.sql.functions.broadcast
val result = bigTable.join(broadcast(smallTable), "key")

// 方法3：调整 Shuffle 分区数
spark.conf.set("spark.sql.shuffle.partitions", "800")
// 分区数 ≈ 数据量(GB) × 10（经验值，单分区约 100-200MB）

// 方法4：AQE（自适应查询执行，Spark 3.0+）
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
```

---

# 第十七章 安全加固指南

## 17.1 网络安全

### 17.1.1 端口访问控制

本环境通过 iptables 管理访问控制，仅暴露必要端口：

```bash
# 查看当前 NAT 规则
sudo -n iptables -t nat -L PREROUTING --line-numbers | head -20

# 添加 INPUT 规则限制访问来源（以限制 Ambari UI 为例）
sudo -n iptables -I INPUT -p tcp --dport 20609 \
  -s 192.168.0.0/24 -j ACCEPT    # 只允许内网访问
sudo -n iptables -I INPUT -p tcp --dport 20609 -j DROP   # 拒绝其他

# 查看 INPUT 规则
sudo -n iptables -L INPUT --line-numbers
```

### 17.1.2 MySQL 安全加固

```bash
# 修改默认密码（生产环境必须）
docker exec bigtop_hostname1 mysql -uroot -pambarirootpass -e "
  ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewStrongPassword123!';
  ALTER USER 'ambari'@'%' IDENTIFIED BY 'NewAmbariPass123!';
  -- 删除匿名用户
  DELETE FROM mysql.user WHERE User='';
  FLUSH PRIVILEGES;
"

# 限制 MySQL 外网访问
docker exec bigtop_hostname1 bash -c "
  echo 'bind-address=127.0.0.1' >> /etc/my.cnf.d/mysql-server.cnf
  # 注意：若其他容器需连接，需改为 0.0.0.0 或指定内网IP
"
```

## 17.2 Ambari 安全配置

### 17.2.1 修改默认密码

```bash
# 修改 Ambari admin 密码（通过 API）
curl -u admin:admin -s -X PUT \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"Users":{"user_name":"admin","password":"NewAdminPass123!","old_password":"admin"}}' \
  "http://localhost:20609/api/v1/users/admin"
```

### 17.2.2 创建只读审计用户

```bash
# 创建只读用户（用于监控系统）
curl -u admin:admin -s -X POST \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '{"Users":{"user_name":"monitor","password":"Monitor123!","active":true,"admin":false}}' \
  "http://localhost:20609/api/v1/users"

# 授予集群只读权限
curl -u admin:admin -s -X POST \
  -H "X-Requested-By: ambari" \
  -H "Content-Type: application/json" \
  -d '[{"PrivilegeInfo":{"permission_name":"CLUSTER.USER","principal_name":"monitor","principal_type":"USER"}}]' \
  "http://localhost:20609/api/v1/clusters/qixuandata/privileges"
```

## 17.3 HDFS 安全配置

### 17.3.1 HDFS 权限最佳实践

```bash
# 各服务用户的推荐权限设置
docker exec bigtop_hostname0 bash -c "
  # HDFS 关键目录权限
  hdfs dfs -chmod 755 /
  hdfs dfs -chmod 1777 /tmp
  hdfs dfs -chmod 755 /user
  hdfs dfs -chown hdfs:hdfs /

  # 各服务目录
  hdfs dfs -chown hive:hadoop /warehouse/tablespace
  hdfs dfs -chmod 1775 /warehouse/tablespace/managed/hive
  hdfs dfs -chown hdfs:hdfs /app-logs
  hdfs dfs -chmod 1777 /app-logs

  echo '权限设置完成'
"
```

### 17.3.2 审计日志配置

```bash
# HDFS 审计日志已默认启用
# 查看审计日志
docker exec bigtop_hostname0 tail -20 /var/log/hadoop-hdfs/hdfs-audit.log

# 审计日志格式：
# date ip ugi(user) allowed CMD path ...
# 2026-09-04 10:00:00,000 allowed=true ugi=hive cmd=open src=/warehouse/...

# 过滤拒绝的访问
docker exec bigtop_hostname0 bash -c "
  grep 'allowed=false' /var/log/hadoop-hdfs/hdfs-audit.log | tail -10
"
```

## 17.4 Ranger 安全最佳实践

### 17.4.1 最小权限原则

```bash
# 创建分析师角色（只读，无写权限）
# 通过 Ranger UI 创建策略：
# - HDFS: /warehouse/tablespace/external/hive → group:analysts → read,execute
# - Hive: database=analytics, table=*, column=* → group:analysts → select
# - Kafka: topic=output-events → group:analysts → consume,describe

# 创建开发者角色（读写，但不能删除生产数据）
# - HDFS: /data/dev → group:developers → read,write,execute
# - Hive: database=dev → group:developers → all
# - Hive: database=prod → group:developers → select（只读）

# 禁止默认的 Hive 公开访问
# 在 Ranger UI 中禁用 "hadoop - hive" 的默认策略
```

---

# 附录A：常用命令速查表

## A.1 HDFS 命令速查

```bash
hdfs dfs -ls <path>              # 列目录
hdfs dfs -ls -R <path>           # 递归列目录
hdfs dfs -mkdir -p <path>        # 创建目录（含父目录）
hdfs dfs -put <local> <hdfs>     # 上传文件
hdfs dfs -get <hdfs> <local>     # 下载文件
hdfs dfs -cat <path>             # 查看文件内容
hdfs dfs -rm <path>              # 删除文件
hdfs dfs -rm -r <path>           # 递归删除
hdfs dfs -du -h <path>           # 查看大小
hdfs dfs -df -h                  # 查看磁盘使用
hdfs dfs -chmod <perm> <path>    # 修改权限
hdfs dfs -chown <owner> <path>   # 修改所有者
hdfs dfs -mv <src> <dst>         # 移动/重命名
hdfs dfs -cp <src> <dst>         # 复制
hdfs dfsadmin -report            # 集群状态报告
hdfs dfsadmin -safemode get      # 查看安全模式
hdfs dfsadmin -safemode leave    # 退出安全模式
hdfs fsck /                      # 健康检查
```

## A.2 YARN 命令速查

```bash
yarn application -list                          # 列出应用
yarn application -list -appStates RUNNING       # 运行中的应用
yarn application -status <appId>                # 应用状态
yarn application -kill <appId>                  # 终止应用
yarn logs -applicationId <appId>                # 查看日志
yarn node -list                                 # 节点列表
yarn queue -status default                      # 队列状态
yarn rmadmin -refreshQueues                     # 刷新队列配置
yarn jar <jar> <class> [args]                   # 提交作业
```

## A.3 Kafka 命令速查

```bash
BOOTSTRAP="bigtop-hostname0.bigtop.apache.org:9092"

# Topic 管理
kafka-topics.sh --list --bootstrap-server $BOOTSTRAP
kafka-topics.sh --create --bootstrap-server $BOOTSTRAP --topic T --partitions 3 --replication-factor 1
kafka-topics.sh --describe --bootstrap-server $BOOTSTRAP --topic T
kafka-topics.sh --delete --bootstrap-server $BOOTSTRAP --topic T

# 生产消费
kafka-console-producer.sh --bootstrap-server $BOOTSTRAP --topic T
kafka-console-consumer.sh --bootstrap-server $BOOTSTRAP --topic T --from-beginning

# 消费组
kafka-consumer-groups.sh --list --bootstrap-server $BOOTSTRAP
kafka-consumer-groups.sh --describe --bootstrap-server $BOOTSTRAP --group G
kafka-consumer-groups.sh --reset-offsets --bootstrap-server $BOOTSTRAP --group G --topic T --to-latest --execute
```

## A.4 HBase Shell 命令速查

```ruby
status                           # 集群状态
list                             # 列表
create 'T', 'CF'                 # 创建表
describe 'T'                     # 表描述
put 'T', 'KEY', 'CF:COL', 'VAL' # 写入
get 'T', 'KEY'                   # 读取
scan 'T', {LIMIT => 10}          # 扫描
scan 'T', {ROWPREFIXFILTER=>'K'} # 前缀扫描
delete 'T', 'KEY', 'CF:COL'      # 删除列
deleteall 'T', 'KEY'             # 删除行
count 'T'                        # 统计行数
disable 'T'                      # 禁用表
drop 'T'                         # 删除表
snapshot 'T', 'snap-name'        # 创建快照
```

## A.5 常用端口速查

| 服务 | 宿主机端口 | 目标节点 | 访问类型 |
|------|-----------|---------|---------|
| Ambari UI | 20609 | h0:8080 | Web UI |
| HDFS NameNode | 50070 | h0:50070 | Web UI |
| HDFS NameNode RPC | 8020 | h0:8020 | RPC |
| YARN RM | 8088 | h0:8088 | Web UI |
| ZooKeeper h0 | 2181 | h0:2181 | Client |
| ZooKeeper h1 | 12181 | h1:2181 | Client |
| ZooKeeper h2 | 22181 | h2:2181 | Client |
| HBase Master | 16010 | h0:16010 | Web UI |
| Kafka | 9092 | h0:9092 | Broker |
| Spark History | 18081 | h0:18081 | Web UI |
| HiveServer2 | 10000 | h1:10000 | JDBC |
| HiveServer2 UI | 10002 | h1:10002 | Web UI |
| Hive Metastore | 9083 | h1:9083 | Thrift |
| Ranger Admin | 6080 | h1:6080 | Web UI |
| MR History | 19888 | h1:19888 | Web UI |
| MySQL | 3306 | h1:3306 | SQL |
| HBase RegionServer | 16030 | h3:16030 | Web UI |
| DataNode | 50075 | h3:50075 | Web UI |
| NodeManager | 8042 | h3:8042 | Web UI |

## A.6 安全凭证速查

| 服务 | 用户名 | 密码 |
|------|--------|------|
| Ambari UI | admin | admin |
| MySQL root | root | ambarirootpass |
| MySQL ambari | ambari | ambari |
| MySQL hive | hive | hive |
| MySQL ranger | ranger | ranger |
| MySQL rangeradmin | rangeradmin | Admin1234! |
| Ranger Admin UI | admin | Admin1234! |

---

# 附录B：故障排查决策树

## B.1 服务无法启动

```
服务无法启动
├── Ambari UI 显示 UNHEALTHY
│   ├── Agent 进程未运行 → docker exec <host> ambari-agent start
│   ├── chronyd 未运行 → 参见第15章 15.2.1
│   └── 网络问题 → 检查 /etc/hosts 和容器连通性
├── 安装包找不到（Deploy 失败）
│   ├── ${stack_version} 问题 → 执行 fix-package-names.sh
│   ├── 软链接丢失 → 执行 setup-hostname.sh
│   └── JDK 未安装 → dnf install java-1.8.0-openjdk-devel
├── 内存不足（OOM）
│   ├── 检查 free -h
│   ├── 降低服务堆内存（通过 Ambari Configs）
│   └── 关闭不必要的服务
└── 日志中有 ERROR/Exception
    ├── Connection refused → 检查依赖服务是否运行
    ├── Permission denied → 检查文件权限和用户
    └── ClassNotFoundException → JAR 缺失或版本不兼容
```

## B.2 查询执行缓慢

```
查询执行缓慢
├── Hive/Spark 查询慢
│   ├── 全表扫描 → 添加分区过滤条件
│   ├── 数据倾斜 → 使用 Salting 或 Broadcast Join
│   ├── 统计信息过期 → ANALYZE TABLE ... COMPUTE STATISTICS
│   └── TextFile 格式 → 转换为 ORC
├── YARN 应用 PENDING
│   ├── 资源不足 → 检查队列容量配置
│   └── NodeManager 离线 → 检查节点状态
└── HDFS 读写慢
    ├── DataNode 磁盘满 → 清理数据，扩容
    ├── 网络带宽瓶颈 → 监控网络
    └── 副本策略问题 → 检查机架感知配置
```

---

*文档版本：V1.0 | 编写日期：2026年9月 | © HodoopForge Project*

