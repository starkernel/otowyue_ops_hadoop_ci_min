#!/bin/sh
echo "[1/6] Stopping dockerd"
nsenter -t 1 -m -u -i -n -p -- /bin/sh -c 'pkill -9 dockerd; sleep 4; pgrep dockerd && { echo FATAL_dockerd_alive; exit 1; } || echo dockerd_stopped'

echo "[2/6] Copying /var/lib/docker -> /home/docker-data"
mkdir -p /host/home/docker-data
cd /host/var/lib/docker && tar cf - . 2>/dev/null | (cd /host/home/docker-data && tar xf - 2>/dev/null)
echo copy_done

echo "[3/6] Writing daemon.json"
printf '{"registry-mirrors":["https://docker.1ms.run"],"data-root":"/home/docker-data"}\n' > /host/etc/docker/daemon.json
cat /host/etc/docker/daemon.json

echo "[4/6] Starting dockerd"
nsenter -t 1 -m -u -i -n -p -- /bin/sh -c 'nohup /usr/bin/dockerd --containerd=/run/containerd/containerd.sock >/var/log/dockerd-restart.log 2>&1 & sleep 10; pgrep dockerd && echo dockerd_started || echo FATAL_dockerd_not_starting; [ -f /var/log/dockerd-restart.log ] && tail -3 /var/log/dockerd-restart.log' 
nsenter -t 1 -m -u -i -n -p -- /bin/sh -c '/usr/bin/docker info 2>&1 | grep -E "Docker Root Dir|Server Version" || true'

echo "[5/6] Containers found"
nsenter -t 1 -m -u -i -n -p -- /bin/sh -c '/usr/bin/docker ps -a --format "{{.Names}} {{.Status}}"'

echo "[6/6] Starting cluster containers"
nsenter -t 1 -m -u -i -n -p -- /bin/sh -c '/usr/bin/docker start bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3; sleep 3; /usr/bin/docker ps'
echo "MIGRATE_SCRIPT_END"