# 大数据集群部署指南

Ambari 3.1.0 + Bigtop 3.5.0 on Rocky Linux 8

---

## 前置确认

在开始 Web UI 操作前，确认所有服务正常：

```bash
# 确认 4 个 agent 都在运行
for i in 0 1 2 3; do
  echo -n "hostname${i}: "
  docker compose exec bigtop_hostname${i} ambari-agent status
done

# 确认 server 正常
docker compose exec bigtop_hostname0 ambari-server status

# 确认 repo 可访问
curl -s http://localhost:20609/api/v1/stacks | python3 -m json.tool | grep "stack_name"
```

---

## 第一阶段：Ambari Web UI 集群创建向导

### 1. 登录

浏览器打开 http://localhost:20609
- 用户名：`admin`
- 密码：`admin`

### 2. 创建集群

点击 "Launch Install Wizard"，输入集群名称，例如 `bigtop-cluster`

### 3. 选择 Stack

- 选择 **BIGTOP**
- 版本选 **3.5.0**
- 点击 "Use Local Repository"（使用本地仓库）
- 删除所有默认 URL，只保留 redhat8，填入：
  ```
  http://bigtop-hostname0.bigtop.apache.org
  ```
- OS 类型选 `redhat8`

### 4. 安装选项（Install Options）

**Target Hosts**（每行一个）：
```
bigtop-hostname0.bigtop.apache.org
bigtop-hostname1.bigtop.apache.org
bigtop-hostname2.bigtop.apache.org
bigtop-hostname3.bigtop.apache.org
```

**Host Registration Information**：
- 选择 "Perform manual registration on hosts and do not use SSH"
  （因为 agent 已经手动安装并运行）

点击 "Register and Confirm"，等待所有节点变为绿色 Registered 状态。

> 如果节点注册失败，检查：
> ```bash
> docker compose exec bigtop_hostname1 cat /etc/ambari-agent/conf/ambari-agent.ini | grep hostname
> # 应该显示 hostname=bigtop-hostname0.bigtop.apache.org
> docker compose exec bigtop_hostname1 ambari-agent status
> ```

### 5. 选择服务（Choose Services）

推荐最小化安装，先选核心服务：

| 服务 | 说明 | 建议 |
|------|------|------|
| HDFS | 分布式文件系统 | 必选 |
| YARN + MapReduce2 | 资源管理 + MR | 必选 |
| ZooKeeper | 协调服务 | 必选 |
| Ambari Metrics | 监控指标 | 建议选 |
| Hive | 数据仓库 | 按需 |
| HBase | NoSQL | 按需 |
| Spark | 计算引擎 | 按需 |
| Kafka | 消息队列 | 按需 |
| Ranger | 权限管理 | 按需 |
| Tez | DAG 执行引擎 | Hive 依赖 |

### 6. 分配 Master 组件（Assign Masters）

4 节点推荐分配：

| 组件 | 节点 |
|------|------|
| NameNode | bigtop-hostname0 |
| Secondary NameNode | bigtop-hostname1 |
| ResourceManager | bigtop-hostname0 |
| History Server | bigtop-hostname0 |
| ZooKeeper Server | hostname0, hostname1, hostname2 |
| Hive Metastore | bigtop-hostname0 |
| HiveServer2 | bigtop-hostname0 |
| Spark History Server | bigtop-hostname0 |
| Ambari Metrics Collector | bigtop-hostname0 |

### 7. 分配 Slave 和 Client（Assign Slaves and Clients）

| 组件 | 节点 |
|------|------|
| DataNode | hostname1, hostname2, hostname3 |
| NodeManager | hostname1, hostname2, hostname3 |
| RegionServer（HBase） | hostname1, hostname2, hostname3 |
| Client | hostname0（可选） |

### 8. 自定义服务配置（Customize Services）

#### HDFS
```
dfs.replication = 3
dfs.datanode.data.dir = /data/hdfs/data
dfs.namenode.name.dir = /data/hdfs/name
```

#### YARN
```
yarn.nodemanager.resource.memory-mb = 4096
yarn.scheduler.maximum-allocation-mb = 4096
yarn.nodemanager.resource.cpu-vcores = 2
```

#### Hive（如果选了）
- Database：选 **Existing MySQL / MariaDB**
- Database Host：`bigtop-hostname0.bigtop.apache.org`
- Database Name：`hive`
- Username：`hive`
- Password：`hive`
- 点击 "Test Connection" 确认连通

#### Ranger（如果选了）
- Ranger DB Host：`bigtop-hostname0.bigtop.apache.org`
- Ranger DB Name：`ranger`
- Ranger DB Username：`ranger`
- Ranger DB Password：`ranger`
- Audit DB Name：`ranger`

#### Ambari Metrics
保持默认即可。

### 9. 检查配置（Review）

确认所有配置无红色警告，点击 "Deploy"。

---

## 第二阶段：安装过程监控

安装过程中可以在 Web UI 看到每个节点的进度。

如果某个组件安装失败，在对应节点查看日志：

```bash
# 查看 agent 日志
docker compose exec bigtop_hostname1 tail -100 /var/log/ambari-agent/ambari-agent.log

# 查看具体组件安装日志
docker compose exec bigtop_hostname1 ls /var/lib/ambari-agent/data/
```

常见问题：

**包找不到**
```bash
# 确认 repo 里有对应的包
curl http://bigtop-hostname0.bigtop.apache.org/ | grep hadoop
```

**权限问题**
```bash
docker compose exec bigtop_hostname0 ambari-server status
```

---

## 第三阶段：集群验证

安装完成后验证各服务：

### HDFS
```bash
docker compose exec bigtop_hostname0 bash -c "
  su - hdfs -s /bin/bash -c 'hdfs dfs -ls /'
  su - hdfs -s /bin/bash -c 'hdfs dfsadmin -report'
"
```

### YARN
```bash
docker compose exec bigtop_hostname0 bash -c "
  su - yarn -s /bin/bash -c 'yarn node -list'
"
```

### MapReduce（跑一个 PI 测试）
```bash
docker compose exec bigtop_hostname0 bash -c "
  su - hdfs -s /bin/bash -c '
    yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar pi 2 10
  '
"
```

### ZooKeeper
```bash
docker compose exec bigtop_hostname0 bash -c "
  echo ruok | nc bigtop-hostname0.bigtop.apache.org 2181
"
# 返回 imok 表示正常
```

### Hive（如果安装了）
```bash
docker compose exec bigtop_hostname0 bash -c "
  su - hive -s /bin/bash -c 'beeline -u jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000 -e \"show databases;\"'
"
```

---

## 常用运维命令

### 容器管理
```bash
# 查看所有容器状态
docker compose ps

# 重启某个容器（保层，推荐；不要乱用 up -d）
docker compose restart bigtop_hostname1

# 容器重启后刷新 hosts（IP 可能变化）
cd ambari3/scripts
./setup-hostname.sh
```

> **⚠️ `up -d` 可能触发 Recreate（丢层）**：`docker compose up -d` 在容器配置、镜像或网络与 compose 定义不一致时，会把容器**先删后建**（可写层清零，Ambari/Hadoop/MySQL 全丢）。最常见的诱因是清理网段冲突时执行过 `docker network rm <网络名>` 后再 `up -d`。拿不准时一律用 `docker compose restart`；判断当前是否已被重建：
> ```bash
> docker compose exec bigtop_hostname0 bash -c \
>   'test -d /usr/lib/ambari-server && echo KEEP=重启 || echo WIPED=重建'
> ```
> 若输出 `WIPED=重建`，全量重装（见根目录 USER-GUIDE §9.1.2 / DEPLOY-GUIDE 部署方法一）。

### Ambari Server
```bash
docker compose exec bigtop_hostname0 ambari-server start
docker compose exec bigtop_hostname0 ambari-server stop
docker compose exec bigtop_hostname0 ambari-server restart
docker compose exec bigtop_hostname0 ambari-server status
```

### Ambari Agent
```bash
# 某节点 agent 重启
docker compose exec bigtop_hostname1 ambari-agent restart

# 查看 agent 日志
docker compose exec bigtop_hostname1 tail -f /var/log/ambari-agent/ambari-agent.log
```

### 查看服务日志
```bash
# HDFS NameNode
docker compose exec bigtop_hostname0 tail -100 /var/log/hadoop/hdfs/hadoop-hdfs-namenode-*.log

# YARN ResourceManager
docker compose exec bigtop_hostname0 tail -100 /var/log/hadoop/yarn/yarn-yarn-resourcemanager-*.log
```

---

## 注意事项

1. 容器重启后 IP 可能变化，需要重跑 `./setup-hostname.sh` 更新 hosts
2. nginx（repo 服务）重启后需要手动 `systemctl start nginx`，或重跑 `./setup-ambari-repo.sh`
3. 集群内存限制每个容器 8GB，安装服务时注意不要超配
4. MySQL 密码：root=`ambarirootpass`，ambari=`ambari`，hive=`hive`，ranger=`ranger`
