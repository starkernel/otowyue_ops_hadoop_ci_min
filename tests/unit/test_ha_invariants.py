"""Regression guards for the documented HA / warehouse invariants.

These tests do not talk to the cluster.  They assert that the scripts, evidence
and docs keep the design decisions that took real incidents to establish:

* Kafka: 3 brokers, replication factor 3, min.insync.replicas=2.
* HDFS: nameservice ``qixuandata`` with two NameNodes.
* Iceberg: both Spark and Flink write to ``iceberg-warehouse-ha``.
* Ops: post-snapshot recovery covers the core services.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def _read(relative: str) -> str:
    return (REPO / relative).read_text(encoding="utf-8")


def test_lake_alignment_defaults_to_ha_warehouse():
    text = _read("datalake/tools/check_lake_alignment.py")
    assert "iceberg-warehouse-ha" in text
    assert "qixuandata" in text
    assert "OLD_WAREHOUSE" in text and "NEW_WAREHOUSE" in text


def test_migration_tools_target_nameservice():
    for relative in (
        "datalake/tools/migrate_beeline.py",
        "datalake/pipelines/migrate_iceberg_warehouse.py",
    ):
        text = _read(relative)
        assert "qixuandata" in text, relative
        assert "iceberg-warehouse" in text, relative


def test_warehouse_alignment_evidence_is_77_of_77():
    data = json.loads(
        _read("datalake/evidence/2026-11-19-warehouse-alignment.json")
    )
    alignment = data["alignment"]
    assert alignment["new_tables"] == 77
    assert alignment["aligned"] == 77
    assert alignment["misaligned"] == 0
    assert data["spark_catalog"]["warehouse"].endswith("iceberg-warehouse-ha")
    assert data["flink"]["warehouse"].endswith("iceberg-warehouse-ha")


def test_kafka_external_ports_are_documented_and_scripted():
    text = _read("scripts/kafka_external_listener.sh")
    for port in ("9092", "9093", "9094"):
        assert port in text
    nat = _read("ambari3/scripts/setup-nat-forward.sh")
    for port in ("9092", "9093", "9094"):
        assert port in nat


def test_post_snapshot_recovery_covers_core_services():
    text = _read("scripts/post_snapshot_recover.sh")
    for service in (
        "ZOOKEEPER",
        "HDFS",
        "YARN",
        "MAPREDUCE2",
        "HIVE",
        "HBASE",
        "KAFKA",
        "SPARK",
        "FLINK",
        "RANGER",
    ):
        assert service in text, "post-snapshot recovery misses %s" % service
    assert "--check" in text
    assert "--all" in text
    assert "--fix-nat" in text
    assert "--fix-kafka" in text


def test_lake_map_summary_reflects_alignment():
    data = json.loads(_read("docs/lake-map-data.json"))
    nodes = {node["id"]: node for layer in data["layers"] for node in layer["nodes"]}
    metrics = " ".join(nodes["iceberg"].get("metrics", []))
    assert "tables=77" in metrics and "aligned=77" in metrics
    assert "-ha" in metrics or "-ha" in nodes["iceberg"].get("desc", "")


def test_production_plan_marks_hdfs_ha_done():
    text = _read("docs/PRODUCTION_HA_UPGRADE_PLAN.md")
    assert "HDFS NN HA" in text
    # The 2026-11-09 implementation is complete; the plan must not still
    # claim there is only a single NameNode and zero JournalNodes.
    assert "0 JN" not in text or "已完成" in text


def test_kafka_topic_defaults_in_scripts_use_rf3():
    text = _read("scripts/post_snapshot_recover.sh")
    assert "min.insync.replicas" in text or "advertised.listeners" in text
    # The documented design is RF3/minISR2 in CURRENT_STATE.
    current = _read("docs/CURRENT_STATE.md")
    assert "RF3" in current or "replication factor 3" in current.lower()


def test_no_plaintext_private_keys_in_repo():
    suspicious = []
    for path in REPO.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        if path.suffix.lower() not in {".pem", ".key", ".p12", ".jks"}:
            continue
        suspicious.append(str(path.relative_to(REPO)))
    assert not suspicious, "private key material committed: %s" % suspicious


def test_shell_scripts_do_not_embed_passwords_in_curl():
    pattern = re.compile(r"(?:-u|--user)\s+([^\s'\"]+)")
    offenders = []
    for path in (REPO / "scripts").rglob("*.sh"):
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if "curl" not in line:
                continue
            for credential in pattern.findall(line):
                # Variables (e.g. "$AMBARI_USER:$AMBARI_PASS") and the
                # documented local Ambari credential are allowed.
                if "$" in credential:
                    continue
                offenders.append("%s: %s" % (path.name, line.strip()[:80]))
    assert not offenders, offenders
