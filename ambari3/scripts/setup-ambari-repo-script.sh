#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

set -ex

# Install createrepo and nginx (禁用 ambari repo，此时 nginx 还没起来)
# 先确保旧的 ambari repo 不干扰（容器重建后 nginx 未启动）
rm -f /etc/yum.repos.d/ambari.repo
# >>> 删除旧的ambari.repo，此时nginx未启动，避免dnf访问失败

dnf install -y createrepo nginx
# >>> createrepo: 生成YUM仓库元数据  nginx: 提供HTTP访问服务

REPO_DIR=/var/repo/ambari

mkdir -p ${REPO_DIR}

echo "==> Copying Ambari 3.1.0 RPMs from local mount..."
find /var/repo/ambarirpm -name "*.rpm" -exec cp -v {} ${REPO_DIR}/ \;
# >>> 递归查找Ambari所有RPM包并复制到仓库目录

echo "==> Copying Bigtop 3.5.0 RPMs from local mount..."
find /var/repo/bigtoprpm -name "*.rpm" -exec cp -v {} ${REPO_DIR}/ \;
# >>> Bigtop RPM按组件分子目录存放，统一复制到仓库根目录

echo "==> Building local yum repository..."
createrepo --update ${REPO_DIR}
# >>> 扫描目录中所有RPM包，生成repomd.xml等YUM元数据文件

dnf clean all
# >>> 清除DNF缓存，确保后续使用最新的仓库元数据
dnf makecache --disablerepo=ambari || true

# Setup nginx to serve the repo over HTTP
tee /etc/nginx/conf.d/ambari-repo.conf << 'EOF'
# >>> 配置Nginx虚拟主机，将仓库目录通过HTTP对外提供访问
server {
    listen 80;
    server_name bigtop_hostname0 bigtop-hostname0.bigtop.apache.org;
    root /var/repo/ambari;
    autoindex on;
    # >>> 开启目录浏览，方便查看仓库中的RPM包列表
    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

# Remove default nginx config to avoid port conflict
rm -f /etc/nginx/conf.d/default.conf
# >>> 删除默认配置，避免与自定义配置的80端口冲突

systemctl enable nginx
# >>> 设置Nginx开机自启，容器重启后自动恢复HTTP仓库服务
systemctl start nginx

echo "==> Repository ready at http://bigtop_hostname0/"