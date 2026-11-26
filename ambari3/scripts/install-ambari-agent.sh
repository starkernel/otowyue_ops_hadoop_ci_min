#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

set -ex

INSTANCES="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"

for i in $INSTANCES ; do
  # Convert underscore to hyphen and append domain: bigtop_hostname0 -> bigtop-hostname0.bigtop.apache.org
  HOSTNAME=$(echo "$i" | sed 's/_/-/g')".bigtop.apache.org"
  docker compose cp install-ambari-agent-script.sh $i:/root/install-ambari-agent-script.sh
  docker compose exec -it $i /bin/bash /root/install-ambari-agent-script.sh "${HOSTNAME}"
done
