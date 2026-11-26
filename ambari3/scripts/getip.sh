#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#
ifconfig |grep inet |grep -v 127 |grep -v '::1' | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' |cut -d ' ' -f2
