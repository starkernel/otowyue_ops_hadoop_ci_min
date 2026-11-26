#!/usr/bin/env bash
# Install HodoopForge ops automation into systemd.
#
#   sudo bash scripts/install_ops_automation.sh
#
# Installs:
#   hodoopforge-postsnapshot.service  (oneshot, at boot: --all)
#   hodoopforge-healthcheck.service  (oneshot, called by timer: --check)
#   hodoopforge-healthcheck.timer    (every 10 min)
#   hodoopforge-logclean.service     (oneshot, rotates old container logs)
#   hodoopforge-logclean.timer       (daily)
#
# Logs:
#   /var/log/hodoopforge-postsnapshot.log
#   /var/log/hodoopforge-healthcheck.log
#   /var/log/hodoopforge-logclean.log
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECOVER="$ROOT/scripts/post_snapshot_recover.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "please run as root: sudo bash $0" >&2
  exit 1
fi
[ -x "$RECOVER" ] || { echo "missing $RECOVER" >&2; exit 1; }

cat > /etc/systemd/system/hodoopforge-postsnapshot.service <<EOF
[Unit]
Description=HodoopForge post-boot health check and auto-recover
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
EnvironmentFile=-/etc/hodoopforge/ambari.env
ExecStartPre=/bin/sleep 45
ExecStart=/bin/bash -c '$RECOVER --all >> /var/log/hodoopforge-postsnapshot.log 2>&1'
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/hodoopforge-healthcheck.service <<EOF
[Unit]
Description=HodoopForge cluster health check (report only)
After=docker.service

[Service]
Type=oneshot
EnvironmentFile=-/etc/hodoopforge/ambari.env
ExecStart=/bin/bash -c '$RECOVER --check >> /var/log/hodoopforge-healthcheck.log 2>&1'
TimeoutStartSec=300
EOF

cat > /etc/systemd/system/hodoopforge-healthcheck.timer <<'EOF'
[Unit]
Description=Run HodoopForge health check every 10 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
AccuracySec=30s
Unit=hodoopforge-healthcheck.service

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/hodoopforge-watchdog.service <<EOF
[Unit]
Description=HodoopForge 60s data-plane watchdog (auto-start missing services)
After=docker.service

[Service]
Type=oneshot
EnvironmentFile=-/etc/hodoopforge/ambari.env
ExecStart=/bin/bash -c 'python3 $ROOT/scripts/watchdog.py --fix >> /var/log/hodoopforge-watchdog.log 2>&1'
TimeoutStartSec=900
EOF

cat > /etc/systemd/system/hodoopforge-watchdog.timer <<'EOF'
[Unit]
Description=Run HodoopForge watchdog every 60 seconds

[Timer]
OnBootSec=2min
OnUnitActiveSec=60s
AccuracySec=5s
Unit=hodoopforge-watchdog.service

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/hodoopforge-logclean.service <<EOF
[Unit]
Description=HodoopForge container log retention (14 days)

[Service]
Type=oneshot
ExecStart=/bin/bash -c '$ROOT/scripts/cleanup_old_logs.sh 14 >> /var/log/hodoopforge-logclean.log 2>&1'
TimeoutStartSec=1800
EOF

cat > /etc/systemd/system/hodoopforge-logclean.timer <<'EOF'
[Unit]
Description=Run HodoopForge log cleanup daily

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
Unit=hodoopforge-logclean.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable hodoopforge-postsnapshot.service
systemctl enable --now hodoopforge-healthcheck.timer
systemctl enable --now hodoopforge-watchdog.timer
systemctl enable --now hodoopforge-logclean.timer

echo "installed:"
echo "  hodoopforge-postsnapshot.service (enabled, runs at boot)"
echo "  hodoopforge-healthcheck.timer    (active, every 10 min, report only)"
echo "  hodoopforge-watchdog.timer       (active, every 60s, auto-start missing services)"
echo "  hodoopforge-logclean.timer       (active, daily 03:30, 14-day retention)"
echo
echo "check:  systemctl status hodoopforge-healthcheck.timer"
echo "logs :  tail -f /var/log/hodoopforge-healthcheck.log"
echo "manual: bash $RECOVER --check"

cat > /etc/systemd/system/hodoopforge-backup.service <<EOF2
[Unit]
Description=HodoopForge throttled control-plane backup
After=docker.service

[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/bin/bash $ROOT/scripts/backup_with_throttle.sh --with-fsimage
TimeoutStartSec=3600
EOF2

cat > /etc/systemd/system/hodoopforge-backup.timer <<'EOF2'
[Unit]
Description=Run HodoopForge backup daily at 02:30

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF2

systemctl daemon-reload
systemctl enable --now hodoopforge-backup.timer
echo "backup timer: $(systemctl is-active hodoopforge-backup.timer)"

cat > /etc/systemd/system/hodoopforge-containers.service <<'EOF2'
[Unit]
Description=Start existing HodoopForge containers (never docker compose)
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
# 禁止运行 docker compose up：compose 只是重建基线，容器内数据不在卷上。
# Only start existing containers.  Do NOT run `docker compose up`: the compose
# file is a rebuild baseline and container-local data is not on volumes.
ExecStart=/bin/bash -c '/usr/bin/docker start bigtop_hostname0 bigtop_hostname1 bigtop_hostname2 bigtop_hostname3 || true'
# Wait for the Ambari API (host port 20609) but do not fail the boot if slow.
ExecStartPost=/bin/bash -c 'for i in $(seq 1 60); do /usr/bin/curl -s http://127.0.0.1:20609/api/v1/clusters >/dev/null 2>&1 && exit 0; sleep 5; done; exit 0'
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
systemctl enable --now hodoopforge-containers.service
echo "containers unit: $(systemctl is-enabled hodoopforge-containers.service) / $(systemctl is-active hodoopforge-containers.service)"

cat > /etc/systemd/system/hodoopforge-mgmt-exporter.service <<'EOF2'
[Unit]
Description=HodoopForge management-plane exporter (:9404)
After=docker.service network.target
Requires=docker.service

[Service]
Type=simple
Environment=MGMT_REPO=REPO_PLACEHOLDER
ExecStart=/usr/bin/python3 REPO_PLACEHOLDER/scripts/monitoring/management_exporter.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF2
sed -i "s|REPO_PLACEHOLDER|$ROOT|g" /etc/systemd/system/hodoopforge-mgmt-exporter.service
systemctl daemon-reload
systemctl enable --now hodoopforge-mgmt-exporter.service
echo "mgmt exporter: $(systemctl is-active hodoopforge-mgmt-exporter.service)"
