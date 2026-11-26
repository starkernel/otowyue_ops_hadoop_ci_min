#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

# 在容器内创建 VDF 文件并通过 API 注册到 Ambari

docker compose exec bigtop_hostname0 bash /root/create-vdf-inner.sh

curl -u admin:admin \
  -H "X-Requested-By: ambari" \
  -X POST "http://localhost:20609/api/v1/version_definitions" \
  -H "Content-Type: application/json" \
  -d '{"VersionDefinition": {"available": "http://bigtop_hostname0/bigtop-3.5.0-vdf.xml"}}'

echo ""
echo "==> Done. HTTP 201 = success"
