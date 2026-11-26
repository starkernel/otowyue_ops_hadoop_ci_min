#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

set -ex

docker compose cp install-ambari-server-script.sh bigtop_hostname0:/root/install-ambari-server-script.sh
docker compose cp setup-bigtop-stack.sh bigtop_hostname0:/root/setup-bigtop-stack.sh
docker compose cp insert-repo-version.py bigtop_hostname0:/root/insert-repo-version.py
docker compose cp fix-package-names.sh bigtop_hostname0:/root/fix-package-names.sh
docker compose cp -a flink-stack-fix bigtop_hostname0:/root/flink-stack-fix
docker compose cp setup-flink-stack-fix.sh bigtop_hostname0:/root/setup-flink-stack-fix.sh
docker compose exec -it bigtop_hostname0 chmod +x /root/setup-bigtop-stack.sh /root/fix-package-names.sh /root/setup-flink-stack-fix.sh
docker compose exec -it bigtop_hostname0 /bin/bash /root/install-ambari-server-script.sh
