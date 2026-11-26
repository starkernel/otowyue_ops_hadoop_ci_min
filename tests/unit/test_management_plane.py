"""Contracts for the management model, compose baseline and drift checker."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
COMPOSE = REPO / "ambari3/docker-compose.yml"
EXPECTED = {
    "bigtop_hostname0": "20g",
    "bigtop_hostname1": "10g",
    "bigtop_hostname2": "9g",
    "bigtop_hostname3": "10g",
}


def test_compose_is_a_safe_rebuild_baseline():
    data = yaml.safe_load(COMPOSE.read_text(encoding="utf-8"))
    services = data["services"]
    for name, memory in EXPECTED.items():
        svc = services[name]
        assert svc["mem_limit"] == memory
        assert svc["restart"] == "unless-stopped"
        assert svc["healthcheck"]["test"]
        assert svc["logging"]["driver"] == "json-file"
        assert svc["logging"]["options"]["max-size"]


def test_container_boot_unit_and_exporter_are_installed():
    text = (REPO / "scripts/install_ops_automation.sh").read_text(encoding="utf-8")
    assert "hodoopforge-containers.service" in text
    assert "docker start bigtop_hostname0" in text
    assert "docker compose up" not in text or "禁止" in text
    assert "hodoopforge-mgmt-exporter.service" in text


def test_management_model_documents_ownership_and_bans():
    text = (REPO / "docs/MANAGEMENT_MODEL.md").read_text(encoding="utf-8")
    for needle in ("归属矩阵", "启动顺序", "禁止事项", "hodoopforge-containers.service"):
        assert needle in text
    assert "docker compose up" in text


def test_management_exporter_exposes_expected_metrics():
    text = (REPO / "scripts/monitoring/management_exporter.py").read_text(encoding="utf-8")
    for metric in (
        "mgmt_ambari_up",
        "mgmt_agent_up",
        "mgmt_mysql_replica_lag_seconds",
        "mgmt_hive_hms_up",
        "mgmt_kdc_up",
        "mgmt_backup_last_success_timestamp",
        "mgmt_config_drift",
    ):
        assert metric in text


def test_watchdog_covers_management_plane():
    text = (REPO / "scripts/watchdog.py").read_text(encoding="utf-8")
    for probe in (
        "probe_containers",
        "probe_agents",
        "probe_mysql",
        "probe_hive",
        "probe_kdc",
        "probe_yarn",
        "probe_backup",
    ):
        assert probe in text
    assert "start_ambari" in text
    assert "start_containers" in text


def test_config_drift_static_check_passes():
    result = subprocess.run(
        [sys.executable, str(REPO / "scripts/config_drift_check.py"), "--static"],
        cwd=str(REPO),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_restore_and_failover_drills_are_safe():
    restore = (REPO / "scripts/restore_drill.sh").read_text(encoding="utf-8")
    assert "FOREIGN_KEY_CHECKS=0" in restore
    assert "restore_drill_" in restore
    assert "DROP DATABASE" in restore
    assert "RTO" in restore

    drill = (REPO / "scripts/mysql_failover_drill.sh").read_text(encoding="utf-8")
    assert "STOP REPLICA" in drill
    assert "CHANGE REPLICATION SOURCE" in drill
    assert "failover_drill" in drill
    assert "SOURCE_LOG_POS" in drill


def test_blueprint_and_rebuild_runbook_exist():
    blueprint = REPO / "ambari3/blueprint.json"
    assert blueprint.is_file()
    data = yaml.safe_load(blueprint.read_text(encoding="utf-8"))
    assert data["Blueprints"]["stack_name"] == "BIGTOP"
    assert len(data["host_groups"]) == 4
    text = (REPO / "docs/REBUILD_RUNBOOK.md").read_text(encoding="utf-8")
    assert "docker compose up -d" in text
    assert "restore_drill.sh" in text
    assert "mysql_failover_drill.sh" in text
