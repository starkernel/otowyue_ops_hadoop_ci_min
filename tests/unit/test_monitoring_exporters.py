"""Unit tests for the Prometheus sidecar exporters."""
from __future__ import annotations


# --------------------------------------------------------------------------
# hdfs_jmx_exporter.py
# --------------------------------------------------------------------------
def test_hdfs_parse_status(hdfs_exporter_module):
    mod = hdfs_exporter_module
    assert mod.parse_status({"State": "ACTIVE"}) == "active"
    assert mod.parse_status({"State": " standby "}) == "standby"
    assert mod.parse_status({}) == ""


def test_hdfs_parse_inode_info(hdfs_exporter_module):
    mod = hdfs_exporter_module
    info = mod.parse_inode_info(
        {
            "Total": 1000,
            "Used": 250,
            "Free": 750,
            "LiveNodes": '{"dn1": {}, "dn2": {}, "dn3": {}}',
        }
    )
    assert info["capacity_total"] == 1000
    assert info["capacity_used"] == 250
    assert info["capacity_free"] == 750
    assert info["live_datanodes"] == 3


def test_hdfs_parse_inode_info_bad_live_nodes(hdfs_exporter_module):
    mod = hdfs_exporter_module
    assert mod.parse_inode_info({"LiveNodes": "not-json"})["live_datanodes"] == 0


def test_hdfs_parse_fsnamesystem(hdfs_exporter_module):
    mod = hdfs_exporter_module
    fs = mod.parse_fsnamesystem(
        {
            "MissingBlocks": 2,
            "UnderReplicatedBlocks": 3,
            "PendingDeletionBlocks": 4,
            "CorruptBlocks": 1,
            "BlocksTotal": 100,
            "LastCheckpointTime": 1700000000000,
            "TransactionsSinceLastCheckpoint": 9,
        }
    )
    assert fs["missing_blocks"] == 2
    assert fs["under_replicated"] == 3
    assert fs["pending_deletion"] == 4
    assert fs["corrupt_blocks"] == 1
    assert fs["blocks_total"] == 100
    assert fs["last_checkpoint_ms"] == 1700000000000
    assert fs["txns_since_checkpoint"] == 9


def test_hdfs_render_node(hdfs_exporter_module):
    mod = hdfs_exporter_module
    info = {
        "capacity_total": 1000,
        "capacity_used": 250,
        "capacity_free": 750,
        "live_datanodes": 3,
    }
    fs = {
        "missing_blocks": 0,
        "under_replicated": 0,
        "pending_deletion": 0,
        "corrupt_blocks": 0,
        "blocks_total": 10,
        "last_checkpoint_ms": 1700000000000,
        "txns_since_checkpoint": 5,
    }
    body = "\n".join(mod.render_node("h0", "active", info, fs))
    assert 'hdfs_namenode_up{host="h0"} 1' in body
    assert 'hdfs_namenode_active{host="h0"} 1' in body
    assert "hdfs_capacity_total_bytes" in body
    assert "hdfs_live_datanodes" in body
    assert "hdfs_missing_blocks" in body
    assert "1700000000" in body


# --------------------------------------------------------------------------
# ambari_exporter.py
# --------------------------------------------------------------------------
def test_ambari_alert_counts(ambari_exporter_module):
    mod = ambari_exporter_module
    items = [
        {"Alert": {"state": "OK"}},
        {"Alert": {"state": "OK"}},
        {"Alert": {"state": "WARNING"}},
        {"Alert": {"state": "CRITICAL"}},
    ]
    counts = mod.alert_counts(items)
    assert counts["OK"] == 2
    assert counts["WARNING"] == 1
    assert counts["CRITICAL"] == 1


def test_ambari_service_states(ambari_exporter_module):
    mod = ambari_exporter_module
    items = [
        {"ServiceInfo": {"service_name": "HDFS", "state": "STARTED"}},
        {"ServiceInfo": {"service_name": "HBASE", "state": "INSTALLED"}},
    ]
    assert mod.service_states(items) == {"HDFS": "STARTED", "HBASE": "INSTALLED"}


def test_ambari_render(ambari_exporter_module):
    mod = ambari_exporter_module
    body = mod.render({"OK": 97, "CRITICAL": 0}, {"HDFS": "STARTED"})
    assert "ambari_up 1" in body
    assert 'ambari_alerts{state="OK"} 97' in body
    assert 'ambari_alerts{state="CRITICAL"} 0' in body
    assert 'ambari_services{service="HDFS",state="STARTED"} 1' in body


# --------------------------------------------------------------------------
# flink_exporter.py
# --------------------------------------------------------------------------
def test_flink_render_running_job(flink_exporter_module):
    mod = flink_exporter_module
    jobs = {
        "jobs": [
            {"jid": "abc", "state": "RUNNING"},
            {"jid": "def", "state": "FINISHED"},
        ]
    }
    tms = {"taskmanagers": [{}, {}]}
    checkpoints = {"counts": {"completed": 10, "failed": 1, "restored": 0}}
    body = mod.render(jobs, tms, checkpoints)
    assert "flink_up 1" in body
    assert "flink_job_running 1" in body
    assert "flink_taskmanagers 2" in body
    assert 'flink_checkpoints_completed{job="abc"} 10' in body
    assert 'flink_checkpoints_failed{job="abc"} 1' in body


def test_flink_render_no_running_job(flink_exporter_module):
    mod = flink_exporter_module
    body = mod.render({"jobs": [{"jid": "x", "state": "FAILED"}]}, {}, {})
    assert "flink_job_running 0" in body
    assert "flink_checkpoints_completed" not in body


# --------------------------------------------------------------------------
# alert_webhook.py
# --------------------------------------------------------------------------
def test_alert_webhook_summarize(alert_webhook_module):
    mod = alert_webhook_module
    payload = {
        "status": "firing",
        "alerts": [
            {
                "status": "firing",
                "labels": {"alertname": "HdfsMissingBlocks", "severity": "critical"},
                "annotations": {"summary": "missing blocks", "description": "2 blocks"},
                "startsAt": "2026-11-20T00:00:00Z",
                "fingerprint": "abc",
            },
            {
                "status": "resolved",
                "labels": {"alertname": "FlinkJobNotRunning", "severity": "critical"},
                "annotations": {"summary": "recovered"},
            },
        ],
    }
    records = mod.summarize(payload)
    assert len(records) == 2
    assert records[0]["alertname"] == "HdfsMissingBlocks"
    assert records[0]["severity"] == "critical"
    assert records[0]["summary"] == "missing blocks"
    assert records[1]["status"] == "resolved"
    assert records[1]["alertname"] == "FlinkJobNotRunning"


def test_alert_webhook_summarize_empty(alert_webhook_module):
    assert alert_webhook_module.summarize({}) == []
    assert alert_webhook_module.summarize(None) == []


# --------------------------------------------------------------------------
# prom_proxy.py
# --------------------------------------------------------------------------
def test_prom_proxy_prefers_healthy_upstream(prom_proxy_module, monkeypatch):
    mod = prom_proxy_module
    primary, standby = mod.UPSTREAMS[0], mod.UPSTREAMS[-1]

    def fake_check(url, timeout=3):
        return (url != primary), ("" if url != primary else "connection refused")

    monkeypatch.setattr(mod, "_check", fake_check)
    monkeypatch.setattr(mod, "_state", {
        url: {"healthy": True, "checked": 0.0, "error": ""} for url in mod.UPSTREAMS
    })
    ordered = mod.ordered_upstreams()
    assert ordered[0] == standby
    assert ordered[-1] == primary


def test_prom_proxy_all_healthy_keeps_order(prom_proxy_module, monkeypatch):
    mod = prom_proxy_module
    monkeypatch.setattr(mod, "_check", lambda url, timeout=3: (True, ""))
    monkeypatch.setattr(mod, "_state", {
        url: {"healthy": True, "checked": 0.0, "error": ""} for url in mod.UPSTREAMS
    })
    assert mod.ordered_upstreams() == list(mod.UPSTREAMS)
