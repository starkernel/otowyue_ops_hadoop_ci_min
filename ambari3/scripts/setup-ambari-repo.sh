#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

set -ex

docker compose cp setup-ambari-repo-script.sh bigtop_hostname0:/root/setup-ambari-repo-script.sh
docker compose exec -it bigtop_hostname0 /bin/bash /root/setup-ambari-repo-script.sh
