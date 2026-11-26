"""Static contracts for the HA and backup helper scripts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def test_flink_jm_ha_script_keeps_ha_contract():
    text = (REPO / "scripts/flink_jm_ha.sh").read_text(encoding="utf-8")
    assert "high-availability.type" in text
    assert "hdfs://qixuandata/flink/ha" in text
    assert "flink-jobmanager-2.service" in text
    assert "conf-jm2" in text
    assert "bigtop-hostname1" in text
    # JM2 must advertise its own host, not h0's address.
    assert "jobmanager.rpc.address: $JM2_HOST" in text


def test_backup_script_is_throttled_and_bounded():
    text = (REPO / "scripts/backup_with_throttle.sh").read_text(encoding="utf-8")
    assert "ionice -c3" in text
    assert "nice -n19" in text
    assert "BACKUP_WINDOW_START" in text
    assert "BACKUP_RETENTION_DAYS" in text
    assert "mysqldump" in text
    assert "configs.tar.gz" in text
    assert "zookeeper" in text
    assert "--with-fsimage" in text
    assert "SHA256SUMS" in text


def test_backup_timer_is_installed_by_ops_automation():
    text = (REPO / "scripts/install_ops_automation.sh").read_text(encoding="utf-8")
    assert "hodoopforge-backup.timer" in text
    assert "OnCalendar=*-*-* 02:30:00" in text


def test_flink_conf_ha_keys_are_documented():
    text = (REPO / "docs/CURRENT_STATE.md").read_text(encoding="utf-8")
    assert "JM HA" in text
    assert "JM2" in text


def test_mysql_replica_setup_contract():
    text = (REPO / "scripts/mysql_replica_setup.sh").read_text(encoding="utf-8")
    assert "server-id=2" in text
    assert "read_only=ON" in text
    assert "source-data=2" in text
    assert "mysql-repl.env" in text
    assert "START REPLICA" in text


def test_mysql_failover_requires_confirmation():
    text = (REPO / "scripts/mysql_failover.sh").read_text(encoding="utf-8")
    assert 'CONFIRM:-' in text
    assert "STOP REPLICA" in text
    assert "super_read_only=OFF" in text


def test_kerberos_kdc_script_contract():
    text = (REPO / "scripts/kerberos_setup_kdc.sh").read_text(encoding="utf-8")
    assert "HODOOPFORGE.LOCAL" in text
    assert "kdb5_util create" in text
    assert "default_realm" in text
    assert "krb5kdc" in text
    assert "security_type=KERBEROS" in text  # documented, not executed


def test_kerberos_status_does_not_print_password():
    text = (REPO / "scripts/kerberos_status.sh").read_text(encoding="utf-8")
    assert "KRB_ADMIN_PASSWORD" in text
    assert "echo \"$ADMIN_PW\"" not in text
    assert "kinit admin/admin" in text
