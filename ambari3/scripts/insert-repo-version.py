#!/usr/bin/env python3
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#
# 仅修复 stack_id=0 → 10（EclipseLink 不接受 id=0）。
# 不预注入 repo_version——让 Web UI Install Wizard 自然完成 VDF 上传注册，
# 避免 Duplicate entry 主键冲突。
import mysql.connector
import sys

conn = mysql.connector.connect(
    host='localhost',
    user='ambari',
    password='ambari',
    database='ambari'
)
cursor = conn.cursor()

# 修正 BIGTOP 3.5.0 的 stack_id（DDL INSERT IGNORE 可能分配了 id=0）
cursor.execute(
    "SELECT stack_id FROM stack WHERE stack_name='BIGTOP' AND stack_version='3.5.0'"
)
row = cursor.fetchone()
if not row:
    print("ERROR: BIGTOP 3.5.0 not found in stack table", file=sys.stderr)
    sys.exit(1)

bigtop_stack_id = row[0]
if bigtop_stack_id == 0:
    cursor.execute(
        "UPDATE stack SET stack_id=10 WHERE stack_id=0 "
        "AND stack_name='BIGTOP' AND stack_version='3.5.0'"
    )
    # 同步修正可能已被 DDL 带入的 repo_version 记录
    cursor.execute("UPDATE repo_version SET stack_id=10 WHERE stack_id=0")
    conn.commit()
    print("==> Fixed stack_id 0 -> 10 for BIGTOP 3.5.0 (EclipseLink rejects id=0)")
else:
    print(f"==> BIGTOP 3.5.0 stack_id={bigtop_stack_id} (already correct, skip)")

# 若 repo_version 表中存在重复的 id=1 记录（历史遗留），清理之
# 让 Wizard 重新自然注册，避免 Duplicate entry 主键冲突
cursor.execute("SELECT COUNT(*) FROM repo_version WHERE repo_version_id=1")
count = cursor.fetchone()[0]
if count > 0:
    # 检查是否是 Bigtop 3.5.0 的预注入记录
    cursor.execute(
        "SELECT version, display_name FROM repo_version WHERE repo_version_id=1"
    )
    rv = cursor.fetchone()
    if rv and '3.5.0' in str(rv[0]):
        cursor.execute("DELETE FROM repo_version WHERE repo_version_id=1")
        conn.commit()
        print(f"==> Removed pre-injected repo_version '{rv[1]}' (repo_version_id=1)")
        print("    Wizard will re-register VDF naturally during cluster creation")
    else:
        print(f"==> repo_version_id=1 exists ('{rv[1] if rv else '?'}'), not touching")
else:
    print("==> No pre-injected repo_version to clean up")

# 验证最终状态
cursor.execute("SELECT stack_id, stack_name, stack_version FROM stack ORDER BY stack_id")
print("==> stack table:")
for r in cursor.fetchall():
    print(f"    stack_id={r[0]}  {r[1]} {r[2]}")

cursor.execute("SELECT repo_version_id, stack_id, version, display_name FROM repo_version")
print("==> repo_version table:")
rows = cursor.fetchall()
if rows:
    for r in rows:
        print(f"    id={r[0]}  stack_id={r[1]}  {r[2]}  ({r[3]})")
else:
    print("    (empty — Wizard will populate during Install Wizard)")

cursor.close()
conn.close()
