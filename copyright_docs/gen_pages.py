#!/usr/bin/env python3
import os

TARGET = 'copyright_docs/源程序前后30页.md'

# Pages 17-30 content stored as list of (title, content) tuples
pages = []

pages.append(("17", r"""
## 第17页 · insert-repo-version.py（主函数逻辑）

```python
def main():
    # 主函数：执行版本信息注入流程
    # 执行顺序: 检查VDF -> 读取内容 -> 连接DB -> 幂等检查 -> 插入记录
    print("==> HodoopForge: 注入 Bigtop 3.5.0 版本信息...")

    # 步骤1: 检查 VDF 文件是否存在
    if not os.path.exists(VDF_PATH):
        print(f"[ERROR] VDF 文件不存在: {VDF_PATH}")
        sys.exit(1)

    # 步骤2: 读取 VDF XML 内容（将存入数据库 version_xml 字段）
    with open(VDF_PATH, 'r', encoding='utf-8') as f:
        vdf_xml = f.read()
    print(f"    VDF 文件读取成功，大小: {len(vdf_xml)} 字节")

    # 步骤3: 建立数据库连接
    try:
        conn   = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        print("    数据库连接成功")
    except mysql.connector.Error as err:
        print(f"[ERROR] 数据库连接失败: {err}")
        sys.exit(1)

    # 步骤4: 幂等性检查——版本记录是否已存在
    # 若已存在则跳过插入，避免主键冲突导致脚本报错
    cursor.execute(
        "SELECT COUNT(*) FROM repo_version WHERE version = %s",
        (VERSION_CONFIG['version'],)
    )
    if cursor.fetchone()[0] > 0:
        print(f"    [INFO] 版本 {VERSION_CONFIG['version']} 已存在，跳过")
        cursor.close()
        conn.close()
        return

    # 步骤5: 查询 BIGTOP Stack 的 stack_id
    # repo_version 表通过 stack_id 外键关联到 stack 表
    cursor.execute(
        "SELECT stack_id FROM stack WHERE stack_name = 'BIGTOP'"
    )
    result   = cursor.fetchone()
    stack_id = result[0] if result else 4   # 默认值 4 作为兜底
    print(f"    BIGTOP stack_id = {stack_id}")

    # 步骤6: 构造并执行 INSERT 语句
    # 使用参数化查询，防止 SQL 注入
    # version_xml 字段存储完整的 VDF XML 内容（CLOB 类型）
    INSERT_SQL = (
        "INSERT INTO repo_version "
        "(repo_version_id, stack_id, version, display_name, "
        " repo_type, hidden, resolved, legacy, version_url, version_xml) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)"
    )
    cursor.execute(INSERT_SQL, (
        VERSION_CONFIG['repo_version_id'],  # 版本记录主键 ID
        stack_id,                           # 关联的 Stack ID
        VERSION_CONFIG['version'],          # 版本号 3.5.0.0-1
        VERSION_CONFIG['display_name'],     # UI 显示名称
        VERSION_CONFIG['repo_type'],        # 仓库类型 STANDARD
        VERSION_CONFIG['hidden'],           # 是否隐藏 0=显示
        VERSION_CONFIG['resolved'],         # 是否已解析 1=是
        VERSION_CONFIG['legacy'],           # 是否旧版本 0=否
        VERSION_CONFIG['version_url'],      # VDF 文件 URL
        vdf_xml                             # VDF XML 完整内容
    ))
    conn.commit()   # 提交事务，持久化写入数据库
    print(f"    [OK] 版本 {VERSION_CONFIG['version']} 插入成功")

    cursor.close()
    conn.close()
    print("==> 版本信息注入完成")


if __name__ == '__main__':
    main()
```
"""))

pages.append(("18", r"""
## 第18页 · fix_secrets.py（XML配置修复工具）

```python
#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: fix_secrets.py
# 文件功能: XML 配置文件精确修复工具
#   使用 Python xml.etree.ElementTree 解析 XML，
#   精确定位并修复配置文件中的异常空格值，
#   比 sed 文本替换更安全，不破坏 XML 结构。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import xml.etree.ElementTree as ET   # Python 标准 XML 解析库
import os                             # 文件操作接口
import shutil                         # 高级文件操作（备份）
from datetime import datetime         # 时间戳生成


def fix_xml_empty_values(xml_path):
    # 修复 XML 配置文件中值为纯空白字符的 <value> 节点
    # 参数: xml_path - XML 配置文件的绝对路径
    # 返回: 修复的属性数量（0 表示无需修复）
    if not os.path.exists(xml_path):
        print(f"    [SKIP] 文件不存在: {xml_path}")
        return 0

    # 备份原文件，文件名附加时间戳，避免覆盖历史备份
    ts  = datetime.now().strftime('%Y%m%d%H%M%S')
    bak = f"{xml_path}.bak.{ts}"
    shutil.copy2(xml_path, bak)
    print(f"    已备份原文件: {bak}")

    # 解析 XML 文件为 ElementTree 对象
    tree  = ET.parse(xml_path)
    root  = tree.getroot()
    fixed = 0   # 记录修复数量

    # 遍历所有 <property> 节点（Hadoop XML 配置的标准结构）
    for prop in root.findall('property'):
        name_el  = prop.find('name')    # <name> 子节点
        value_el = prop.find('value')   # <value> 子节点

        # 跳过结构不完整的节点
        if name_el is None or value_el is None:
            continue

        # 检查值是否为纯空白字符
        # 条件: 值非 None、非空字符串，但 strip() 后为空
        if value_el.text and value_el.text.strip() == '':
            prop_name     = name_el.text
            value_el.text = ''   # 清空为真正的空字符串
            fixed        += 1
            print(f"      修复属性: {prop_name}")

    if fixed > 0:
        # 写回修复后的 XML，保留 XML 声明头
        tree.write(xml_path, encoding='utf-8', xml_declaration=True)
        print(f"    [OK] 共修复 {fixed} 个属性")
    else:
        print(f"    [INFO] 无需修复，删除备份")
        os.remove(bak)   # 无修改则删除备份，保持目录整洁

    return fixed


if __name__ == '__main__':
    print("==> HodoopForge: 修复 XML 配置文件...")
    count = fix_xml_empty_values('/etc/hive/conf/hive-site.xml')
    print(f"==> 修复完成，共修复 {count} 个配置项")
```
"""))

pages.append(("19", r"""
## 第19页 · ranger_pwd.py（Ranger密码生成工具）

```python
#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: ranger_pwd.py
# 文件功能: Ranger 服务密码生成工具
#   生成符合 Apache Ranger 密码策略要求的随机密码。
#   Ranger 要求密码必须包含大写字母、小写字母、
#   数字和特殊字符，且长度不少于 8 位。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import sys       # 命令行参数解析
import random    # 随机数生成（密码随机化）
import string    # 字符集常量（大写/小写/数字）


def generate_ranger_password(length=12):
    # 生成符合 Ranger 密码策略的随机密码
    # Ranger 密码策略要求:
    #   - 最少 8 个字符
    #   - 至少 1 个大写字母 (A-Z)
    #   - 至少 1 个小写字母 (a-z)
    #   - 至少 1 个数字 (0-9)
    #   - 至少 1 个特殊字符 (!@#$%^&*)
    if length < 8:
        raise ValueError("密码长度不能少于 8 位（Ranger 策略要求）")

    # 定义各类字符集
    upper   = string.ascii_uppercase   # A-Z 26个大写字母
    lower   = string.ascii_lowercase   # a-z 26个小写字母
    digits  = string.digits            # 0-9 10个数字
    special = '!@#$%^&*'              # Ranger 支持的特殊字符集

    # 强制包含每类字符至少一个，满足最低策略要求
    pwd = [
        random.choice(upper),    # 强制包含 1 个大写字母
        random.choice(lower),    # 强制包含 1 个小写字母
        random.choice(digits),   # 强制包含 1 个数字
        random.choice(special),  # 强制包含 1 个特殊字符
    ]

    # 用所有字符类型填充剩余长度（length - 4 个）
    all_chars = upper + lower + digits + special
    for _ in range(length - 4):
        pwd.append(random.choice(all_chars))

    # 打乱顺序，避免前 4 位固定为特定类型（增加随机性）
    random.shuffle(pwd)

    return ''.join(pwd)


if __name__ == '__main__':
    # 支持命令行参数指定密码长度，默认 12 位
    # 用法: python3 ranger_pwd.py [长度]
    # 示例: python3 ranger_pwd.py 16
    length   = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    password = generate_ranger_password(length)
    print(password)   # 输出生成的密码
```
"""))

pages.append(("20", r"""
## 第20页 · docker-compose.yml（容器编排·主节点配置）

```yaml
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: docker-compose.yml
# 文件功能: Docker 容器编排配置文件
#   定义 HodoopForge 4 节点 Hadoop 集群的完整容器配置，
#   包括镜像选择、端口映射、存储卷挂载、网络配置等。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================
# 集群节点说明:
#   bigtop_hostname0: 主节点（Ambari Server + 各服务 Master）
#   bigtop_hostname1: 从节点1（Ambari Agent + 各服务 Slave）
#   bigtop_hostname2: 从节点2（Ambari Agent + 各服务 Slave）
#   bigtop_hostname3: 从节点3（Ambari Agent + 各服务 Slave）
# ============================================================

services:

  # ==========================================================
  # 主节点: bigtop_hostname0
  # 职责: 运行 Ambari Server、MySQL、Nginx 及各服务 Master
  # ==========================================================
  bigtop_hostname0:
    # 容器启动命令: 启动 systemd 初始化系统
    # 必须使用 /sbin/init 才能通过 systemctl 管理服务
    command: /sbin/init

    # 容器主机名（FQDN 的主机名部分）
    hostname: bigtop_hostname0

    # 容器名称（docker ps 中显示的唯一标识）
    container_name: bigtop_hostname0

    # 域名（与 hostname 组合成完整 FQDN）
    # 完整 FQDN: bigtop_hostname0.bigtop.apache.org
    domainname: bigtop.apache.org

    # 使用 Bigtop 官方 Rocky Linux 8 基础镜像
    # trunk: 主干开发版本
    # rockylinux-8: 基于 Rocky Linux 8 操作系统
    image: bigtop/puppet:trunk-rockylinux-8

    # 内存上限: 8GB（防止单容器耗尽宿主机全部内存）
    mem_limit: 8g

    # 禁用 swap 使用（值为0，提高性能稳定性）
    mem_swappiness: 0

    # 端口映射: 宿主机端口 -> 容器端口
    # 20609:8080 使宿主机可通过 http://localhost:20609
    # 访问容器内的 Ambari Web UI（默认端口 8080）
    ports:
      - "20609:8080"

    # 特权模式: 必须启用
    # 原因: systemd 需要访问 /sys/fs/cgroup 等系统资源
    privileged: true

    # 存储卷挂载（宿主机路径:容器路径[:权限]）
    volumes:
      # 本地 YUM 仓库目录（读写模式，Nginx 从此提供服务）
      - ./ambari-repo:/var/repo/ambari

      # Ambari RPM 包目录（只读，安装时从此复制）
      - ../ambarirpm:/var/repo/ambarirpm:ro

      # Bigtop RPM 包目录（只读，安装时从此复制）
      - ../bigtoprpm:/var/repo/bigtoprpm:ro

      # 主机名解析配置（覆盖容器内 /etc/hosts）
      # 确保所有节点能通过 FQDN 互相解析
      - ./conf/hosts:/etc/hosts
```
"""))

with open(TARGET, 'a') as f:
    for num, content in pages:
        f.write(content)

print(f"Pages 17-20 written to {TARGET}")
print(f"Total size: {os.path.getsize(TARGET)} bytes")
