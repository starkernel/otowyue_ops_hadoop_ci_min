#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#

set -ex
# >>> -e: 任意命令失败立即退出  -x: 打印每条命令便于调试

INSTANCES="bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3"
# >>> 集群节点列表：hostname0=主节点(Ambari Server)，1-3=从节点(Agent)

for i in $INSTANCES ; do
  if [ "$(docker compose ps | grep -c $i)" == "0" ] ; then
    echo "can't find docker container: $i"
    exit 1
  fi
done

for i in $INSTANCES ; do
  docker compose exec -it $i dnf install -y sudo openssh-server openssh-clients which iproute net-tools less vim-enhanced
  # >>> 安装SSH服务端/客户端，Ambari节点间通信和密钥分发必需
  docker compose exec -it $i dnf install -y initscripts wget curl tar unzip git
  # >>> 安装下载工具、解压工具和版本控制工具
  docker compose exec -it $i dnf install -y dnf-plugins-core
  # >>> 提供 config-manager 子命令，用于启用/禁用软件仓库
  # >>> PowerTools仓库提供额外开发包，部分Ambari依赖需要
  docker compose exec -it $i dnf config-manager --set-enabled powertools 2>/dev/null \
    || docker compose exec -it $i dnf config-manager --set-enabled rocky-powertools 2>/dev/null \
    || echo "powertools already enabled or not needed"
  docker compose exec -it $i dnf update -y || echo "update failed, but continuing"
done

for i in $INSTANCES ; do
  # 只在没有 id_rsa 时才生成，避免重复执行报错
  docker compose exec -it $i bash -c \
    '[ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa'
    # >>> -t rsa: RSA算法  -N "": 空密码短语(免密登录必须)  幂等：已存在则跳过
  docker compose exec -it $i systemctl enable sshd
  # >>> 设置SSH开机自启，容器重启后自动恢复服务
  docker compose exec -it $i systemctl start sshd
done

for i in $INSTANCES ; do
  docker compose exec -it $i setenforce 0 || echo "selinux is disabled"
  # >>> 关闭SELinux强制模式，避免Ambari服务被安全策略拦截
done

# 把 hostname0 的公钥分发到所有节点的 authorized_keys
docker compose cp bigtop_hostname0:/root/.ssh/id_rsa.pub bigtop_hostname0.pub
# >>> 将主节点公钥复制到宿主机临时文件，再分发到所有节点

for i in $INSTANCES ; do
  docker compose cp bigtop_hostname0.pub $i:/root/.ssh/authorized_keys
  docker compose exec -it $i chown root:root /root/.ssh/authorized_keys
  docker compose exec -it $i chmod 600 /root/.ssh/authorized_keys
  # >>> SSH要求authorized_keys权限为600，否则拒绝使用该文件
done

rm -f bigtop_hostname0.pub

# ── 更新 /etc/hosts（先用 docker exec 获取 IP，不依赖 SSH）────────────────────
rm -f hosts
printf '127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4\n' > hosts
printf '::1         localhost localhost.localdomain localhost6 localhost6.localdomain6\n\n' >> hosts

for i in $INSTANCES ; do
  docker compose cp getip.sh $i:/root/getip.sh
  # >>> 获取容器IP地址，写入/etc/hosts实现FQDN主机名解析
  IP=$(docker compose exec -it $i /bin/bash /root/getip.sh | tr -d '\r\n ')
  # >>> 获取容器IP地址，写入/etc/hosts实现FQDN主机名解析
  FQDN=$(echo "$i" | sed 's/_/-/g')".bigtop.apache.org"
  echo "${IP}  ${FQDN} ${i}" >> hosts
  echo "  -> ${i}: ${IP}"
done

if [ "$(basename $PWD)" == "scripts" ] ; then
  cat hosts > ../conf/hosts
  # >>> 将生成的hosts文件写入conf目录，供docker-compose挂载到容器
else
  cat hosts > conf/hosts
  # >>> 将生成的hosts文件写入conf目录，供docker-compose挂载到容器
fi
rm -f hosts

# ── 用 docker exec 验证 SSH 服务正常（不走网络 SSH）─────────────────────────
for i in $INSTANCES ; do
  docker compose exec -it $i systemctl is-active sshd && echo "$i: sshd OK"
  # >>> 验证SSH服务正常运行，不走网络SSH，直接用docker exec检查
done

echo "==> setup.sh completed successfully"