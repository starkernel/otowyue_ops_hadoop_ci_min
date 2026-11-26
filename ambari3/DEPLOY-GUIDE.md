# HodoopForge - Ambari 3.1 + Bigtop 3.5.0 集群访问与管理指南

<!--
  HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
  Forge Stability. Connect the Future.
  Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
-->

## 环境概览

| 节点 | 容器名 | Docker 内网 IP | 主要角色 |
|------|--------|---------------|---------|
| 宿主机 | - | 192.168.0.60 | 访问入口 |
| hostname0 | bigtop_hostname0 | 172.19.0.2 | Ambari Server, NameNode, ResourceManager, HiveServer2, HBase Master, Ranger Admin, Kafka Broker |
| hostname1 | bigtop_hostname1 | 172.19.0.5 | DataNode, NodeManager, ZooKeeper, APP_TIMELINE_SERVER |
| hostname2 | bigtop_hostname2 | 172.19.0.4 | DataNode, NodeManager, ZooKeeper |
| hostname3 | bigtop_hostname3 | 172.19.0.3 | DataNode, NodeManager, ZooKeeper, HBase RegionServer |

> 局域网内其他机器通过宿主机 IP `192.168.0.60` 访问。
> 容器内网 `172.19.0.x` 仅宿主机可直接访问。

---

## 网络访问说明

### 方式一：宿主机直接访问（推荐）

目前只有 Ambari UI 做了端口映射（`20609:8080`）。
其他服务需要通过以下方式之一访问：

**方式 A：在宿主机上添加 hosts 解析**

```bash
# 在宿主机 /etc/hosts 添加
172.19.0.2  bigtop-hostname0.bigtop.apache.org bigtop-hostname0
172.19.0.5  bigtop-hostname1.bigtop.apache.org bigtop-hostname1
172.19.0.4  bigtop-hostname2.bigtop.apache.org bigtop-hostname2
172.19.0.3  bigtop-hostname3.bigtop.apache.org bigtop-hostname3
```

添加后宿主机可直接通过域名访问容器内所有服务。

**方式 B：局域网其他机器访问**

在局域网其他机器的 `/etc/hosts` 添加（将 `192.168.0.60` 替换为宿主机实际 IP）：

```bash
192.168.0.60  bigtop-hostname0.bigtop.apache.org bigtop-hostname0
192.168.0.60  bigtop-hostname1.bigtop.apache.org bigtop-hostname1
192.168.0.60  bigtop-hostname2.bigtop.apache.org bigtop-hostname2
192.168.0.60  bigtop-hostname3.bigtop.apache.org bigtop-hostname3
```

同时需要在宿主机上做端口转发（见下方各服务端口转发配置）。

---

## 端口转发配置（局域网访问）

在宿主机执行以下命令，将容器端口暴露到宿主机：

```bash
# HDFS NameNode Web UI
iptables -t nat -A PREROUTING -p tcp --dport 50070 -j DNAT --to-destination 172.19.0.2:50070
iptables -t nat -A PREROUTING -p tcp --dport 8020  -j DNAT --to-destination 172.19.0.2:8020

# YARN ResourceManager Web UI
iptables -t nat -A PREROUTING -p tcp --dport 8088  -j DNAT --to-destination 172.19.0.2:8088

# MapReduce History Server
iptables -t nat -A PREROUTING -p tcp --dport 19888 -j DNAT --to-destination 172.19.0.2:19888

# HBase Master Web UI
iptables -t nat -A PREROUTING -p tcp --dport 16010 -j DNAT --to-destination 172.19.0.2:16010

# HiveServer2 (JDBC)
iptables -t nat -A PREROUTING -p tcp --dport 10000 -j DNAT --to-destination 172.19.0.2:10000
# HiveServer2 Web UI
iptables -t nat -A PREROUTING -p tcp --dport 10002 -j DNAT --to-destination 172.19.0.2:10002

# ZooKeeper
iptables -t nat -A PREROUTING -p tcp --dport 2181  -j DNAT --to-destination 172.19.0.2:2181

# Kafka
iptables -t nat -A PREROUTING -p tcp --dport 9092  -j DNAT --to-destination 172.19.0.2:9092

# Ranger Admin
iptables -t nat -A PREROUTING -p tcp --dport 6080  -j DNAT --to-destination 172.19.0.2:6080

# Spark History Server
iptables -t nat -A PREROUTING -p tcp --dport 18081 -j DNAT --to-destination 172.19.0.2:18081

# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -j MASQUERADE
```

---

## 各服务访问地址与说明

### 1. Ambari 管理界面

| 项目 | 值 |
|------|-----|
| URL | http://192.168.0.60:20609 |
| 用户名 | admin |
| 密码 | admin |

Ambari 是整个集群的统一管理入口，可以在这里启停服务、查看监控、修改配置。

---

### 2. HDFS

| 项目 | 值 |
|------|-----|
| NameNode Web UI | http://bigtop-hostname0.bigtop.apache.org:50070 |
| NameNode RPC | hdfs://bigtop-hostname0.bigtop.apache.org:8020 |
| SecondaryNameNode | http://bigtop-hostname0.bigtop.apache.org:50090 |

**命令行操作（在容器内或配置好 hadoop 客户端后）：**

```bash
# 进入容器
docker exec -it bigtop_hostname0 bash

# 查看根目录
hdfs dfs -ls /

# 创建目录
hdfs dfs -mkdir -p /user/test

# 上传文件
hdfs dfs -put /etc/hosts /user/test/

# 下载文件
hdfs dfs -get /user/test/hosts /tmp/

# 查看文件内容
hdfs dfs -cat /user/test/hosts

# 查看磁盘使用
hdfs dfs -du -h /

# 查看集群状态
hdfs dfsadmin -report

# 进入安全模式/退出安全模式
hdfs dfsadmin -safemode get
hdfs dfsadmin -safemode leave
```

**客户端配置（局域网其他机器）：**

安装 hadoop 客户端后，在 `core-site.xml` 中配置：

```xml
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://bigtop-hostname0.bigtop.apache.org:8020</value>
  </property>
</configuration>
```

---

### 3. YARN / MapReduce

| 项目 | 值 |
|------|-----|
| ResourceManager Web UI | http://bigtop-hostname0.bigtop.apache.org:8088 |
| MapReduce History Server | http://bigtop-hostname0.bigtop.apache.org:19888 |
| ResourceManager RPC | bigtop-hostname0.bigtop.apache.org:8050 |

**命令行操作：**

```bash
# 查看所有应用
yarn application -list

# 查看运行中的应用
yarn application -list -appStates RUNNING

# 杀死应用
yarn application -kill <application_id>

# 查看队列
yarn queue -status default

# 查看节点
yarn node -list

# 提交 MapReduce 示例作业
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar pi 4 100

# 查看作业历史
mapred job -history <job_id>
```

---

### 4. ZooKeeper

| 项目 | 值 |
|------|-----|
| 连接地址 | bigtop-hostname0.bigtop.apache.org:2181,bigtop-hostname1.bigtop.apache.org:2181,bigtop-hostname2.bigtop.apache.org:2181 |

**命令行操作：**

```bash
# 进入 ZooKeeper CLI
/usr/lib/zookeeper/bin/zkCli.sh -server bigtop-hostname0.bigtop.apache.org:2181

# 常用 ZK 命令
ls /              # 列出根节点
get /hiveserver2  # 查看 HiveServer2 注册信息
stat /            # 查看节点状态

# 四字命令（在宿主机执行）
echo ruok | nc bigtop-hostname0.bigtop.apache.org 2181   # 健康检查，返回 imok
echo stat | nc bigtop-hostname0.bigtop.apache.org 2181   # 查看统计信息
echo mntr | nc bigtop-hostname0.bigtop.apache.org 2181   # 详细监控信息
```

---

### 5. Hive

| 项目 | 值 |
|------|-----|
| HiveServer2 Web UI | http://bigtop-hostname0.bigtop.apache.org:10002 |
| JDBC URL | jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default |
| Metastore | thrift://bigtop-hostname0.bigtop.apache.org:9083 |
| 用户名 | hive（或任意用户） |
| 密码 | 无（默认无认证） |

**Beeline 命令行连接：**

```bash
# 在容器内
beeline -u "jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default" -n hive

# 常用 HiveQL
SHOW DATABASES;
CREATE DATABASE test;
USE test;
CREATE TABLE t1 (id INT, name STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',';
LOAD DATA LOCAL INPATH '/tmp/data.csv' INTO TABLE t1;
SELECT * FROM t1 LIMIT 10;
SHOW TABLES;
DESCRIBE t1;
```

**JDBC 连接（Java 客户端）：**

```java
String url = "jdbc:hive2://bigtop-hostname0.bigtop.apache.org:10000/default";
Connection conn = DriverManager.getConnection(url, "hive", "");
```

**通过 ZooKeeper 发现（高可用模式）：**

```
jdbc:hive2://bigtop-hostname0.bigtop.apache.org:2181,bigtop-hostname1.bigtop.apache.org:2181,bigtop-hostname2.bigtop.apache.org:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2
```

---

### 6. HBase

| 项目 | 值 |
|------|-----|
| HBase Master Web UI | http://bigtop-hostname0.bigtop.apache.org:16010 |
| HBase Master RPC | bigtop-hostname0.bigtop.apache.org:16000 |
| RegionServer Web UI | http://bigtop-hostname3.bigtop.apache.org:16030 |
| ZooKeeper Quorum | bigtop-hostname0:2181,bigtop-hostname1:2181,bigtop-hostname2:2181 |

**HBase Shell 操作：**

```bash
# 进入 HBase Shell
hbase shell

# 常用命令
status                          # 集群状态
list                            # 列出所有表
create 'test', 'cf1'            # 创建表
put 'test', 'row1', 'cf1:col1', 'value1'  # 写入数据
get 'test', 'row1'              # 读取行
scan 'test'                     # 扫描全表
scan 'test', {LIMIT => 10}      # 限制返回行数
delete 'test', 'row1', 'cf1:col1'  # 删除列
deleteall 'test', 'row1'        # 删除行
disable 'test'                  # 禁用表
drop 'test'                     # 删除表
describe 'test'                 # 查看表结构
count 'test'                    # 统计行数
```

**Java API 连接配置（hbase-site.xml）：**

```xml
<configuration>
  <property>
    <name>hbase.zookeeper.quorum</name>
    <value>bigtop-hostname0.bigtop.apache.org,bigtop-hostname1.bigtop.apache.org,bigtop-hostname2.bigtop.apache.org</value>
  </property>
  <property>
    <name>hbase.zookeeper.property.clientPort</name>
    <value>2181</value>
  </property>
</configuration>
```

---

### 7. Spark

| 项目 | 值 |
|------|-----|
| Spark History Server | http://bigtop-hostname0.bigtop.apache.org:18081 |
| 运行模式 | YARN（推荐） |

**提交 Spark 作业：**

```bash
# Spark on YARN（cluster 模式）
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --class org.apache.spark.examples.SparkPi \
  /usr/lib/spark/examples/jars/spark-examples_*.jar 100

# Spark on YARN（client 模式，适合调试）
spark-submit \
  --master yarn \
  --deploy-mode client \
  --class org.apache.spark.examples.SparkPi \
  /usr/lib/spark/examples/jars/spark-examples_*.jar 10

# 启动 Spark Shell
spark-shell --master yarn

# 启动 PySpark
pyspark --master yarn

# 查看 Spark 作业历史
# 访问 http://bigtop-hostname0.bigtop.apache.org:18081
```

**spark-defaults.conf 关键配置：**

```properties
spark.master                     yarn
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs:///spark-history
spark.history.fs.logDirectory    hdfs:///spark-history
spark.yarn.historyServer.address bigtop-hostname0.bigtop.apache.org:18081
```

---

### 8. Kafka

| 项目 | 值 |
|------|-----|
| Broker 地址 | bigtop-hostname0.bigtop.apache.org:9092 |
| ZooKeeper | bigtop-hostname0.bigtop.apache.org:2181/kafka |

**命令行操作：**

```bash
# 创建 Topic
kafka-topics.sh --create \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --replication-factor 1 \
  --partitions 3 \
  --topic test-topic

# 列出 Topic
kafka-topics.sh --list \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092

# 查看 Topic 详情
kafka-topics.sh --describe \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --topic test-topic

# 生产消息
kafka-console-producer.sh \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --topic test-topic

# 消费消息（从头开始）
kafka-console-consumer.sh \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --topic test-topic \
  --from-beginning

# 查看消费组
kafka-consumer-groups.sh \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --list

# 删除 Topic
kafka-topics.sh --delete \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --topic test-topic
```

---

### 9. Ranger

| 项目 | 值 |
|------|-----|
| Ranger Admin Web UI | http://bigtop-hostname0.bigtop.apache.org:6080 |
| 管理员账号 | admin |
| 管理员密码 | Admin1234! |

**主要功能：**
- 为 HDFS、Hive、HBase、Kafka、YARN 配置细粒度访问控制策略
- 查看审计日志（需要配置 Solr 审计）
- 管理用户和用户组

**常用操作：**
1. 登录 http://bigtop-hostname0.bigtop.apache.org:6080
2. 进入 **Access Manager → Resource Based Policies**
3. 选择对应服务（HDFS/Hive/HBase 等）
4. 点击 **Add New Policy** 添加访问策略

---

### 10. Tez

Tez 是 Hive 的执行引擎，无独立 Web UI，通过 YARN 界面查看 Tez 作业。

| 项目 | 值 |
|------|-----|
| Tez UI（通过 YARN） | http://bigtop-hostname0.bigtop.apache.org:8088/tez-ui |
| 配置目录 | /etc/tez/conf |

**Hive 中使用 Tez：**

```sql
-- 确认使用 Tez 引擎
SET hive.execution.engine=tez;

-- 查看当前引擎
SET hive.execution.engine;
```

---

## 集群管理常用操作

### 启停服务

通过 Ambari UI（http://192.168.0.60:20609）统一管理，或使用命令行：

```bash
# 在容器内启停 HDFS
ambari-agent restart   # 重启 agent

# 通过 Ambari API 启动服务
curl -u admin:admin -X PUT \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Start HDFS"},"Body":{"ServiceInfo":{"state":"STARTED"}}}' \
  "http://localhost:8080/api/v1/clusters/otowyue_redoop/services/HDFS"
```

### 容器重启后恢复

> **⚠️ 先判定"重启"还是"重建"**：下方流程仅适用**重启（restart）**——可写层还在，只是 hosts/软链接/包名被还原。若容器被**重建（recreate）**（典型诱因：`docker network rm` 清网段冲突后 `docker compose up -d`），可写层已清空、Ambari 未安装，`setup-hostname.sh` 会因栈目录不存在报错，必须**全量重装**（见"部署方法一"①~⑦ + 见根目录 `USER-GUIDE.md §9.1`）。
>
> ```bash
> # 判定：可写层还在？
> docker compose exec bigtop_hostname0 bash -c \
>   'test -d /usr/lib/ambari-server && echo KEEP=重启 || echo WIPED=重建'
> docker compose ps   # 重建时 Created 时间会被更新为最近一次 up -d 的时刻
> ```

```bash
cd ambari3

# 1. 启动容器（配置/网络未变化时推荐 docker compose restart，避免误触发重建丢层）
docker compose restart

# 2. 修复 hostname（容器重启后需要）
cd scripts && ./setup-hostname.sh

# 3. 启动 Ambari Server
docker exec bigtop_hostname0 ambari-server start

# 4. 启动所有 Agent
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  docker exec $h ambari-agent start
done

# 5. 通过 Ambari UI 启动集群服务
# 访问 http://192.168.0.60:20609 → Actions → Start All
```

### 查看日志

```bash
# Ambari Server 日志
docker exec bigtop_hostname0 tail -f /var/log/ambari-server/ambari-server.log

# HDFS NameNode 日志
docker exec bigtop_hostname0 tail -f /var/log/hadoop-hdfs/hadoop-hdfs-namenode-*.log

# YARN ResourceManager 日志
docker exec bigtop_hostname0 tail -f /var/log/hadoop-yarn/yarn-yarn-resourcemanager-*.log

# HiveServer2 日志
docker exec bigtop_hostname0 tail -f /var/log/hive/hiveserver2.log

# HBase Master 日志
docker exec bigtop_hostname0 tail -f /var/log/hbase/hbase-hbase-master-*.log

# Ranger Admin 日志
docker exec bigtop_hostname0 tail -f /usr/lib/ranger-admin/ews/logs/ranger-admin-*.log

# Kafka 日志
docker exec bigtop_hostname0 tail -f /var/log/kafka/server.log
```

---

## 端口速查表

| 服务 | 端口 | 协议 | 说明 |
|------|------|------|------|
| Ambari UI | 20609 (宿主机) / 8080 (容器) | HTTP | 集群管理界面 |
| HDFS NameNode UI | 50070 | HTTP | HDFS Web 界面 |
| HDFS NameNode RPC | 8020 | TCP | HDFS 客户端连接 |
| HDFS SecondaryNameNode | 50090 | HTTP | 检查点服务 |
| YARN ResourceManager UI | 8088 | HTTP | YARN 作业管理 |
| YARN ResourceManager RPC | 8050 | TCP | 客户端提交作业 |
| MapReduce History Server | 19888 | HTTP | 历史作业查看 |
| HBase Master UI | 16010 | HTTP | HBase 管理界面 |
| HBase Master RPC | 16000 | TCP | HBase 客户端 |
| HBase RegionServer UI | 16030 | HTTP | RegionServer 状态 |
| HiveServer2 JDBC | 10000 | TCP | Hive JDBC 连接 |
| HiveServer2 UI | 10002 | HTTP | HiveServer2 Web |
| Hive Metastore | 9083 | TCP | Thrift 协议 |
| ZooKeeper | 2181 | TCP | 客户端连接 |
| Kafka Broker | 9092 | TCP | 消息生产/消费 |
| Ranger Admin UI | 6080 | HTTP | 权限管理界面 |
| Spark History Server | 18081 | HTTP | Spark 历史作业 |
| MySQL | 3306 | TCP | 元数据库（内部） |

---

## 常见问题

### Q: 局域网机器连接 HDFS 报错 "Connection refused"
确认宿主机已做端口转发，且 `/etc/hosts` 中域名解析指向宿主机 IP（不是容器 IP）。

### Q: Hive 查询报 "Metastore connection failed"
检查 Hive Metastore 是否启动：
```bash
docker exec bigtop_hostname0 netstat -tlnp | grep 9083
```

### Q: Spark 作业提交失败
确认 YARN 和 HDFS 都已启动，且 `/spark-history` 目录存在：
```bash
docker exec bigtop_hostname0 hdfs dfs -ls /spark-history
```

### Q: Kafka 消费者连接超时
Kafka 返回的 broker 地址是容器内域名，局域网机器需要在 hosts 文件中添加对应解析，且宿主机需要做 9092 端口转发。

### Q: 容器重启后服务无法自动启动
容器使用 systemd，服务需要通过 Ambari 手动启动，或在 Ambari UI 中设置 **Service Auto Start**（Cluster Admin → Service Auto Start）。
