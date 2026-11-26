#!/usr/bin/env bash
# Install the manual-Kerberos guard.
#
#   sudo bash scripts/install_kerberos_guard.sh   # systemd timer (root)
#   bash scripts/install_kerberos_guard.sh        # per-user cron (no root)
#
# The guard stops ambari-agent inside the four containers (so Ambari cannot
# rewrite the Kerberos config), snapshots/restores the Kerberos config, and
# starts missing HDFS/HBase/Hive/YARN processes in the correct order.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY=/usr/bin/python3

if [ "$(id -u)" -eq 0 ]; then
  UNIT=/etc/systemd/system/hodoopforge-kerberos-guard.service
  TIMER=/etc/systemd/system/hodoopforge-kerberos-guard.timer
  cat > "$UNIT" <<EOF
[Unit]
Description=HodoopForge manual Kerberos guard
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
Environment=KERBEROS_GUARD_HOME=/etc/hodoopforge
ExecStart=$PY $REPO/scripts/kerberos_guard.py --fix
Nice=5
IOSchedulingClass=best-effort
IOSchedulingPriority=6
EOF
  cat > "$TIMER" <<EOF
[Unit]
Description=Run HodoopForge manual Kerberos guard every 30 seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Unit=hodoopforge-kerberos-guard.service

[Install]
WantedBy=timers.target
EOF
  chmod 755 "$REPO/scripts/kerberos_guard.py"
  systemctl daemon-reload
  systemctl enable --now hodoopforge-kerberos-guard.timer
  export KERBEROS_GUARD_HOME=/etc/hodoopforge
else
  GUARD_HOME="${KERBEROS_GUARD_HOME:-$HOME/.hodoopforge-kerberos}"
  UNIT_DIR="$HOME/.config/systemd/user"
  mkdir -p "$GUARD_HOME" "$UNIT_DIR"
  cat > "$UNIT_DIR/hodoopforge-kerberos-guard.service" <<EOF
[Unit]
Description=HodoopForge manual Kerberos guard (user)

[Service]
Type=oneshot
Environment=KERBEROS_GUARD_HOME=$GUARD_HOME
ExecStart=$PY $REPO/scripts/kerberos_guard.py --fix
Nice=5
EOF
  cat > "$UNIT_DIR/hodoopforge-kerberos-guard.timer" <<EOF
[Unit]
Description=Run HodoopForge manual Kerberos guard every 30 seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Unit=hodoopforge-kerberos-guard.service

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now hodoopforge-kerberos-guard.timer
  loginctl enable-linger "$USER" >/dev/null 2>&1 || true
  export KERBEROS_GUARD_HOME="$GUARD_HOME"
  echo "installed per-user systemd timer: $GUARD_HOME"
fi

echo "== enable manual Kerberos guard =="
"$PY" "$REPO/scripts/kerberos_guard.py" enable
echo "== status =="
"$PY" "$REPO/scripts/kerberos_guard.py" status
