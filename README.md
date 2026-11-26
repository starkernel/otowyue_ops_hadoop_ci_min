
HodoopForge —— 专为现代Hadoop集群量身打造的一站式部署与管理平台

简介
HodoopForge 是一款企业增强版Hadoop集群管理软件，专为解决市面上 Apache Ambari 3.x 与 Apache Bigtop 3.5.0及以上版本 之间联调困难、兼容性差、部署复杂等问题而生。

它在深度优化 Apache Ambari 的基础上，完美集成并增强了 Bigtop 的打包与组件管理能力，同时对相关 Stack、服务定义、元数据、部署脚本等进行了专项定制与重构，填补了当前开源生态中这一关键空白。

无论您是构建全新大数据平台，还是迁移/升级现有Hadoop集群，HodoopForge 都能让部署更简单、管理更高效、运维更稳定。

核心价值与功能亮点

无缝集成与兼容优化：针对 Ambari 3.x 与 Bigtop 3.5+ 的版本不匹配、Stack 加载不匹配、组件依赖冲突等问题进行专项修复与优化，支持一键式或向导式部署最新 Bigtop 组件（Hadoop、Hive、Spark、HBase、Kafka、Flink 等）。

增强的部署能力：提供改进的 Management Pack（MPack）、自动化脚本、离线/在线安装模式，支持多 Linux 发行版（CentOS/RHEL、Ubuntu、Rocky Linux 等），极大降低手动调优门槛。

现代化集群管理：继承并优化 Ambari 的 Web UI 界面，实现集群 provisioning（置备）、配置管理、服务监控、告警、滚动升级、高可用（HA）配置等全生命周期管理。

专项优化点：

改进 Bigtop Stack 的兼容性与包命名规则
增强服务发现、依赖解析与健康检查机制
优化性能调优模板与资源分配策略
支持自定义扩展 Stack，方便集成第三方或自研组件

易用性提升：简化安装流程、提供详细的日志诊断工具、备份恢复机制，以及与 Ansible/Puppet 等配置管理工具的更好协同。
安全与可扩展：内置 Kerberos、Ranger 等安全集成支持，预留插件架构，方便未来扩展到云原生或 Kubernetes 环境。

适用场景

需要使用最新 Apache Bigtop 版本但苦于 Ambari 兼容问题的团队
追求纯开源、无厂商锁定的 Hadoop 生产环境
从 Cloudera/Hortonworks 等商业发行版迁移到纯社区栈的用户
大数据平台运维团队，希望降低部署与日常管理复杂度的组织

技术定位

HodoopForge 不是简单地“打包” Ambari 和 Bigtop，而是对其核心机制进行了针对性重构与增强。它延续了 Ambari 成熟的 Web 管理理念，同时注入 Bigtop 的最新组件能力，成为连接“老工具”与“新生态”的桥梁。
口号：

“锻造稳定 · 连接未来”

—— HodoopForge，让 Hadoop 集群部署从“难题”变为“简单”。



## 当前部署状态（2026-11-26）

- **架构总览**：[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 4 容器拓扑、Kerberos 认证链路、HA、端口、回滚
- **当前状态**：[`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md) — 单一事实源
- **Kerberos**：[`docs/KERBEROS_ENABLEMENT.md`](docs/KERBEROS_ENABLEMENT.md)（数据面） + [`docs/KERBEROS_GUARD.md`](docs/KERBEROS_GUARD.md)（防呆守护）
- **Ambari**：`security_type=KERBEROS`；`ambari-agent` 由 guard 锁定，禁止从 Ambari 启停数据面服务
- **同事参考包**：[`ambarirpm/hodoopforge-handbook-2026-11-26/`](ambarirpm/hodoopforge-handbook-2026-11-26/)

## 文档与数据湖地图

[![CI](https://github.com/starkernel/otowyue_ops_hadoop/actions/workflows/ci.yml/badge.svg)](https://github.com/starkernel/otowyue_ops_hadoop/actions/workflows/ci.yml)

- **测试策略**：[`docs/TEST_STRATEGY.md`](docs/TEST_STRATEGY.md) — 分层、用例目录、准入/退出标准
- **CI/CD**：[`docs/CI_CD.md`](docs/CI_CD.md) — GitHub Actions、JUnit、Allure、Live smoke
- **文档索引**：[`docs/INDEX.md`](docs/INDEX.md)
- **架构总览**：[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **交互地图**：[`docs/lake-map.html`](docs/lake-map.html) — 组件、HA、端口、指标、命令，可搜索/筛选/点击查看
- **当前状态（单一事实源）**：[`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md)
- **快照后恢复**：[`docs/POST_SNAPSHOT_RUNBOOK.md`](docs/POST_SNAPSHOT_RUNBOOK.md)
- **运维自动化**：[`docs/OPERATIONS_AUTOMATION.md`](docs/OPERATIONS_AUTOMATION.md)
- **Prometheus 监控**：[`docs/MONITORING_PROMETHEUS.md`](docs/MONITORING_PROMETHEUS.md)
- **Warehouse 对齐**：[`docs/WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md`](docs/WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md)
- **Kafka 外部访问**：[`docs/KAFKA_EXTERNAL_ACCESS.md`](docs/KAFKA_EXTERNAL_ACCESS.md)
- **Kerberos 防呆**：[`docs/KERBEROS_GUARD.md`](docs/KERBEROS_GUARD.md)

### Software Name
**HodoopForge** 

**Tagline / Slogan**:  
**"Forge Stability. Connect the Future."**


**HodoopForge** — A Purpose-Built Platform for Modern Hadoop Cluster Deployment and Management

#### Overview
HodoopForge is an open-source (with optional enterprise edition) Hadoop cluster management solution specifically designed to bridge the compatibility and integration gaps between **Apache Ambari 3.x** and **Apache Bigtop 3.5.0 and above**.

By deeply optimizing Apache Ambari and enhancing its integration with the latest Bigtop packaging and components, HodoopForge provides a unified, reliable, and production-ready platform for deploying and managing pure open-source Hadoop ecosystems. It addresses common pain points such as stack loading failures, component dependency conflicts, packaging inconsistencies, and deployment complexities that exist in the current community landscape.

Whether you are building a new big data platform, upgrading an existing cluster, or migrating from commercial distributions, HodoopForge makes deployment simpler, management more efficient, and operations more stable.

#### Key Features & Highlights
- **Seamless Ambari + Bigtop Integration**: Specialized optimizations and fixes for Ambari 3.x compatibility with Bigtop 3.5+, including improved Management Packs (MPacks), stack definitions, service metadata, and dependency resolution.
- **Enhanced Deployment Experience**: Wizard-based or one-click deployment support for the latest Bigtop components (Hadoop, Hive, Spark, HBase, Kafka, Flink, etc.). Supports both online and offline installation modes across multiple Linux distributions (RHEL/CentOS/Rocky Linux, Ubuntu, etc.).
- **Full Lifecycle Management**: Inherits and improves Ambari’s mature web UI for cluster provisioning, configuration management, service monitoring, alerting, rolling upgrades, and High Availability (HA) setup.
- **Targeted Optimizations**:
  - Refined Bigtop stack compatibility, package naming, and installation paths
  - Enhanced service discovery, health checks, and failure diagnostics
  - Optimized performance tuning templates and resource allocation
  - Support for custom and extended stacks, making it easy to integrate third-party or in-house components
- **Improved Usability & Operations**: Simplified installation process, comprehensive logging and troubleshooting tools, backup/restore capabilities, and better integration with Ansible or other configuration tools.
- **Security & Extensibility**: Built-in support for Kerberos, Ranger, and other security features. Plugin architecture ready for future extensions toward cloud-native or Kubernetes environments.

#### Target Use Cases
- Teams wanting to run the latest Apache Bigtop releases but facing Ambari compatibility challenges
- Organizations seeking a pure open-source, vendor-neutral Hadoop platform
- Users migrating from Cloudera HDP/CDP or other commercial distributions to community stacks
- Big data operations teams looking to reduce deployment complexity and ongoing maintenance overhead

#### Positioning
HodoopForge is not just a simple repackaging of Ambari and Bigtop — it is a targeted re-engineering that preserves Ambari’s proven management strengths while injecting robust support for the latest Bigtop ecosystem. It serves as the essential bridge between established tools and the evolving open-source big data landscape.

---

### Logo Design Ideas
Here are several conceptual directions for the HodoopForge logo (suitable for vector design in tools like Figma, Illustrator, or AI generators):

1. **Primary Concept (Recommended)**:  
   A stylized elephant (classic Hadoop symbol) combined with a blacksmith’s hammer or anvil. The elephant’s body subtly forms the letter “H”, while the hammer represents “Forge”. Use deep navy blue + orange accents (Hadoop’s traditional colors) with metallic gradients for the forge element. Clean, modern typography for “HodoopForge” with a subtle gear or circuit pattern in the background.

2. **Minimalist Tech Style**:  
   Abstract “H” shaped like a chain or link (symbolizing the connection/bridge between Ambari and Bigtop), with glowing nodes or data particles. Add a small anvil or flame icon next to it. Monochrome version available for dark/light modes.

3. **Forge + Data Flow**:  
   An anvil with molten data streams (binary/code lines or Hadoop elephant silhouette) flowing out like forged metal. Tagline “Forge Stability” placed underneath.

4. **Icon-Only Version**:  
   A compact hammer striking an elephant-shaped spark, enclosed in a hexagonal shield (representing stability and big data ecosystem).

**Color Palette Suggestions**:  
- Primary: Deep Navy (#0A2540) + Hadoop Orange (#FF6600)  
- Accent: Metallic Silver/Gold for forge feel  
- Neutral: Charcoal gray and white for UI

**Font Suggestions**:  
- Sans-serif modern tech fonts like Inter, Montserrat, or Roboto Condensed for the wordmark.  
- Slightly bolder weight for “Forge” to emphasize strength.

---


docker exec bigtop_hostname0 bash -c "
sed -i \"s/'app.name': 'Otowyue'/'app.name': 'HodoopForge'/g\" /usr/lib/ambari-server/web/javascripts/app.js
sed -i \"s/name: 'Otowyue'/name: 'HodoopForge'/g\" /usr/lib/ambari-server/web/javascripts/app.js
sed -i \"s/'app.name.subtitle': 'Otowyue - {0}'/'app.name.subtitle': 'HodoopForge - {0}'/g\" /usr/lib/ambari-server/web/javascripts/app.js
sed -i 's/<title>Otowyue<\/title>/<title>HodoopForge<\/title>/' /usr/lib/ambari-server/web/index.html

grep -o \"'app.name': '[^']*'\" /usr/lib/ambari-server/web/javascripts/app.js | head -2
grep '<title>' /usr/lib/ambari-server/web/index.html
"