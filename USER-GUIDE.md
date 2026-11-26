# HodoopForge 用户指导说明书

> **软件名称**：HodoopForge 企业级 Hadoop 集群部署与管理平台  
> **版本**：V1.1  
> **口号**：*锻造稳定 · 连接未来 | Forge Stability. Connect the Future.*  
> **文档修订日期**：2026年9月

---

## 目录

1. [产品概述](#1-产品概述)
2. [系统要求与前置条件](#2-系统要求与前置条件)
3. [目录结构说明](#3-目录结构说明)
4. [快速部署（标准流程）](#4-快速部署标准流程)
5. [Ambari Web UI 集群创建向导](#5-ambari-web-ui-集群创建向导)
6. [组件版本与服务访问地址](#6-组件版本与服务访问地址)
7. [网络访问配置](#7-网络访问配置)
8. [各服务操作手册](#8-各服务操作手册)
9. [日常运维操作](#9-日常运维操作)
10. [运维工具（opstools）使用说明](#10-运维工具opstools使用说明)
11. [已知问题与修复方案](#11-已知问题与修复方案)
12. [安全凭证速查](#12-安全凭证速查)
13. [端口速查表](#13-端口速查表)
14. [常见问题排查（FAQ）](#14-常见问题排查faq)

---

## 1. 产品概述

HodoopForge 是一款专为解决 **Apache Ambari 3.x** 与 **Apache Bigtop 3.5.0 及以上版本** 联调困难、兼容性差、部署复杂问题而设计的企业级开源 Hadoop 集群管理平台。

### 1.1 核心价值

| 能力项 | 描述 |
|--------|------|
| 无缝集成 | 针对 Ambari 3.x 与 Bigtop 3.5+ 版本不匹配、Stack 加载失败、组件依赖冲突等问题进行专项修复 |
| 离线部署 | 所有 RPM 包本地内置，无需公网下载，支持完全离线环境 |
| 全生命周期管理 | 集群置备、配置管理、服务监控、告警、滚动升级、HA 配置一体化 |
| 安全集成 | 内置 Kerberos、Ranger 等安全框架，支持细粒度权限管理 |
| 易扩展 | 支持自定义 Stack，便于集成第三方或自研组件 |

### 1.2 适用场景

- 需要运行最新 Apache Bigtop 版本但受限于 Ambari 兼容性问题的团队
- 追求纯开源、无厂商锁定的 Hadoop 生产环境
- 从 Cloudera HDP/CDP 等商业发行版迁移到社区栈的用户
- 大数据平台运维团队，希望降低部署与日常管理复杂度的组织

### 1.3 技术架构

```
┌─────────────────────────────────────────────────────┐
│                  HodoopForge 平台                    │
│                                                     │
│  ┌────────────────────────────────────────────────┐ │
│  │         Ambari 3.1.0 管理层（Web UI + API）      │ │
│  └────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────┐ │
│  │         Bigtop 3.5.0 组件层                     │ │
│  │  Hadoop · Hive · Spark · HBase · Kafka · ...   │ │
│  └────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────┐ │
│  │      Rocky Linux 8 容器基础设施（Docker）        │ │
│  │   hostname0 · hostname1 · hostname2 · hostname3 │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## 2. 系统要求与前置条件

### 2.1 宿主机硬件要求

| 资源 | 最低配置 | 推荐配置 |
|------|----------|----------|
| CPU | 8 核 | 16 核以上 |
| 内存 | 32 GB | 64 GB |
| 磁盘 | 100 GB 可用空间 | 200 GB SSD |
| 网络 | 千兆以太网 | — |

> 容器内存限额（`ambari3/docker-compose.yml` 的 `mem_limit`）：hostname0 默认 16 GB，hostname1~3 各 12 GB，4 个容器合计需约 52 GB 空闲内存——**8g 限额下 HS2（默认堆 6G+）会直接 OOM、Hive 整体起不来**（见 §11.5.12）。单测/最小环境建议 64 GB 以上，可先用 `docker update --memory <n>g <容器名>` 临时调整（不重建、不丢层），再同步改 compose 保持一致性。

### 2.2 软件依赖

| 软件 | 版本要求 | 说明 |
|------|----------|------|
| Docker Engine | 24.0+ | 容器运行时 |
| Docker Compose | V2（`docker compose`） | 容器编排，注意是 V2 命令格式 |
| Python3 | 3.6+ | 部分脚本依赖 |
| jq | 任意版本 | 运维工具脚本使用（可选） |

> **Vagrant 模式（可选）**：如需通过 VirtualBox 虚拟机部署，根目录提供了 `Vagrantfile`，需要安装 Vagrant 和 VirtualBox。节点配置为 node1（4 核/4 GB，Ambari Server）、node2/node3（4 核/4 GB，Agent）。

### 2.3 内置软件包

本项目已内置所有 RPM 包，无需互联网访问：

- `ambarirpm/` — Ambari 3.1.0.0-SNAPSHOT RPM 包（10 个）
- `bigtoprpm/` — Bigtop 3.5.0 组件 RPM 包（按组件分子目录）

---

## 3. 目录结构说明

```
hadoop-ops-course/
├── README.md                    # 项目主文档（中英文）
├── Vagrantfile                  # VirtualBox 虚拟机部署配置（可选）
├── ambarirpm/                   # Ambari 3.1.0 RPM 包
├── bigtoprpm/                   # Bigtop 3.5.0 组件 RPM 包（按组件分目录）
│
├── ambari3/                     # ★ 核心部署目录（主要工作目录）
│   ├── docker-compose.yml       # 4 节点 Docker 容器定义
│   ├── README.md                # 部署快速参考
│   ├── DEPLOY-GUIDE.md          # 集群访问与管理指南
│   ├── deploy00.md              # Web UI 部署向导详解
│   ├── ambari-repo/             # 本地 Yum 仓库（含 VDF 定义文件）
│   ├── conf/
│   │   └── hosts                # 自动生成的容器 /etc/hosts 挂载文件
│   └── scripts/                 # 部署脚本集合
│       ├── setup.sh             # Step 2: 初始化节点（SSH/SELinux/Hosts）
│       ├── setup-ambari-repo.sh # Step 3: 构建本地 Yum 仓库（nginx）
│       ├── install-ambari-server.sh   # Step 4: 安装 Ambari Server
│       ├── install-ambari-agent.sh    # Step 5: 安装所有节点 Agent
│       ├── setup-hostname.sh    # 容器重启后修复主机名解析、重建软链接、修复包名
│       ├── post-deploy-fixes.sh # ★ Deploy 后一键修复所有已知兼容性问题
│       ├── setup-nat-forward.sh # 宿主机 NAT 端口转发配置（局域网访问）
│       ├── fix-hive.sh          # Hive 4.0.1 兼容性修复
│       ├── setup-bigtop-stack.sh      # 注入 Bigtop 3.5.0 Stack 定义
│       ├── fix-package-names.sh       # 修复 Bigtop 包命名（容器重启后须重跑）
│       ├── insert-repo-version.py     # 注入仓库版本信息
│       ├── fix_secrets.py       # 修复安全配置
│       └── ranger_pwd.py        # Ranger 密码配置工具
│
├── opstools/                    # 运维工具集
│   ├── ops/                     # Shell 运维脚本
│   │   ├── health-check.sh      # 集群健康检查
│   │   ├── restart-services.sh  # 服务重启
│   │   ├── backup-config.sh     # 配置备份
│   │   ├── restore-config.sh    # 配置恢复
│   │   ├── monitor-cluster.sh   # 集群监控
│   │   ├── log-collect.sh       # 日志收集
│   │   ├── clean-cluster.sh     # 集群清理
│   │   ├── deploy-stack.sh      # Stack 部署
│   │   └── verify-install.sh    # 安装验证
│   ├── python/                  # Python 运维脚本
│   │   ├── api-client.py        # Ambari API 客户端
│   │   ├── service-checker.py   # 服务状态检查
│   │   ├── alert-manager.py     # 告警管理
│   │   ├── metrics-collector.py # 指标采集
│   │   ├── log-analyzer.py      # 日志分析
│   │   ├── backup-restore.py    # 备份恢复
│   │   ├── cluster-scaler.py    # 集群扩缩容
│   │   ├── config-validator.py  # 配置校验
│   │   └── performance-test.py  # 性能测试
│   └── upgrade/
│       ├── upgrade-stack.sh     # Stack 滚动升级
│       └── cluster-info.sh      # 集群信息查询
│
├── blueprints/                  # Ambari Blueprint 模板
│   ├── blueprint.json           # 集群蓝图定义
│   └── template.json            # 集群拓扑模板
│
├── scripts/                     # Vagrant 模式部署脚本
│   ├── install_ambari_server.sh
│   ├── install_ambari_agent.sh
│   ├── install_krb5.sh          # Kerberos 安装
│   ├── setup_ranger.sh          # Ranger 安全配置
│   ├── create_blueprint.sh      # 蓝图创建
│   └── import_blueprint.sh      # 蓝图导入
│
└── demos/                       # 示例代码
    ├── MapReduce.java            # MapReduce Java 示例
    ├── wordcount.py              # Spark PySpark 词频统计
    ├── PhoenixDemo.sql           # Phoenix SQL 示例
    ├── spark-kafka-wordcount/    # Spark + Kafka 流处理示例
    └── storm-kafka-wordcount/    # Storm + Kafka 流处理示例
```

---

## 4. 快速部署（标准流程）

> **重要**：所有部署命令必须在 `ambari3/scripts/` 目录下执行（或在 `ambari3/` 目录下执行对应的 `cd scripts` 版本）。

### Step 0 — 准备工作

确认 Docker 和 Docker Compose 已正常运行：

```bash
docker --version
docker compose version
```

### Step 1 — 启动容器

```bash
cd ambari3
docker compose up -d
```

验证 4 个容器均已启动：

```bash
docker compose ps
# 应看到 bigtop_hostname0~3 全部处于 Up 状态
```

容器镜像：`bigtop/puppet:trunk-rockylinux-8`（Rocky Linux 8）

### Step 2 — 初始化节点

```bash
cd scripts
./setup.sh
```

该脚本执行以下操作：
- 在所有节点安装 SSH 服务端/客户端、基础工具包
- 生成 SSH 密钥并将 hostname0 的公钥分发到所有节点（实现免密登录）
- 关闭 SELinux 强制模式
- 自动获取各容器 IP 并生成 `/etc/hosts` 文件，挂载到所有容器

### Step 3 — 构建本地 Yum 仓库

```bash
./setup-ambari-repo.sh
```

该脚本在 `bigtop_hostname0` 容器内执行：
- 将 `ambari-repo/` 下的 RPM 包注册为本地 Yum 仓库（通过 `createrepo`）
- 启动 Nginx 作为仓库 HTTP 服务（监听 80 端口）

### Step 4 — 安装 Ambari Server

```bash
./install-ambari-server.sh
```

该脚本在 `bigtop_hostname0` 内执行：
- 安装 `ambari-server` RPM 包及其依赖
- 初始化 MySQL 元数据库（用户/密码：`ambari/ambari`，root 密码：`ambarirootpass`）
- 向 Ambari 注入 **BIGTOP 3.5.0 Stack 定义**（`setup-bigtop-stack.sh`）
- 修复 Bigtop 包命名兼容性问题（`fix-package-names.sh`）
- 启动 Ambari Server

### Step 5 — 安装 Ambari Agent（所有节点）

```bash
./install-ambari-agent.sh
```

该脚本在所有 4 个节点上安装并配置 `ambari-agent`，将 Agent 指向 `bigtop-hostname0.bigtop.apache.org` 作为 Server 地址，并启动 Agent 服务。

### Step 6 — 通过 Web UI 创建集群

打开浏览器访问：**http://localhost:20609**

登录凭证：用户名 `admin`，密码 `admin`

详细的 Web UI 操作步骤见第 [5 节](#5-ambari-web-ui-集群创建向导)。

---

### Step 7 — Deploy 后执行一键修复脚本

Ambari Web UI 完成集群创建向导并点击 Deploy 之后，**必须执行**以下修复脚本，解决 Ambari 3.1.0 与 Bigtop 3.5.0 之间的已知兼容性问题，否则大量服务会安装失败：

```bash
# 在宿主机 ambari3/ 目录下执行
cd /home/rkam/hadoop-ops-course/ambari3
./scripts/post-deploy-fixes.sh
```

> **何时执行**：每次 Deploy 失败后点 Retry 之前，先运行一次此脚本。脚本是幂等的，多次运行无副作用。

脚本自动处理以下 8 项已知问题：

| Fix | 问题描述 | 影响 |
|-----|----------|------|
| Fix 1 | 容器无硬件时钟，Agent 上报 UNHEALTHY | 所有 Install 任务被拒绝下发 |
| Fix 2 | cluster-env 缺 APP_TIMELINE_SERVER/TIMELINE_READER 映射 | Timeline Service V2 Install abort |
| Fix 3 | BIGTOP 3.5.0 stack_id=0 被 EclipseLink 拒绝 | VDF 上传报 Server Error |
| Fix 3b | Agent cache 里 `${stack_version}` 占位符未清理 | 所有组件包名匹配失败 |
| Fix 3c | hostname2/3 未安装 JDK8 | before-ANY hook 失败，所有 Install 连锁报错 |
| Fix 4 | Hive service_advisor.py hooks 空格 bug | HiveServer2 启动抛 ClassNotFoundException |
| Fix 5 | Agent hive_check.py `auth=noSasl` 不兼容 | Hive 健康检查持续失败触发重启循环 |
| Fix 6 | Stack XML 文件含 shell 注释行导致解析失败 | Ambari UI 显示 BIGTOP 3.4.0 而非 3.5.0 |
| Fix 7 | 重启 Ambari Server 刷新 stack 缓存 | — |
| Fix 8 | 输出所有节点 HEALTHY 状态汇总 | — |

脚本运行完成后，回到 Ambari UI 点击 **Retry** 重试失败任务。

---

### 部署完成后——修复 Hive（如已安装）

```bash
cd ambari3
docker compose exec bigtop_hostname0 bash < scripts/fix-hive.sh
```

详见第 [11 节](#11-已知问题与修复方案)。

---

## 5. Ambari Web UI 集群创建向导

### 5.1 登录并启动向导

1. 浏览器访问 `http://localhost:20609`，使用 `admin / admin` 登录
2. 点击 **"Launch Install Wizard"**，输入集群名称（如 `bigtop-cluster`）

### 5.2 选择 Stack

- Stack 选择 **BIGTOP**，版本选 **3.5.0**
- 点击 **"Use Local Repository"**
- 删除所有默认 URL，仅保留 `redhat8` 条目，填入：
  ```
  http://bigtop-hostname0.bigtop.apache.org
  ```
- OS 类型选 `redhat8`

### 5.3 注册目标节点

在 Target Hosts 中填入（每行一个）：

```
bigtop-hostname0.bigtop.apache.org
bigtop-hostname1.bigtop.apache.org
bigtop-hostname2.bigtop.apache.org
bigtop-hostname3.bigtop.apache.org
```

Host Registration 选择：**"Perform manual registration on hosts and do not use SSH"**

点击 **"Register and Confirm"**，等待所有节点显示绿色 Registered 状态。

> 若节点注册失败，检查 Agent 状态和配置：
> ```bash
> docker compose exec bigtop_hostname1 ambari-agent status
> docker compose exec bigtop_hostname1 cat /etc/ambari-agent/conf/ambari-agent.ini | grep hostname
> # 应显示 hostname=bigtop-hostname0.bigtop.apache.org
> ```

### 5.4 选择安装服务

推荐的最小化安装组合：

| 服务 | 优先级 | 说明 |
|------|--------|------|
| HDFS | 必选 | 分布式文件系统 |
| YARN + MapReduce2 | 必选 | 资源管理与批处理 |
| ZooKeeper | 必选 | 分布式协调，多服务依赖 |
| Ambari Metrics | 建议 | 集群监控指标 |
| Tez | 按需 | Hive 执行引擎依赖 |
| Hive | 按需 | 数据仓库 SQL 层 |
| HBase | 按需 | 分布式 NoSQL |
| Spark | 按需 | 内存计算引擎 |
| Kafka | 按需 | 分布式消息队列 |
| Ranger | 按需 | 细粒度权限管理 |

### 5.5 组件分配建议（4 节点）

**Master 组件分配：**

| 组件 | 分配节点 |
|------|----------|
| NameNode | bigtop-hostname0 |
| Secondary NameNode | bigtop-hostname1 |
| ResourceManager | bigtop-hostname0 |
| History Server | bigtop-hostname0 |
| ZooKeeper Server | hostname0, hostname1, hostname2 |
| HiveServer2 + Metastore | bigtop-hostname0 |
| HBase Master | bigtop-hostname0 |
| Spark History Server | bigtop-hostname0 |
| Kafka Broker | bigtop-hostname0 |
| Ranger Admin | bigtop-hostname0 |
| Ambari Metrics Collector | bigtop-hostname0 |

**Slave 组件分配：**

| 组件 | 分配节点 |
|------|----------|
| DataNode | hostname1, hostname2, hostname3 |
| NodeManager | hostname1, hostname2, hostname3 |
| HBase RegionServer | hostname1, hostname2, hostname3 |

### 5.6 关键配置参数

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

#### Hive（选择 MySQL 数据库）
```
Database Type: Existing MySQL / MariaDB
Database Host: bigtop-hostname0.bigtop.apache.org
Database Name: hive
Username: hive
Password: hive
```

#### Ranger

Ambari UI 中 Ranger 数据库配置分两个区域，填写如下：

**Ranger DB 配置（上方区域）**
```
DB Flavor:            MySQL
Ranger DB name:       ranger
Ranger DB username:   rangeradmin
Ranger DB password:   Admin1234!
Ranger DB host:       bigtop-hostname1.bigtop.apache.org
Driver class:         com.mysql.jdbc.Driver
JDBC connect string:  jdbc:mysql://bigtop-hostname1.bigtop.apache.org:3306/ranger
```

**Setup Database — DBA 连接（下方区域）**
```
DBA username:         root
DBA password:         ambarirootpass
JDBC connect string:  jdbc:mysql://bigtop-hostname1.bigtop.apache.org:3306
```

> **注意**：`rangeradmin` 和 `ranger` 是两个不同的 MySQL 用户。
> Ambari UI 默认填写 `rangeradmin` 作为应用用户；`root` 仅用于 DBA 初始化操作（建表、授权）。
> 两者均已在部署时预建，直接点击 **Test Connection** 验证即可。

### 5.7 部署与验证

配置无红色告警后，点击 **Deploy**。安装过程中：
- 可在 Web UI 查看各节点安装进度
- 若组件失败，查看 Agent 日志：`docker compose exec bigtop_hostname1 tail -100 /var/log/ambari-agent/ambari-agent.log`

---

## 6. 组件版本与服务访问地址

### 6.1 集群节点拓扑

| 节点 | 容器名 | Docker 内网 IP | 主要角色 |
|------|--------|---------------|---------|
| 宿主机入口 | — | 192.168.0.60（示例） | 外部访问入口 |
| hostname0 | bigtop_hostname0 | 172.19.0.2 | Ambari Server, NameNode, ResourceManager, HiveServer2, HBase Master, Ranger, Kafka |
| hostname1 | bigtop_hostname1 | 172.19.0.5 | DataNode, NodeManager, ZooKeeper, Timeline Server |
| hostname2 | bigtop_hostname2 | 172.19.0.4 | DataNode, NodeManager, ZooKeeper |
| hostname3 | bigtop_hostname3 | 172.19.0.3 | DataNode, NodeManager, ZooKeeper, HBase RegionServer |

### 6.2 Bigtop 3.5.0 组件版本

| 组件 | 版本 | 组件 | 版本 |
|------|------|------|------|
| Hadoop | 3.3.6 | Kafka | 3.4.1 |
| HBase | 2.6.2 | ZooKeeper | 3.8.4 |
| Hive | 4.0.1 | Ranger | 2.7.0 |
| Spark | 3.5.6 | Tez | 0.10.4 |
| Flink | 1.20.1 | Solr | 8.11.4 |
| Iceberg (Spark 3.5) | 1.6.1 | Iceberg (Flink 1.20) | 1.11.0 |
| Zeppelin | 0.11.2 | Livy | 0.8.0 |
| Phoenix | 5.2.1 | Alluxio | 2.9.6 |

---

## 7. 网络访问配置

### 7.1 宿主机本地访问（推荐）

Ambari UI 已做端口映射（宿主机 `20609` → 容器 `8080`），直接访问：
- Ambari UI：`http://localhost:20609`

其他服务需通过容器内网 IP 访问，在宿主机 `/etc/hosts` 添加以下解析：

```
172.19.0.2  bigtop-hostname0.bigtop.apache.org bigtop-hostname0
172.19.0.5  bigtop-hostname1.bigtop.apache.org bigtop-hostname1
172.19.0.3  bigtop-hostname2.bigtop.apache.org bigtop-hostname2
172.19.0.4  bigtop-hostname3.bigtop.apache.org bigtop-hostname3
```

> **注意**：容器每次重启后 IP 可能变化，需重新运行 `./setup-hostname.sh` 并更新 hosts 记录。

### 7.2 局域网其他机器访问

在目标机器的 `/etc/hosts` 中将域名解析指向**宿主机 IP**（如 192.168.0.60）：

```
192.168.0.60  bigtop-hostname0.bigtop.apache.org bigtop-hostname0
192.168.0.60  bigtop-hostname1.bigtop.apache.org bigtop-hostname1
192.168.0.60  bigtop-hostname2.bigtop.apache.org bigtop-hostname2
192.168.0.60  bigtop-hostname3.bigtop.apache.org bigtop-hostname3
```

同时在宿主机配置 iptables 端口转发（将容器端口暴露到宿主机），推荐使用项目自带脚本：

```bash
# 一键应用所有服务端口转发（52条规则，覆盖全部 Bigtop 组件）
sudo ./ambari3/scripts/setup-nat-forward.sh apply

# 查看规则应用状态
sudo ./ambari3/scripts/setup-nat-forward.sh status

# 清除所有规则（仅清除脚本自身定义的规则）
sudo ./ambari3/scripts/setup-nat-forward.sh remove

# 容器重启后自动探测新的容器 IP 并全量重建（先 remove 再 apply）
sudo ./ambari3/scripts/setup-nat-forward.sh refresh
```

> **重要**：宿主机开启了 `net.bridge.bridge-nf-call-iptables=1`，容器间同网段流量也会经过宿主 netfilter，
> 因此 PREROUTING 中的 DNAT 会命中容器间通信。脚本已严格按"实际组件分布"定义目标节点，
> **切勿手动添加或残留旧脚本时代的僵尸规则（同一宿主机端口指向不同容器 IP）**，否则会劫持容器间流量、服务连接超时。
> 若怀疑存在残留规则，可先在宿主执行 `sudo iptables -t nat -S PREROUTING` 检查重复端口，并 `remove` 后重新 `apply`。

也可手动添加常用端口（目标 IP 必须与实际组件所在节点一致，切勿随意指向 hostname0）：

```bash
# HDFS（hostname0）
iptables -t nat -A PREROUTING -p tcp --dport 50070 -j DNAT --to-destination 172.19.0.2:50070
iptables -t nat -A PREROUTING -p tcp --dport 8020  -j DNAT --to-destination 172.19.0.2:8020
# YARN ResourceManager（hostname0）
iptables -t nat -A PREROUTING -p tcp --dport 8088  -j DNAT --to-destination 172.19.0.2:8088
# HiveServer2 JDBC（hostname1）
iptables -t nat -A PREROUTING -p tcp --dport 10000 -j DNAT --to-destination 172.19.0.5:10000
# HBase Master UI（hostname0）
iptables -t nat -A PREROUTING -p tcp --dport 16010 -j DNAT --to-destination 172.19.0.2:16010
# Kafka Broker（hostname0）
iptables -t nat -A PREROUTING -p tcp --dport 9092  -j DNAT --to-destination 172.19.0.2:9092
# Ranger Admin UI（hostname1）
iptables -t nat -A PREROUTING -p tcp --dport 6080  -j DNAT --to-destination 172.19.0.5:6080
# Spark History Server（hostname0）
iptables -t nat -A PREROUTING -p tcp --dport 18081 -j DNAT --to-destination 172.19.0.2:18081
# ZooKeeper Client（hostname0，使用 21810，勿再用 2181/2888/3888）
iptables -t nat -A PREROUTING -p tcp --dport 21810 -j DNAT --to-destination 172.19.0.2:2181
# 启用转发
echo 1 > /proc/sys/net/ipv4/ip_forward
```

---

## 8. 各服务操作手册

### 8.1 Ambari 管理界面

| 项目 | 值 |
|------|-----|
| URL（本地） | http://localhost:20609 |
| URL（局域网） | http://192.168.0.60:20609 |
| 用户名 / 密码 | admin / admin |

Ambari 是集群的统一管理入口，提供服务启停、配置管理、监控告警等功能。

通过 REST API 操作服务示例：

```bash
# 启动 HDFS
curl -u admin:admin -X PUT \
  -H "Content-Type: application/json" \
  -d '{"RequestInfo":{"context":"Start HDFS"},"Body":{"ServiceInfo":{"state":"STARTED"}}}' \
  "http://localhost:20609/api/v1/clusters/bigtop-cluster/services/HDFS"
```

---

### 8.2 HDFS

| 项目 | 值 |
|------|-----|
| NameNode Web UI | http://bigtop-hostname0.bigtop.apache.org:50070 |
| NameNode RPC | hdfs://bigtop-hostname0.bigtop.apache.org:8020 |
| Secondary NameNode UI | http://bigtop-hostname1.bigtop.apache.org:50090 |

**常用命令：**

```bash
# 进入主节点容器
docker exec -it bigtop_hostname0 bash

hdfs dfs -ls /                          # 列出根目录
hdfs dfs -mkdir -p /user/test           # 创建目录
hdfs dfs -put /etc/hosts /user/test/    # 上传文件
hdfs dfs -get /user/test/hosts /tmp/    # 下载文件
hdfs dfs -du -h /                       # 查看磁盘使用
hdfs dfsadmin -report                   # 查看集群状态
hdfs dfsadmin -safemode get             # 查看安全模式状态
hdfs dfsadmin -safemode leave           # 退出安全模式
```

**客户端 core-site.xml 配置（外部连接）：**

```xml
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://bigtop-hostname0.bigtop.apache.org:8020</value>
  </property>
</configuration>
```

---

### 8.3 YARN / MapReduce

| 项目 | 值 |
|------|-----|
| ResourceManager Web UI | http://bigtop-hostname0.bigtop.apache.org:8088 |
| MapReduce History Server | http://bigtop-hostname1.bigtop.apache.org:19888 |

**常用命令：**

```bash
yarn application -list                              # 查看所有应用
yarn application -list -appStates RUNNING           # 查看运行中应用
yarn application -kill <application_id>             # 终止应用
yarn node -list                                     # 查看节点列表
yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar pi 4 100  # 提交 PI 测试
```

---

### 8.4 ZooKeeper

| 项目 | 值 |
|------|-----|
| 连接地址 | hostname0:2181,hostname1:2181,hostname2:2181 |

**常用命令：**

```bash
# 进入 ZK CLI
/usr/lib/zookeeper/bin/zkCli.sh -server bigtop-hostname0.bigtop.apache.org:2181

ls /          # 列出根节点
stat /        # 查看节点状态

# 四字命令健康检查
echo ruok | nc bigtop-hostname0.bigtop.apache.org 2181   # 返回 imok 为正常
echo stat | nc bigtop-hostname0.bigtop.apache.org 2181   # 查看统计信息
```

---

### 8.5 Hive

| 项目 | 值 |
|------|-----|
| HiveServer2 Web UI | http://bigtop-hostname1.bigtop.apache.org:10002 |
| JDBC URL | jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000/default |
| Metastore Thrift | thrift://bigtop-hostname1.bigtop.apache.org:9083 |
| 用户名 / 密码 | hive / （无密码） |

**Beeline 连接：**

```bash
docker exec -it bigtop_hostname0 beeline \
  -u "jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000/default" -n hive

# 常用 HiveQL
SHOW DATABASES;
CREATE DATABASE test;
USE test;
CREATE TABLE t1 (id INT, name STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',';
LOAD DATA LOCAL INPATH '/tmp/data.csv' INTO TABLE t1;
SELECT * FROM t1 LIMIT 10;
```

**通过 ZooKeeper 发现（ZK-HA 模式）：**

```
jdbc:hive2://hostname0:2181,hostname1:2181,hostname2:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2
```

---

### 8.6 HBase

| 项目 | 值 |
|------|-----|
| HBase Master Web UI | http://bigtop-hostname0.bigtop.apache.org:16010 |
| RegionServer Web UI | http://bigtop-hostname3.bigtop.apache.org:16030 |
| ZooKeeper Quorum | hostname0:2181,hostname1:2181,hostname2:2181 |

**HBase Shell 常用操作：**

```bash
hbase shell

status                                              # 集群状态
list                                                # 列出所有表
create 'test', 'cf1'                                # 创建表
put 'test', 'row1', 'cf1:col1', 'value1'            # 写入数据
get 'test', 'row1'                                  # 读取行
scan 'test', {LIMIT => 10}                          # 扫描限定行数
disable 'test'; drop 'test'                         # 删除表
```

**Java 客户端 hbase-site.xml 配置：**

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

### 8.7 Spark

| 项目 | 值 |
|------|-----|
| Spark History Server | http://bigtop-hostname0.bigtop.apache.org:18081 |
| 推荐运行模式 | YARN |

**提交 Spark 作业：**

```bash
# Cluster 模式（生产推荐）
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --class org.apache.spark.examples.SparkPi \
  /usr/lib/spark/examples/jars/spark-examples_*.jar 100

# Client 模式（调试）
spark-submit --master yarn --deploy-mode client \
  --class org.apache.spark.examples.SparkPi \
  /usr/lib/spark/examples/jars/spark-examples_*.jar 10

# 交互式 Shell
spark-shell --master yarn
pyspark --master yarn
```

> **注意**：Spark 集群统一以 **JDK 8** 运行（YARN NodeManager/容器默认即 JDK8），
> 配套 Iceberg **1.6.1**（JDK8 编译）。与 Flink 侧的版本分叉原因见 §8.7.1 版本说明。

---

### 8.7.1 Iceberg 数据湖

| 项目 | 值 |
|------|-----|
| Warehouse | `hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse` |
| Data 格式 | Apache Iceberg（Parquet 文件 + 元数据） |
| Spark Catalog | `iceberg`（Hadoop Catalog） |
| Spark 集成 | `iceberg-spark-runtime-3.5_2.12-1.6.1.jar`（JDK 8 编译） |
| Flink Catalog | `demoicb`（Hadoop Catalog，同一 Warehouse） |
| Flink 集成 | `iceberg-flink-runtime-1.20-1.11.0.jar`（JDK 17 编译） |

**版本说明（Spark=1.6.1 / Flink=1.11.0 分叉的由来）**：
节点 NodeManager 的容器默认就是 JDK8（class 52），而 Iceberg 1.11 用 JDK17
编译（class 61）。Spark 作业在 YARN 上运行时，executor 反序列化写入器会抛
`UnsupportedClassVersionError: org/apache/iceberg/spark/source/SparkWrite$WriterFactory
... class file version 61.0 ... up to 52.0`，executor 反复启动即崩、表象为
"作业卡住不分配资源"。因此 **Spark 侧统一回退 1.6.1（Iceberg 1.7 起即要求
JDK11+），并保持 `spark-env.sh` 的 `JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk`**。
Flink 的 JobManager/TaskManager 进程本身在 JDK17 上运行，可继续使用
`iceberg-flink-runtime-1.20-1.11.0.jar`（flink 1.20 的 1.6.x runtime 不存在，
1.7.0 起即为 JDK11 编译）。

**Spark 侧说明**：Spark 与 Hive 3.1 客户端存在 `NoSuchFieldError: out`
冲突，故 Spark 采用 **Hadoop Catalog**（不初始化 Hive client，元数据直接
以文件形式存放在 HDFS warehouse）。

**常用操作示例（spark-sql / spark-submit）：**

```sql
-- 查看 catalog
SHOW CATALOGS;

-- 建库建表（分区表）
CREATE DATABASE IF NOT EXISTS iceberg.demo;
USE iceberg.demo;
CREATE TABLE IF NOT EXISTS iceberg.demo.users (
  id INT, name STRING, city STRING, ts TIMESTAMP
) USING iceberg PARTITIONED BY (city);

-- 写入（每次写入产生一个快照）
INSERT INTO iceberg.demo.users VALUES
  (1, 'alice', 'beijing', current_timestamp()),
  (2, 'bob',   'shanghai', current_timestamp());

-- 查询
SELECT city, count(*) FROM iceberg.demo.users GROUP BY city;

-- 查询快照（时间旅行能力基础）
SELECT snapshot_id, committed_at, operation
FROM iceberg.demo.users.snapshots;

-- 数据刷新（MERGE INTO，需要 spark.sql.extensions 已配置）
MERGE INTO iceberg.demo.users t
USING (SELECT 2 AS id, 'bobby' AS name) s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET name = s.name;
```

**命令行执行示例：**

```bash
# 以 hdfs 用户（有 HDFS 写权限）提交
sudo -u hdfs spark-sql --master yarn -e 'SHOW CATALOGS'
sudo -u hdfs spark-sql --master yarn -e 'SELECT * FROM iceberg.demo.users'

# spark-submit 提交 Python/Scala 作业时无需额外配置，catalog 已在
# spark-defaults.conf 中全局声明（iceberg）可直接用 `iceberg.demo.*`。
```

**数据文件位置**：

```bash
sudo -u hdfs hdfs dfs -ls -R /iceberg-warehouse/demo.db/users
# 元数据目录 metadata/（snapshot/manifest）与数据目录 data/（parquet）
```

**Flink 侧验证（Flink 1.20.1 / JDK17 / sql-client）：**

sql-client 的 Catalog 是**会话级**的，且 INSERT 为异步提交——应在同一脚本里
"建 Catalog → 写 → 读"连起来跑（见下）。运行前置：

```bash
# 以 flink 用户执行
docker exec -u flink bigtop_hostname0 bash -c '
  export HADOOP_HOME=/usr/bigtop/current/hadoop-client
  export HADOOP_CONF_DIR=/etc/hadoop/conf
  # 必须导出 HADOOP_CLASSPATH，否则建 HiveCatalog 报
  # java.lang.ClassNotFoundException: org.apache.hadoop.conf.Configuration
  export HADOOP_CLASSPATH=$($HADOOP_HOME/bin/hadoop classpath)
  timeout 360 /usr/lib/flink/bin/sql-client.sh \
    -Dexecution.target=remote -Drest.address=localhost -Drest.port=8081 \
    -Denv.java.opts="--add-opens=java.base/java.lang=ALL-UNNAMED \
       --add-opens=java.base/java.net=ALL-UNNAMED \
       --add-opens=java.base/java.util=ALL-UNNAMED" \
    -f /tmp/flink_test.sql
'
```

```sql
-- /tmp/flink_test.sql（两个 SET 必须放在最前面）
SET 'sql-client.execution.result-mode' = 'tableau';
SET 'execution.runtime-mode' = 'batch';

-- ① Flink ↔ Hive（HiveCatalog + hive connector，不用 hive dialect）
CREATE CATALOG demohive WITH ('type'='hive',
  'hive-conf-dir'='/etc/hive/conf', 'default-database'='default');
USE CATALOG demohive;
SHOW DATABASES;
CREATE TABLE flink_hive_t1 (id INT, name STRING, ts TIMESTAMP(9))  -- 精度必须 (9)
  WITH ('connector' = 'hive');
INSERT INTO flink_hive_t1 VALUES
  (1, 'apple',  TIMESTAMP '2026-09-10 10:00:00'),
  (2, 'banana', TIMESTAMP '2026-09-10 11:00:00');
SELECT id, name, ts FROM flink_hive_t1;   -- → 2 行（apple / banana）

-- ② Flink ↔ Iceberg（与 Spark 同一 warehouse，跨引擎互读）
CREATE CATALOG demoicb WITH ('type'='iceberg', 'catalog-type'='hadoop',
  'warehouse'='hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse');
USE CATALOG demoicb;
SHOW DATABASES;   -- → demo（Spark 侧建的库）
SELECT city, dt, cnt FROM demo.metrics ORDER BY city, dt;   -- → 3 行 Spark 写入的数据
```

**Flink 侧坑与要点**：

- **不要用 Hive dialect**：hive-exec 3.1 的 `SessionState` 构造器会把父加载器强转
  URLClassLoader，JDK17 下直接抛 `ClassCastException`。用默认 dialect + HiveCatalog +
  `WITH ('connector'='hive')` 即可。
- **HiveCatalog 只接受 `timestamp(9)`**：`timestamp(3)` 报
  "HiveCatalog currently only supports timestamp of precision 9"。
- **JDK17 需 `--add-opens`**（java.base 的 java.lang / java.net / java.util，另含
  `sun.nio.ch`、`java.nio`），否则 `InaccessibleObjectException: java.net.URI.string`。
  已在 Ambari `flink-conf` 配置的 `env.java.opts/.jobmanager/.taskmanager` 中固化
  （改的是 desired content，重启自动渲染，勿手改容器内 /etc/flink/conf/flink-conf.yaml）。
- **非交互结果模式**：必须 `SET 'sql-client.execution.result-mode' = 'tableau';`
  （带引号的完整写法），否则 SELECT 无输出。
- **INSERT 是异步作业**：提交后立刻执行的 SELECT 可能读到空集，需等作业 commit
  （作业状态看 http://localhost:8081）。
- Flink 集群拓扑：JobManager（standalonesession）在 **hostname0**（REST 8081 / RPC 6123），
  TaskManager 在 **hostname2**（1 slot），sql-client 在 hostname0 以 `flink` 用户运行。

---

### 8.8 Kafka

| 项目 | 值 |
|------|-----|
| Broker 地址 | bigtop-hostname0.bigtop.apache.org:9092 |
| ZooKeeper 路径 | bigtop-hostname0.bigtop.apache.org:2181/kafka |

**常用操作：**

```bash
# 创建 Topic
kafka-topics.sh --create \
  --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 \
  --replication-factor 1 --partitions 3 --topic test-topic

# 列出 / 查看 Topic
kafka-topics.sh --list --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092
kafka-topics.sh --describe --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 --topic test-topic

# 生产 / 消费消息
kafka-console-producer.sh --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 --topic test-topic
kafka-console-consumer.sh --bootstrap-server bigtop-hostname0.bigtop.apache.org:9092 --topic test-topic --from-beginning
```

---

### 8.9 Ranger

| 项目 | 值 |
|------|-----|
| Admin Web UI | http://bigtop-hostname1.bigtop.apache.org:6080 |
| 管理员账号 / 密码 | admin / Admin1234! |
| MySQL 应用用户 | rangeradmin / Admin1234! |
| MySQL DBA 用户 | root / ambarirootpass |
| ranger 数据库 | ranger |

Ranger 为 HDFS、Hive、HBase、Kafka、YARN 提供细粒度访问控制。

操作路径：登录 → Access Manager → Resource Based Policies → 选择服务 → Add New Policy

**Ambari UI 配置 Ranger 数据库时常见问题：**

Ambari 的 Ranger DB 配置页分两个区域，两套凭证容易混淆：

| 区域 | 用户 | 密码 | 用途 |
|------|------|------|------|
| Ranger DB username（上方） | rangeradmin | Admin1234! | Ranger 服务运行时连接数据库 |
| DBA username（下方） | root | ambarirootpass | Ambari 初始化建表/授权时使用，仅用一次 |

> 若提示 "Connection Failed"，99% 是 DBA 密码填错，确认填 `ambarirootpass` 而非其他密码。

**Advanced ranger-hdfs-policymgr-ssl 配置（SSL 未启用时的处理）：**

Ambari 安装向导中 Advanced 标签页会出现以下 SSL 相关字段，在非 SSL / 非 Kerberos 环境下无需真实配置，按下表填写绕过必填校验即可：

| 配置项 | 填写值 | 说明 |
|--------|--------|------|
| `xasecure.policymgr.clientssl.keystore` | （留空） | 不启用 SSL，无需 keystore 路径 |
| `xasecure.policymgr.clientssl.keystore.credential.file` | `jceks://file{{credential_file}}` | 保持默认值不变 |
| `xasecure.policymgr.clientssl.keystore.password` | `none` | 填 `none` 绕过必填校验，非 SSL 时不生效 |
| `xasecure.policymgr.clientssl.truststore` | （留空） | 不启用 SSL，无需 truststore 路径 |

> `keystore.password` 标红 "This is required" 是 Ambari 的强制校验，填 `none` 即可通过，实际未开启 SSL 时该值不会被使用。如后续需要启用 SSL，再替换为真实 keystore 路径和密码。

---

## 9. 日常运维操作

### 9.1 容器重启后恢复集群

> **⚠️ 第一步必须先判断：容器是"重启（restart）"还是"重建（recreate）"，两者恢复方式完全不同！**

Docker 对这两个动作的处理差异极大：

| 动作 | 命令 | 可写层 | 已装软件（Ambari/Hadoop/MySQL） |
|------|------|--------|--------------------------------|
| **重启** | `docker compose restart` | **保留** | 全部保留，仅需修 hosts/软链接后拉起服务 |
| **重建** | `docker compose up -d`（当容器配置或网络被判为变化时） | **清空为镜像原始状态** | **全部丢失**，必须走 §4 全量重装 |

#### 9.1.0 判定容器是重启还是重建

```bash
cd ambari3

# 方法1：看容器创建时间。重建时 Created 会变成最近一次 up -d 的时刻；
#        正常重启 Created 保持首次创建时间不变
docker compose ps

# 方法2：检查 Ambari Server 是否还在（重建后一定不存在，因为基础镜像不含 Ambari）
docker compose exec bigtop_hostname0 bash -c \
  'test -d /usr/lib/ambari-server && test -x /usr/sbin/ambari-server && echo "KEEP=重启(保留层)" || echo "WIPED=重建(可写层已清空)"'
docker compose exec bigtop_hostname0 rpm -q ambari-server 2>/dev/null || echo "  (ambari-server 未安装)"
```

若输出 `WIPED=重建`，**直接跳到 [9.1.2 重建后全量恢复](#912-重建后全量恢复)**。不要去跑 `setup-hostname.sh`，否则会因 `/var/lib/ambari-server/resources/stacks` 不存在而在 `fix-package-names.sh` 处报错中断。

#### 9.1.1 场景A：容器重启（可写层保留）

容器重启后 IP 会重新分配，`/var/lib/ambari-server/` 等可写层目录恢复为镜像原始状态（软链接、栈 metainfo、包映射被还原），**必须按以下完整流程恢复**，否则 Deploy/Start 会再次出现各种兼容性报错：

```bash
cd ambari3

# 1. 重新启动容器（若已停止；请勿在 IP/网络未变化时无脑 up -d，它可能触发重建）
docker compose restart

# 2. ★ 修复 hostname 解析 + 重建 bigtop 软链接 + 修复包名（必须执行）
#    该脚本同时完成：
#    - 更新 conf/hosts（容器 /etc/hosts 挂载文件）
#    - 重建 /usr/bigtop/3.5.0/usr/lib/ 所有软链接
#    - 重新执行 fix-package-names.sh（清除 ${stack_version}、删除缺包依赖）
#    - 重放 Iceberg 数据湖配置（Spark 侧）
cd scripts
./setup-hostname.sh

# 3. 启动 Ambari Server
cd ..
docker exec bigtop_hostname0 ambari-server start

# 4. 启动所有节点的 Ambari Agent
for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
  docker exec $h ambari-agent start
done

# 5. 通过 Ambari UI 启动全部服务
# 访问 http://localhost:20609 → Actions → Start All
```

> **为什么重启后必须执行 `setup-hostname.sh`？**  
> Docker 容器的可写层在停止后会被保留但重启时某些路径恢复初始状态：
> - `/etc/hosts` — 通过 bind mount 挂载，IP 变化后旧记录导致通信失败
> - `/usr/bigtop/3.5.0/usr/lib/` — 软链接丢失，yarn/hive install 脚本找不到 bin/lib 路径
> - `/var/lib/ambari-server/resources/stacks/` — Stack metainfo 恢复原始状态，`${stack_version}` 占位符重现
> - `/usr/lib/bigtop-select/distro-select` — 包映射恢复，`hadoop-hdfs-dfsrouter` 等条目丢失

#### 9.1.2 场景B：容器重建（可写层被清空 → 全量重装）

**为什么会发生重建？** 最常见的触发点是动了容器的**网络或配置**：
- 对容器所在网络执行了 `docker network rm`（如清理与 compose 网段冲突的旧网络 `ambari3_default`），该网络上的容器被剥离；
- 随后 `docker compose up -d` 发现容器网络/配置与 compose 定义不一致，于是 **Recreate（先删旧容器再建新容器）**，而不是简单 restart；
- 挂载卷（`./ambari-repo`、`../ambarirpm`、`../bigtoprpm`、`conf/hosts`）仍在，但**容器内已安装的一切（Ambari Server/Agent、Hadoop、MySQL 数据）全部清零**。

> **💡 规避原则**：需要清冲突网络时先 `docker compose down` 再删网络，或改用 `docker compose stop/start`；判断 `up -d` 是否会重建，可先 `docker compose config` 对比容器现状。不确定时优先 `docker compose restart`。

重建后恢复 = **全新安装**，按本文 **§4 快速部署（Step 0 ~ Step 7）** 完整重走：

```bash
cd ambari3
docker compose up -d          # Step 1 启动容器（此时确保没有了冲突网络）

cd scripts
./setup.sh                     # Step 2 初始化节点（SSH、SELinux、hosts）
./setup-ambari-repo.sh         # Step 3 构建本地 nginx yum 仓库
cd ..
./scripts/install-ambari-server.sh   # Step 4 安装 Ambari Server + MySQL + 栈注入（全自动）
./scripts/install-ambari-agent.sh    # Step 5 所有节点安装 Agent

# Step 6 通过 Web UI 创建集群（必为人工步骤，见 §5 向导说明）
#   - 4 个节点 FQDN、Stack=BIGTOP 3.5.0、仓库版本=Bigtop-3.5.0.0-1
#   - 组件分配与关键配置见 §5.5 / §5.6

# Step 7 每次 Deploy 失败后执行（幂等）：
./scripts/post-deploy-fixes.sh        # 修完点 Web UI 的 Retry，反复到全部成功
# Deploy 成功后启动全部服务，再：
./scripts/fix-hive.sh                 # Hive 4.0.1 兼容性修复（已在视图重启）

# 其他按需重放：
./scripts/setup-hostname.sh           # 重建软链接/包名/iceberg 重放（幂等，可再跑）
./scripts/setup-nat-forward.sh refresh  # 重建端口转发规则
```

> **时长参考**：Step 1-5 自动部分约 30~60 分钟（主要耗时在每节点 `dnf update` 与冷缓存元数据下载）；Step 6 Web UI 向导需人工 10~30 分钟。

### 9.2 服务启停（Ambari API）

```bash
# 启动指定服务（将 HDFS 替换为目标服务名）
curl -u admin:admin -X PUT \
  -H "X-Requested-By: ambari" \
  -d '{"RequestInfo":{"context":"Start"},"Body":{"ServiceInfo":{"state":"STARTED"}}}' \
  "http://localhost:20609/api/v1/clusters/bigtop-cluster/services/HDFS"

# 停止指定服务
curl -u admin:admin -X PUT \
  -H "X-Requested-By: ambari" \
  -d '{"RequestInfo":{"context":"Stop"},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' \
  "http://localhost:20609/api/v1/clusters/bigtop-cluster/services/HDFS"
```

### 9.3 查看服务日志

```bash
# Ambari Server
docker exec bigtop_hostname0 tail -f /var/log/ambari-server/ambari-server.log

# HDFS NameNode
docker exec bigtop_hostname0 tail -f /var/log/hadoop-hdfs/hadoop-hdfs-namenode-*.log

# YARN ResourceManager
docker exec bigtop_hostname0 tail -f /var/log/hadoop-yarn/yarn-yarn-resourcemanager-*.log

# HiveServer2
docker exec bigtop_hostname0 tail -f /var/log/hive/hiveserver2.log

# Hive Metastore
docker exec bigtop_hostname0 tail -f /var/log/hive/hive-metastore.log

# HBase Master
docker exec bigtop_hostname0 tail -f /var/log/hbase/hbase-hbase-master-*.log

# Kafka
docker exec bigtop_hostname0 tail -f /var/log/kafka/server.log

# Ranger Admin
docker exec bigtop_hostname0 tail -f /usr/lib/ranger-admin/ews/logs/ranger-admin-*.log
```

### 9.4 集群健康检查

```bash
# 验证 ZooKeeper
echo ruok | nc bigtop-hostname0.bigtop.apache.org 2181  # 返回 imok 为正常

# 验证 HDFS
docker exec bigtop_hostname0 hdfs dfsadmin -report

# 验证 YARN
docker exec bigtop_hostname0 su - yarn -s /bin/bash -c 'yarn node -list'

# 运行 MapReduce PI 测试
docker exec bigtop_hostname0 su - hdfs -s /bin/bash -c \
  'yarn jar /usr/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar pi 2 10'

# 验证 Hive
docker exec bigtop_hostname0 su - hive -s /bin/bash -c \
  'beeline -u jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10000 -e "show databases;"'
```

---

## 10. 运维工具（opstools）使用说明

### 10.1 Shell 脚本工具（opstools/ops/）

所有脚本默认连接 `localhost:20609`，集群名 `c1`。根据实际情况修改脚本头部变量后执行。

| 脚本 | 用途 | 用法示例 |
|------|------|----------|
| `health-check.sh` | 集群健康全面检查 | `./health-check.sh` |
| `restart-services.sh` | 重启指定服务 | `./restart-services.sh HDFS` |
| `backup-config.sh` | 备份集群配置 | `./backup-config.sh` |
| `restore-config.sh` | 恢复集群配置 | `./restore-config.sh` |
| `monitor-cluster.sh` | 实时监控集群状态 | `./monitor-cluster.sh` |
| `log-collect.sh` | 收集所有节点日志 | `./log-collect.sh` |
| `clean-cluster.sh` | 清理集群资源 | `./clean-cluster.sh` |
| `verify-install.sh` | 验证安装完整性 | `./verify-install.sh` |

### 10.2 Stack 升级工具（opstools/upgrade/）

```bash
# 查看集群信息
./opstools/upgrade/cluster-info.sh

# 执行 Stack 滚动升级（升级前请务必备份配置）
./opstools/upgrade/upgrade-stack.sh 3.6.0
```

升级脚本会自动：备份配置 → 校验目标版本可用性 → 提交滚动升级请求 → 输出进度监控提示

### 10.3 Python 运维工具（opstools/python/）

需要 Python 3.6+ 及 `requests` 库：

```bash
pip3 install requests

# 常用示例
python3 opstools/python/service-checker.py     # 检查所有服务状态
python3 opstools/python/metrics-collector.py   # 采集集群指标
python3 opstools/python/alert-manager.py       # 查看/管理告警
python3 opstools/python/log-analyzer.py        # 分析日志
python3 opstools/python/config-validator.py    # 校验配置
python3 opstools/python/performance-test.py    # 性能基准测试
python3 opstools/python/cluster-scaler.py      # 集群扩缩容辅助
python3 opstools/python/backup-restore.py      # 备份/恢复操作
```

---

## 11. 已知问题与修复方案

### 11.1 Hive 4.0.1 兼容性问题（部署后必须执行修复）

Hive 4.0.1 与 Ambari 3.1.0 存在 6 个已知兼容性问题，部署完成后必须运行修复脚本：

```bash
cd ambari3
docker compose exec bigtop_hostname0 bash < scripts/fix-hive.sh
```

修复后在 Ambari UI 中对 Hive 服务执行 **Restart**。

**问题详情：**

| # | 问题 | 现象 | 修复方式 |
|---|------|------|----------|
| 1 | `hive.exec.post.hooks` 值为空格 | HiveServer2 启动时抛 ClassNotFoundException | 将 hive-site.xml 中 `<value> </value>` 替换为 `<value></value>` |
| 2 | `auth=noSasl` 大小写不兼容 | Ambari 健康检查失败，触发重启循环 | 将 hive_check.py 中 `auth=noSasl` 改为 `auth=none` |
| 3 | Metastore schema 未初始化 | Metastore 启动后立即崩溃 | 执行 `hive-schema-4.0.0.mysql.sql` 初始化 |
| 4 | HDFS warehouse 目录权限 | 查询失败、Permission denied | 创建 `/warehouse/tablespace` 并授权 hive 用户 |
| 5 | PID 文件不匹配 | Ambari 认为服务未运行 | 清理过期 PID 文件 |
| 6 | `sys.db.created` 标记文件缺失 | Ambari Sys DB 告警持续 | 创建 `/etc/hive/sys.db.created` 空文件 |

**手动诊断 Hive 问题：**

```bash
# 查看 HiveServer2 日志
docker exec bigtop_hostname0 tail -100 /var/log/hive/hiveserver2.log

# 检查 Metastore schema
docker exec bigtop_hostname0 mysql -uhive -phive hive -e "SELECT * FROM VERSION" 2>&1

# 检查 Metastore 进程
docker exec bigtop_hostname0 ps -ef | grep -E "metastore|hiveserver2"
```

### 11.2 容器重启后 hostname 解析失效

容器重启后 IP 变化但 hosts 记录未更新，导致节点间通信失败。

```bash
cd ambari3/scripts
./setup-hostname.sh
```

### 11.3 HBase RegionServer 无法启动

按以下顺序排查：

```bash
# 1. 检查 ZooKeeper 是否正常
echo ruok | nc bigtop-hostname0.bigtop.apache.org 2181

# 2. 查看 HBase Master 日志
docker exec bigtop_hostname0 tail -50 /var/log/hbase/hbase-hbase-master-bigtop_hostname0.log

# 3. 检查 HDFS /hbase 目录权限
docker exec bigtop_hostname0 hdfs dfs -ls /hbase
# 应为 hbase:hadoop 所有

# 4. 检查容器 /etc/hosts 解析
docker exec bigtop_hostname1 cat /etc/hosts
```

### 11.4 Nginx 仓库服务停止

容器重启后 nginx 不会自动恢复：

```bash
docker exec bigtop_hostname0 systemctl start nginx
# 或重新运行：
cd ambari3/scripts && ./setup-ambari-repo.sh
```

### 11.5 Deploy 安装阶段常见失败汇总

以下问题在每次 Deploy 时可能出现，统一使用 `post-deploy-fixes.sh` 处理：

```bash
cd ambari3 && ./scripts/post-deploy-fixes.sh
```

**11.5.1 `${stack_version}` 占位符导致包名找不到（HDFS/DataNode、YARN/TSV2、FLINK 全挂）**

- 现象（同一根因的三个变体）：
  - `No package found for hadoop_${stack_version}(expected name: hadoop_3_5_0)`——DataNode/HDFS Install（hostname2 等）
  - `No package found for hadoop_${stack_version}-yarn(expected name: hadoop_3_5_0-yarn)`——Timeline Service V2（APP_TIMELINE_SERVER，hostname1）
  - `No package found for flink_${stack_version}(expected name: flink_3_5_0)`——Flink History Server（hostname0）
- 原因（三条，都会让 Agent 用错包名）：
  1. **Server 端 3.2.0 父栈未清理**：Agent 通过继承链加载 3.2.0 父栈的 metainfo，该基栈是 RPM 原始文件，包名仍是 `hadoop_${stack_version}`。3.3.0/3.4.0/3.5.0 已干净，因此只修 3.5.0 是无效的。自研安装流程漏跑 `fix-package-names.sh` 时必然复发。
  2. **ambari-server 内存里的栈定义是启动时加载的**：`AmbariMetaInfo` 只在本进程启动时读一次磁盘，运行中改 metainfo.xml **不会热加载**。只改磁盘文件不 `ambari-server restart`，Server 生成的命令 `package_list` 仍是旧占位符，Agent 照旧 `No package found`（已确认：重启后新请求 `execution_command` 里 `package_list` 变干净，可装成功）。
  3. **Agent cache 缓存了修复前的旧栈**：即使 Server 端已修复，节点 `/var/lib/ambari-agent/cache/stacks/BIGTOP/{3.2.0,3.3.0}` 里缓存的旧 metainfo 不会自动失效——必须**删除缓存 + 重启 agent**强制重新下发，仅重放脚本不删缓存无效。
- 修复（一条命令，容器重启后跑 `cd ambari3/scripts && ./setup-hostname.sh` 即自动完成）：`setup-hostname.sh` 已内置"重放 `fix-package-names.sh` → 重放 flink 栈补丁 → 重启 ambari-server → 清 4 节点 Agent 缓存 → 重启 agent → 自校验占位符零残留"；全量重装流程 `install-ambari-server-script.sh` 也已在 `ambari-server start` 之前执行 `fix-package-names.sh`（首启即加载修复后的栈，无需重启）；Deploy 失败后跑 `post-deploy-fixes.sh`（Fix 3d 重放 fix-package-names + Fix 7 重启 Server 保证 Retry 生成干净命令）。也可手动执行：
  ```bash
  cd ambari3/scripts
  docker compose cp fix-package-names.sh bigtop_hostname0:/root/
  docker compose exec bigtop_hostname0 bash /root/fix-package-names.sh
  # ⚠️ 关键第一步：重启 ambari-server 重载栈定义到内存（漏掉则 Retry 仍失败）
  docker compose exec bigtop_hostname0 ambari-server restart
  # 然后删除所有节点 Agent 缓存并重启 agent（必须做，否则旧缓存仍生效）
  for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
    docker exec $h bash -c \
      'rm -rf /var/lib/ambari-agent/cache/stacks/BIGTOP/3.2.0 /var/lib/ambari-agent/cache/stacks/BIGTOP/3.3.0
       find /var/lib/ambari-agent/cache/stacks/BIGTOP -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
       ambari-agent restart'
  done
  # Web UI 对本次失败任务点 Retry（必须点 Retry 重新生成命令，
  # 不要沿用旧失败显示；再次失败且是同样 No package found 时，先 Abort 再重跑)
  ```
- 干扰项：`grep -rl "stack_version" .../package/scripts/*.py` 有命中属于**正常现象**——
  `params_linux.py` 等里的 `stack_version_formatted` 是 Python 变量名（运行时取值），
  不是包名占位符。判定只看 metainfo.xml 与命令的 `package_list`。
- 验证：Agent 缓存重新下发后确认无占位符
  ```bash
  docker exec bigtop_hostname2 bash -c \
    'grep -rl "stack_version" /var/lib/ambari-agent/cache/stacks/BIGTOP/ 2>/dev/null | wc -l'
  # 输出 0 即通过
  ```

**11.5.2 `snappy-devel` 安装失败（DataNode Install）**

- 现象：`Error: Unable to find a match: snappy-devel`
- 原因：`snappy-devel` 在 el8 上需要 PowerTools/CRB 仓库，且父 stack metainfo 残留了该依赖
- 修复：`fix-package-names.sh` 会删除父 stack 中该依赖；同时确保节点开启 PowerTools：
  ```bash
  for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
    docker exec $h dnf config-manager --set-enabled powertools 2>/dev/null || \
      docker exec $h dnf config-manager --set-enabled crb 2>/dev/null || true
    docker exec $h dnf install -y snappy-devel 2>/dev/null || true
  done
  ```

**11.5.3 `ambari-infra-solr` / `ambari-infra-solr-client` 安装失败（INFRA_SOLR / Ranger Admin）**

- 现象：`Error: Unable to find a match: ambari-infra-solr-client`（或 `... ambari-infra-solr`）
- 原因：这两个是 Ambari 自带包（非 Bigtop 组件），2019 年 el7 时代构建，本地仓库未收录且 el8 的 rpm/dnf 拒绝其旧头（`does not verify: no digest`）
- 修复：`fix-package-names.sh` **不再删除这些依赖**，而是确保真实 RPM 已收录到本地仓库 `/var/repo/ambari`：
  1. 本地已有 `.el8` 重打包版本则跳过；
  2. 否则从公共镜像下载原包到 `/tmp/ah`，用 `rebuild-ambari-infra-rpm.sh` 重打包（内容与原包字节一致，仅重建头信息修复 el8 digest 兼容），再放回仓库并 `createrepo --update`；
  3. 各节点 `dnf -y install ambari-infra-solr ambari-infra-solr-client` 即可成功，`/usr/lib/ambari-infra-solr-client/solrCloudCli.sh` 由真实包提供（INFRA_SOLR_CLIENT configure 的 `StaticFile` 依赖它）
- 手动触发：重跑 `fix-package-names.sh` 或 `setup-hostname.sh`；重打包脚本可单独执行：`rebuild-ambari-infra-rpm.sh ambari-infra-solr|ambari-infra-solr-client /tmp/ah /var/repo/ambari`

**11.5.4 `/usr/bigtop/current/xxx/bin` 目录不存在（MapReduce2/YARN Client Install）**

- 现象：`parent directory /usr/bigtop/current/hadoop-yarn-client/bin doesn't exist`
- 原因：容器重启后 `/usr/bigtop/3.5.0/usr/lib/` 软链接丢失
- 修复：`setup-hostname.sh` 已自动重建；也可手动：
  ```bash
  for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
    docker exec $h bash -c "
      mkdir -p /usr/bigtop/3.5.0/usr/lib
      for pkg in hadoop hadoop-hdfs hadoop-yarn hadoop-mapreduce hbase hive zookeeper kafka spark tez; do
        [ -d /usr/lib/\${pkg} ] && ln -sfn /usr/lib/\${pkg} /usr/bigtop/3.5.0/usr/lib/\${pkg} || true
      done
      for pkg in \$(ls /usr/lib/ | grep ranger); do
        ln -sfn /usr/lib/\${pkg} /usr/bigtop/3.5.0/usr/lib/\${pkg} 2>/dev/null || true
      done
    "
  done
  ```

**11.5.5 `hive-client/lib/mysql-connector-java.jar` 复制失败（Hive Client Install）**

- 现象：`cp: cannot create regular file '/usr/bigtop/current/hive-client/lib/mysql-connector-java.jar': No such file or directory`
- 原因：同 11.5.4，`hive-client` 软链接丢失
- 修复：同 11.5.4

**11.5.6 `hadoop-hdfs-dfsrouter is not supported`（Router Install）**

- 现象：`The package hadoop-hdfs-dfsrouter is not supported by this version of the stack-select tool.`
- 原因：容器重启后 `distro-select` 恢复原始状态，缺少 `hadoop-hdfs-dfsrouter` 映射条目
- 修复：`fix-package-names.sh` 已处理，执行 `setup-hostname.sh` 自动补入

**11.5.7 JDK 未安装导致 before-ANY hook 失败**

- 现象：`Unable to access /usr/lib/jvm/java-1.8.0-openjdk/bin/java`，所有 Install 任务连锁报错
- 原因：hostname2/hostname3 为纯 Agent 节点，JDK 未安装
- 修复：`post-deploy-fixes.sh` 的 Fix 3c 自动检测并安装；也可手动：
  ```bash
  for h in bigtop_hostname2 bigtop_hostname3; do
    docker exec $h dnf install -y java-17-openjdk-devel java-1.8.0-openjdk-devel
  done
  ```

**11.5.8 Ranger Tagsync 凭证文件创建失败**

- 现象：`Could not find or load main class org.apache.ranger.credentialapi.buildks`
- 原因：**两层**软链接缺失：`/usr/bigtop/3.5.0/usr/lib/ranger-tagsync`（中间层）+ `/usr/bigtop/current/ranger-tagsync`（顶层，后装包常漏）。启动时类路径 `/usr/bigtop/current/ranger-tagsync/lib/*` 悬空即报此错；buildks 实际位于 `/usr/lib/ranger-tagsync/lib/credentialbuilder-2.7.0.jar`
- 修复：`post-deploy-fixes.sh` Fix 3e 已同时重建两层；也可手动：
  ```bash
  for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
    docker exec $h bash -c "
      for pkg in \$(ls /usr/lib/ | grep ranger); do
        ln -sfn /usr/lib/\${pkg} /usr/bigtop/3.5.0/usr/lib/\${pkg}
        ln -sfn /usr/bigtop/3.5.0/usr/lib/\${pkg} /usr/bigtop/current/\${pkg}
      done
    "
  done
  ```
- 验证：`docker exec bigtop_hostname3 java -cp "/usr/bigtop/current/ranger-tagsync/lib/*" org.apache.ranger.credentialapi.buildks -help` 输出 usage 即通过

**11.5.9 EclipseLink 拒绝 stack_id=0（VDF 上传报 Server Error）**

- 现象：`Null or zero primary key encountered in StackEntity{id=0}`
- 原因：MySQL INSERT IGNORE 分配了 id=0 给 BIGTOP 3.5.0，EclipseLink JPA 把 0 当 null 拒绝
- 修复：`insert-repo-version.py` 已自动检测并修正为 id=10；`post-deploy-fixes.sh` Fix 3 也会处理

**11.5.10 `Ambari Metrics (AMS)` 安装失败**

- 现象：`Error: Unable to find a match: ambari-metrics-monitor`
- 原因：AMS 包（`ambari-metrics-*`）属于 Ambari 内部包，未收录到本地仓库
- 修复：**在安装向导的服务选择页取消勾选 Ambari Metrics 服务**，不安装该服务

**11.5.11 `ranger-hdfs-plugin` 未安装（NameNode Install 失败）**

- 现象：`/usr/bigtop/3.5.0/usr/lib/hadoop/../ranger-hdfs-plugin/ranger_credential_helper.py: No such file or directory`，NameNode 启动失败
- 原因：ranger-hdfs-plugin 属于被向导“分光”的隐藏依赖，**4 节点全没装**（其它 ranger-* 包在 RANGER/RANGER_KMS Install 时装过）
- 修复：本地仓库已有 `ranger-hdfs-plugin-2.7.0-1.el8.x86_64.rpm`，全节点安装后重建软链：
  ```bash
  for h in bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; do
    docker exec $h dnf --disablerepo="*" --enablerepo=ambari install -y ranger-hdfs-plugin
    docker exec $h bash -c "rm -f /usr/bigtop/3.5.0/usr/lib/ranger-hdfs-plugin /usr/bigtop/current/ranger-hdfs-plugin
                            ln -sfn /usr/lib/ranger-hdfs-plugin /usr/bigtop/3.5.0/usr/lib/ranger-hdfs-plugin
                            ln -sfn /usr/bigtop/3.5.0/usr/lib/ranger-hdfs-plugin /usr/bigtop/current/ranger-hdfs-plugin"
  done
  ```
- 验证：`readlink -f /usr/bigtop/current/ranger-hdfs-plugin` 应指向 `/usr/lib/ranger-hdfs-plugin`

**11.5.12 Hive metastore 崩溃（NoSuchMethodError: HadoopMetrics2Reporter.forRegistry）**

- 现象：Metastore 每次启动即崩（`hivemetastore.log` 报 `NoSuchMethodError`），9083 从不监听；HS2 连锁报 `ZooKeeper node /hiveserver2 is not ready`，Hive 服务整体起不来
- 原因（两个叠加）：
  1. `hivemetastore-site.xml` 里 `hive.metastore.metrics.enabled=true` **覆盖**了 hive-site.xml 里的 `false`（metastore 配置按 hive-site → hivemetastore-site 顺序加载，后者胜出），只改 hive-site 不生效
  2. 更关键：`hive.service.metrics.reporter=HADOOP2` 才是触发开关——Hive 4.0.1 的 `Metrics.init` 会构造 `HadoopMetrics2Reporter`，但该依赖 jar 是原生 `com.codahale` 签名，与 Hive 内部阴影包 `org.apache.hive.com.codahale` 不匹配，一构造即崩
- 修复（改 Ambari `hivemetastore-site` 配置类型，不是 hive-site）：
  ```bash
  # 在容器 bigtop_hostname0 内（脚本自动继承当前 desired_config，无需手填 base tag）
  docker compose cp scripts/ambari-cfg.py bigtop_hostname0:/tmp/
  docker exec bigtop_hostname0 bash -c 'python3 /tmp/ambari-cfg.py hivemetastore-site auto \
    hive.metastore.metrics.enabled=false hive.service.metrics.reporter=JMX'
  # 然后对 HIVE 服务 STOP → START（START 才会重新渲染 /etc/hive/conf/hivemetastore-site.xml）
  ```
  也可直接编辑 `/etc/hive/conf/hivemetastore-site.xml`（等 START 重渲染会覆盖，二选一）
- 验证：`ss -tlnp | grep 9083` 有监听；`hivemetastore.log` 无 NoSuchMethodError；HS2 在 ZK `/hiveserver2` 注册

**11.6 容器被"重建"而非"重启"导致集群全量丢失**

- 现象：`docker compose up -d` 后 4 个容器 `Created` 时间全部更新；`/usr/lib/ambari-server`、`/var/lib/mysql` 均不存在；`rpm -qa | grep -i ambari` 无输出；此时跑 `setup-hostname.sh` 直接报 `.../stacks/BIGTOP/3.5.0/services/HDFS/metainfo.xml: No such file or directory`
- 原因：为清理与 compose 网段（172.19.0.0/24）冲突的旧网络 `ambari3_default`（占用 172.19.0.0/16）执行了 `docker network rm ambari3_default`，该网络上的容器被剥离；随后 `docker compose up -d` 因容器网络/配置与 compose 定义不一致触发 **Recreate**（并非 restart），可写层清空。bind mount 卷（RPM 仓库、hosts）仍在，但已装软件全部丢失
- 修复：**无法恢复已装软件，只能全量重装**，见 §9.1.2（场景B：重建后全量恢复）与 §4 快速部署
- 规避：
  - 不要对在使用中的网络执行 `docker network rm`；清理冲突网络前先 `docker compose down`
  - 拿不准时用 `docker compose restart`（保层）而不是 `up -d`
  - 大动作前用 §9.1.0 的方法确认当前容器是"重启态"还是"重建态"

**11.7 bash 脚本"反斜杠续行内夹注释"语法坑**

- 现象：执行 `setup.sh` 报 `未预期的符号 '||' 附近有语法错误`；执行 `install-ambari-server-script.sh` 时中途报 `sed: no input files` 后脚本在 `set -e` 下提前退出（Ambari Server 未启动、repo_version 未注入）
- 原因：在 `\` 续行中间插入 `# >>> 注释` 行会**中断续行**——bash 只把注释之前的命令接续，注释后的行（如 `-e`、`||`）被当成新的普通命令执行，导致语法错误或命令错乱
- 修复：把说明注释移到续行块的**之前或之后**。已修复 `setup.sh`（powertools 使能段）与 `install-ambari-server-script.sh`（distro-select sed 段）
- 排查命令（找出"上一行以 \ 结尾、本行是注释"的位置）：
  ```bash
  awk 'prev ~ /\\$/{ c=$0; gsub(/^[ \t]+/,"",c); if (c ~ /^#/) print FILENAME": line "FNR } { prev=$0 }' scripts/*.sh
  ```

**11.8 MySQL root 密码与 Ambari DDL 的幂等性（重装重跑时暴露）**

- 现象A：数据库被重建后重跑 `install-ambari-server-script.sh`，后续步骤 `mysql -uroot -pambarirootpass` 报 `Access denied`（root 仍停留在 `--initialize-insecure` 产生的空密码）
  - 原因：`mysqld --initialize-insecure` 已创建 root@localhost（空密码），`CREATE USER IF NOT EXISTS 'root'@... BY 'ambarirootpass'` 对**已存在用户不生效**
  - 修复：SQL 块对每个 root host 追加 `ALTER USER ... IDENTIFIED WITH mysql_native_password BY 'ambarirootpass';`（含 localhost、%.bigtop.apache.org、172.19.0.% 三个 host）。已修复
- 现象B：重复导入 `Ambari-DDL-MySQL-CREATE.sql` 报错（表已存在）导致脚本中断
  - 修复：导入前先 `SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='ambari'`，表数 `< 2` 才导入；否则跳过。已修复

**11.9 Spark YARN executor 抛 UnsupportedClassVersionError（Iceberg 1.11 vs JDK8 容器）**

- 现象：Spark 在 YARN 上跑 Iceberg 写入，作业长期停在 "ACCEPTED / Resource request" 不复位；
  executor 日志（把容器调小后可见）露真因：
  `UnsupportedClassVersionError: org/apache/iceberg/spark/source/SparkWrite$WriterFactory has
  been compiled by a more recent version of the Java Runtime (class file version 61.0), this
  version of the Java Runtime only recognizes class file versions up to 52.0`
- 原因：YARN NodeManager/容器是 **JDK8（class 52）**，而 iceberg 1.11.0 用 JDK17 编译（class 61）；
  driver 端 spark-env 即使切 JDK17，executor 仍在 NM 容器的 JDK8 里反序列化写入器即崩。
- 修复：Spark 侧回退 `iceberg-spark-runtime-3.5_2.12-1.6.1.jar`（JDK8 编译，属主 hive:spark，
  已部署 hostname0/1/3 的 /usr/lib/spark/jars/ 并删除 1.11.0），`spark-env.sh` 保持
  `JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk`（Ambari desired tag `jdk8v2`）。
- 关联陷阱（Flink 侧 / JDK17 + Hive 3.1）：Hive dialect 报 AppClassLoader→URLClassLoader
  ClassCastException；HiveCatalog 拒绝非 (9) 精度 timestamp；需 `--add-opens` 打开 java.base/java.net
  等——详见 §8.7.1 "Flink 侧坑与要点"。

---

## 12. 安全凭证速查

> **安全提示**：以下密码为开发/测试环境默认值，生产部署前请修改所有密码。

| 服务 | 用户名 | 密码 | 备注 |
|------|--------|------|------|
| Ambari UI | admin | admin | Web 管理界面 |
| MySQL root | root | ambarirootpass | 数据库管理员 |
| MySQL ambari | ambari | ambari | Ambari 元数据库 |
| MySQL hive | hive | hive | Hive 元数据库 |
| MySQL ranger | ranger | ranger | Ranger 数据库（内部用户） |
| MySQL rangeradmin | rangeradmin | Admin1234! | Ranger DB 应用用户（Ambari UI 填写） |
| Ranger Admin UI | admin | Admin1234! | 权限管理界面 |
| Ranger Ambari 用户 | amb_ranger_admin | Admin1234! | Ranger-Ambari 集成 |
| Ranger Usersync | — | Admin1234! | 用户同步 |
| Ranger Tagsync | — | Admin1234! | 标签同步 |
| Ranger KMS | keyadmin | Admin1234! | 密钥管理 |
| Grafana | admin | admin123 | 监控仪表板（如启用） |

---

## 13. 端口速查表

| 服务 | 宿主机端口 | 目标节点 | 容器端口 | 访问方式 |
|------|-----------|---------|---------|----------|
| **Ambari UI** | 20609（宿主机）/ 8080（容器内） | hostname0 | 8080 | Web 浏览器 |
| HDFS NameNode UI | 50070 | hostname0 | 50070 | Web 浏览器 |
| HDFS NameNode RPC | 8020 | hostname0 | 8020 | Hadoop 客户端 |
| HDFS SecondaryNN UI | 50090 | hostname1 | 50090 | Web 浏览器 |
| YARN ResourceManager UI | 8088 | hostname0 | 8088 | Web 浏览器 |
| YARN RM RPC | 8050 | hostname0 | 8050 | 作业提交客户端 |
| MR History Server | 19888 | hostname1 | 19888 | Web 浏览器 |
| HBase Master UI | 16010 | hostname0 | 16010 | Web 浏览器 |
| HBase Master RPC | 16000 | hostname0 | 16000 | HBase 客户端 |
| HBase RegionServer UI | 16030 | hostname3 | 16030 | Web 浏览器 |
| HiveServer2 JDBC | 10000 | hostname1 | 10000 | JDBC/Beeline |
| HiveServer2 UI | 10002 | hostname1 | 10002 | Web 浏览器 |
| Hive Metastore | 9083 | hostname1 | 9083 | Thrift 协议 |
| ZooKeeper Client (h0) | **21810**（勿用 2181） | hostname0 | 2181 | ZK 客户端 |
| ZooKeeper Client (h1) | 12181 | hostname1 | 2181 | ZK 客户端 |
| ZooKeeper Client (h2) | 22181 | hostname2 | 2181 | ZK 客户端 |
| ZooKeeper 仲裁 (2888/3888) | 不对外转发 | — | 容器内 | 集群内部使用 |
| Kafka Broker | 9092 | hostname0 | 9092 | Kafka 客户端 |
| **Ranger Admin UI** | 6080 | hostname1 | 6080 | Web 浏览器 |
| Ranger Usersync | 6083 | hostname1 | 6083 | TCP |
| Spark History Server | 18081 | hostname0 | 18081 | Web 浏览器 |
| Flink History Server | 8082 | hostname0 | 8082 | Web 浏览器 |
| Flink JobManager Web UI | 8081 | hostname0 | 8081 | Web 浏览器 |
| Flink JobManager RPC | 6123 | hostname0 | 6123 | 作业提交客户端 (`-m`) |
| Tez UI（通过 YARN） | 8088/tez-ui | hostname0 | HTTP | Web 浏览器 |
| MySQL | 3306 | hostname1 | 3306 | 容器内部 |
| Nginx（Yum 仓库） | 80 | 容器内部 | HTTP | 容器内部 |

> **ZK 端口重要提醒**：ZK 仲裁端口 2888（Follower 通信）与 3888（Leader 选举）**绝不能 DNAT 对外**，
> 否则会破坏集群仲裁并劫持容器间同端口流量。hostname0 的 ZK 客户端对外访问请使用宿主机 **21810**，
> 而非容器内默认的 2181。

---

## 14. 常见问题排查（FAQ）

**Q: 局域网机器访问 HDFS 报 "Connection refused"**  
A: 确认宿主机已配置 iptables 端口转发，且目标机器 `/etc/hosts` 中的域名指向宿主机 IP 而非容器 IP（172.19.x.x 仅宿主机可达）。

**Q: 节点注册向导中节点一直不显示 Registered**  
A: 检查 Ambari Agent 状态和 server 地址配置：
```bash
docker exec bigtop_hostname1 ambari-agent status
docker exec bigtop_hostname1 grep hostname /etc/ambari-agent/conf/ambari-agent.ini
```

**Q: Hive 查询报 "Metastore connection failed"**  
```bash
# 检查 Metastore 端口
docker exec bigtop_hostname0 netstat -tlnp | grep 9083
# 查看日志
docker exec bigtop_hostname0 tail -50 /var/log/hive/hive-metastore.log
```

**Q: Spark 作业提交失败**  
确认 YARN 和 HDFS 都已启动，且 Spark 事件日志目录存在：
```bash
docker exec bigtop_hostname0 hdfs dfs -ls /spark-history
# 若不存在则创建：
docker exec bigtop_hostname0 hdfs dfs -mkdir -p /spark-history
docker exec bigtop_hostname0 hdfs dfs -chmod 777 /spark-history
```

**Q: Kafka 消费者连接超时**  
Kafka broker 返回的地址是容器内域名，局域网机器访问时需在 `/etc/hosts` 中将 `bigtop-hostname0.bigtop.apache.org` 解析到宿主机 IP，且宿主机需做 9092 端口转发。

**Q: 容器重启后服务不自动启动**  
容器基于 systemd，Hadoop 服务通过 Ambari 管理，不会随系统自启。需手动启动 Server 和 Agent 后，通过 Ambari UI 启动服务，或在 Ambari UI 中开启 **Service Auto Start**（Cluster Admin → Service Auto Start）。

**Q: Ambari 告警 "Sys DB status" 持续红色**  
执行 Hive 修复脚本后该告警会消除：
```bash
docker compose exec bigtop_hostname0 bash < ambari3/scripts/fix-hive.sh
```

**Q: Deploy 安装时各种包找不到 / 路径不存在**  
执行一键修复脚本后再 Retry：
```bash
cd ambari3 && ./scripts/post-deploy-fixes.sh
```

**Q: 容器重启后服务启动失败，和首次部署一样的错误**  
容器重启后必须先执行：
```bash
cd ambari3/scripts && ./setup-hostname.sh
```
该脚本会同时修复 hosts、重建软链接、修复包名，缺一不可。


**Q: 安装时报包找不到**  
确认 nginx 仓库服务正在运行：
```bash
docker exec bigtop_hostname0 systemctl status nginx
curl http://bigtop-hostname0.bigtop.apache.org/ | grep hadoop
```

---

*© HodoopForge Project — 让 Hadoop 集群部署从"难题"变为"简单"*
