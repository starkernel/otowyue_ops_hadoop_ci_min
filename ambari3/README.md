# HodoopForge - Ambari 3.1.0 + Bigtop 3.5.0 Installation

<!--
  HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
  Forge Stability. Connect the Future.
  Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
-->

This setup uses **local RPM packages** — no internet download required for Ambari or Bigtop packages.

- Ambari: 3.1.0.0-SNAPSHOT (from `ambarirpm/`)
- Bigtop: 3.5.0 (from `bigtoprpm/`)
- OS: Rocky Linux 8 (via `bigtop/puppet:trunk-rockylinux-8`)

## Directory layout

```
ambari3/          ← this directory (cd here first)
ambarirpm/        ← Ambari 3.1.0 RPMs (mounted read-only into bigtop_hostname0)
bigtoprpm/        ← Bigtop 3.5.0 RPMs (mounted read-only into bigtop_hostname0)
```

## Step 1 — Start containers

> **⚠️ 首次部署 / 明确重建时**才用 `docker compose up -d`。日常重启请用 `docker compose restart`（保层）；`up -d` 在容器配置、镜像或网络与 compose 定义不一致时会 **Recreate（可写层清零，已装的 Ambari/Hadoop/MySQL 全丢）**。常见诱因：清理网段冲突时执行过 `docker network rm <网络名>` 后再 `up -d`。
>
> 重装路径：本 README Step 1→7 即全量重装流程；判定当前是"重启态"还是"重建态"及详细说明见根目录 `USER-GUIDE.md §9.1` 与 `DEPLOY-GUIDE.md`。

```bash
cd ambari3
docker compose up -d
```

## Step 2 — Initialize nodes (SSH, SELinux, etc.)

```bash
cd scripts
./setup.sh
```

## Step 3 — Build local yum repository

Copies all RPMs into `/var/repo/ambari` inside `bigtop_hostname0`, runs `createrepo`, and starts nginx.

```bash
./setup-ambari-repo.sh
```

## Step 4 — Install Ambari Server (node 0)

Installs ambari-server, MySQL, initializes the DB schema, injects the BIGTOP/3.5.0 stack definition, and starts the server.

```bash
./install-ambari-server.sh
```

## Step 5 — Install Ambari Agent (all nodes)

```bash
./install-ambari-agent.sh
```

## Step 6 — Setup cluster via Web UI

Open http://localhost:20609 (admin / admin)

### Configuration tips

- Repository Base URL: `http://bigtop-hostname0.bigtop.apache.org`
- OS type: `redhat8`
- Stack: select **BIGTOP 3.5.0**
- Cluster nodes (FQDN):
  ```
  bigtop-hostname0.bigtop.apache.org
  bigtop-hostname1.bigtop.apache.org
  bigtop-hostname2.bigtop.apache.org
  bigtop-hostname3.bigtop.apache.org
  ```

## Refreshing hostnames after container restart

```bash
cd scripts
./setup-hostname.sh
```

## Component versions (Bigtop 3.5.0)

| Component  | Version |
|------------|---------|
| Hadoop     | 3.3.6   |
| HBase      | 2.6.2   |
| Hive       | 4.0.1   |
| Spark      | 3.5.6   |
| Kafka      | 3.4.1   |
| ZooKeeper  | 3.8.4   |
| Ranger     | 2.7.0   |
| Tez        | 0.10.4  |
| Flink      | 1.20.1  |
| Solr       | 8.11.4  |
| Zeppelin   | 0.11.2  |
| Livy       | 0.8.0   |
| Phoenix    | 5.2.1   |

## Known Issues and Fixes

### Hive Service Issues

Hive 4.0.1 与 Ambari 3.1.0 存在一些兼容性问题，部署后需要运行修复脚本：

```bash
cd scripts
./fix-hive.sh
```

主要问题：
1. **hive.exec.post.hooks 配置** - Bigtop 3.5.0 stack 的 service_advisor.py 存在 bug，当没有 hooks 时返回空格 `" "` 而不是空字符串 `""`，导致 ClassNotFoundException
2. **Ambari 告警 auth 参数** - Hive 4.0.1 对 auth 参数大小写敏感，`auth=noSasl` 会失败，需要改为 `auth=none`
3. **HDFS 权限** - HiveServer2 需要以 hive 用户运行
4. **Metastore schema** - 需要手动初始化
5. **PID 文件** - 状态检测可能不匹配
6. **SYS DB 标记文件** - Ambari 需要 `/etc/hive/sys.db.created` 文件

修复后，在 Ambari UI 中重启 Hive 服务即可。

**注意**：部署脚本 `install-ambari-server-script.sh` 已包含 service_advisor.py 的修复，新部署时会自动应用。

### 告警说明

部署完成后，以下告警是正常的，等待几分钟让 Ambari 刷新状态：

- **Sys DB status** - 运行 `fix-hive.sh` 后会创建标记文件
- **HiveServer2 Process** - 服务启动后需要等待状态刷新



相关部署实施关键步骤：

在系统终端里按顺序执行就好：

cd ambari3

# Step 1: 启动容器
docker compose up -d

# Step 2: 初始化节点
cd scripts
./setup.sh

# Step 3: 建本地 yum 仓库
./setup-ambari-repo.sh

# Step 4: 安装 Ambari Server（含 stack 注入）
./install-ambari-server.sh

# Step 5: 所有节点安装 Agent
./install-ambari-agent.sh
完成后访问 http://localhost:20609，用 admin/admin 登录，选 BIGTOP 3.5.0 stack 开始建集群。



# refer: 相关用户参考以及HIVE相关问题修复
Grafana Admin

Username: admin
Password: admin123
Hive Database

Username: hive
Password: hive（和 install 脚本里一致）
Ranger Admin User Credentials

Username: admin
Password: Admin1234!（Ranger 要求密码有大写+数字+特殊字符，至少8位）
Ranger Admin Credentials for Ambari User

Username: amb_ranger_admin
Password: Admin1234!
Ranger Admin DB Credentials

Username: ranger
Password: ranger（和 install 脚本里一致）
Ranger Usersync user's password

Password: Admin1234!
Ranger Tagsync user's password

Password: Admin1234!
Ranger KMS keyadmin user's password

Password: Admin1234!

docker exec -it bigtop_hostname0 beeline -u jdbc:hive2://localhost:10000 -n hive

docker exec bigtop_hostname0 ps -ef | grep -E "metastore|hiveserver2"

cd ambari3
docker compose exec -T bigtop_hostname0 bash < scripts/fix-hive.sh

docker compose cp scripts/fix-hive.sh bigtop_hostname0:/tmp/fix-hive.sh
docker compose exec bigtop_hostname0 bash /tmp/fix-hive.sh

# refer: 常见FAQ



1. ZooKeeper 没起来 RegionServer 启动时必须能连上 ZK，ZK 挂了 RegionServer 直接起不来。

echo ruok | nc bigtop-hostname0.bigtop.apache.org 2181
# 返回 imok 才正常
2. HBase Master 还没 ready RegionServer 要向 Master 注册，Master 没起来或还在初始化中，RegionServer 会超时退出。

docker compose exec bigtop_hostname0 tail -50 /var/log/hbase/hbase-hbase-master-bigtop_hostname0.log
3. HDFS 上 HBase 目录权限问题

docker compose exec bigtop_hostname0 hdfs dfs -ls /hbase
# 应该是 hbase:hadoop 所有
4. hostname 解析问题 容器重启后 IP 变了但 hosts 没更新，RegionServer 注册到 ZK 的地址无法被 Master 反向连接。

docker compose exec bigtop_hostname1 cat /etc/hosts
# 确认 IP 和实际容器 IP 一致



Hive 无法启动的原因分析
fix-hive.sh 脚本本身就是问题的"说明书"，它记录了 6 个已知 bug：

1. hive.exec.post.hooks 配置了空格值（最常见）
Ambari 在配置 Hive 时，hive.exec.post.hooks 的值被设为一个空格 " "，而不是真正的空值。Hive 4.0.1 启动时会尝试加载这个"空格类名"，抛出 ClassNotFoundException，导致 HiveServer2 启动失败。

修复：

docker exec bigtop_hostname0 bash -c \
  "sed -i 's|<value> </value>|<value></value>|g' /etc/hive/conf/hive-site.xml"
2. Hive 4.0.1 对 auth 参数大小写敏感
Ambari Agent 的 hive_check.py 用 auth=noSasl 检测 HiveServer2 健康状态，但 Hive 4.0.1 只认 auth=none，导致 Ambari 一直报 HiveServer2 不健康，并可能触发重启循环。

修复：

docker exec bigtop_hostname0 bash -c \
  "sed -i 's/beeline_url.append(\"auth=noSasl\")/beeline_url.append(\"auth=none\")/g' \
  /usr/lib/ambari-agent/lib/resource_management/libraries/functions/hive_check.py"
3. Metastore schema 未初始化
如果 MySQL 里 hive 数据库的表结构没有初始化（VERSION 表不存在），Metastore 启动后会立即崩溃。

检查：

docker exec bigtop_hostname0 mysql -uhive -phive hive -e "SELECT * FROM VERSION" 2>&1
如果报错，需要初始化：

docker exec bigtop_hostname0 bash -c \
  "mysql -uhive -phive hive < /usr/lib/hive/scripts/metastore/upgrade/mysql/hive-schema-4.0.0.mysql.sql"
4. HDFS 仓库目录权限问题
Hive 需要 /warehouse/tablespace 和 /tmp/hive 目录存在且归 hive 用户所有，否则 HiveServer2 启动后执行任何查询都会失败。

修复：

docker exec bigtop_hostname0 bash -c "
  hdfs dfs -mkdir -p /warehouse/tablespace/managed/hive
  hdfs dfs -mkdir -p /warehouse/tablespace/external/hive
  hdfs dfs -mkdir -p /tmp/hive
  hdfs dfs -chown -R hive:hadoop /warehouse/tablespace
  hdfs dfs -chown hive:hadoop /tmp/hive
  hdfs dfs -chmod 1777 /tmp/hive
"
5. PID 文件不匹配
进程实际 PID 和 /var/run/hive/ 下的 PID 文件不一致，导致 Ambari 认为服务没在运行，反复尝试启动，造成冲突。

一键修复
直接在 ambari3 目录下运行已有的修复脚本：

cd ambari3
docker compose exec bigtop_hostname0 bash < scripts/fix-hive.sh
运行完后在 Ambari UI 里对 Hive 做 Restart 操作即可。如果还有问题，先看日志：

docker exec bigtop_hostname0 tail -100 /var/log/hive/hiveserver2.log
docker exec bigtop_hostname0 tail -100 /var/log/hive/hive-metastore.log