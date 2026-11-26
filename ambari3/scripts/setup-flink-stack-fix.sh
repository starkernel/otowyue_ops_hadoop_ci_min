#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#
# 运行位置: bigtop_hostname0 容器内（由宿主机 setup-hostname.sh 调用）
# 功能:    给 Ambari BIGTOP 3.2.0 栈的 FLINK 服务补齐 JobManager/TaskManager
#          组件定义与启动脚本
#
# 背景:
#   Ambari 3.5.0 栈的 FLINK metainfo 只声明了 FLINK_JOBMANAGER / FLINK_TASKMANAGER
#   两个"空壳"组件（无 commandScript，且引用了不存在的 flink-jobmanager /
#   flink-taskmanager 独立包），导致 Ambari 无法安装/启动这两个组件。
#   而 agent 实际加载的 FLINK 服务脚本来自 BIGTOP 3.2.0（继承链 3.5.0->3.4.0->
#   3.3.0->3.2.0），因此补丁必须打在 3.2.0 栈目录下。
#
#   容器 /var/lib/ambari-server/resources/stacks 属于可写层，容器重启后丢失，
#   需要每次重启后重新应用（与 fix-package-names.sh 同理）。

set -ex

STACK_BASE=/var/lib/ambari-server/resources/stacks
FLINK_320="${STACK_BASE}/BIGTOP/3.2.0/services/FLINK"
PATCH_DIR=/root/flink-stack-fix

# ════════════════════════════════════════════════════════════
# 1. 复制补丁脚本到 3.2.0 FLINK 的 package/scripts
# ════════════════════════════════════════════════════════════
echo "==> Copying FLINK patch scripts into BIGTOP/3.2.0 stack..."
cp -f "${PATCH_DIR}"/flink_jobmanager.py   "${FLINK_320}/package/scripts/"
cp -f "${PATCH_DIR}"/flink_taskmanager.py  "${FLINK_320}/package/scripts/"
cp -f "${PATCH_DIR}"/flink_service.py      "${FLINK_320}/package/scripts/"
cp -f "${PATCH_DIR}"/params.py             "${FLINK_320}/package/scripts/"
cp -f "${PATCH_DIR}"/status_params.py      "${FLINK_320}/package/scripts/"

# ════════════════════════════════════════════════════════════
# 2. 给 3.2.0 FLINK metainfo.xml 幂等补插 FLINK_JOBMANAGER /
#    FLINK_TASKMANAGER 组件定义（含 commandScript）
#    （3.5.0 栈 metainfo 覆盖组件列表，但不含 commandScript；
#     脚本路径会回落到 3.2.0 的实际脚本）
# ════════════════════════════════════════════════════════════
echo "==> Patching BIGTOP/3.2.0 FLINK metainfo.xml (JM/TM command scripts)..."
python3 - <<'PYEOF'
import os
p = '/var/lib/ambari-server/resources/stacks/BIGTOP/3.2.0/services/FLINK/metainfo.xml'
s = open(p).read()
if 'FLINK_JOBMANAGER' in s and 'scripts/flink_jobmanager.py' in s:
    print('metainfo already patched')
else:
    defs = '''
        <component>
          <name>FLINK_JOBMANAGER</name>
          <displayName>Flink JobManager</displayName>
          <category>MASTER</category>
          <cardinality>1</cardinality>
          <commandScript>
            <script>scripts/flink_jobmanager.py</script>
            <scriptType>PYTHON</scriptType>
            <timeout>600</timeout>
          </commandScript>
        </component>
        <component>
          <name>FLINK_TASKMANAGER</name>
          <displayName>Flink TaskManager</displayName>
          <category>SLAVE</category>
          <cardinality>1+</cardinality>
          <commandScript>
            <script>scripts/flink_taskmanager.py</script>
            <scriptType>PYTHON</scriptType>
            <timeout>600</timeout>
          </commandScript>
        </component>
'''
    assert '</components>' in s, 'could not find </components> in metainfo.xml'
    s = s.replace('      </components>', defs + '      </components>', 1)
    open(p, 'w').write(s)
    print('metainfo patched')

# 校验 XML 合法性
import xml.etree.ElementTree as ET
root = ET.parse(p).getroot()
comps = [c.find('name').text for c in root.iter('component')]
print('XML OK, components:', comps)
PYEOF

# ════════════════════════════════════════════════════════════
# 3. 清理 .pyc 缓存，避免旧字节码干扰
# ════════════════════════════════════════════════════════════
find "${FLINK_320}/package/scripts" -name '*.pyc' -delete 2>/dev/null || true

echo "==> Flink stack fix applied to BIGTOP/3.2.0"