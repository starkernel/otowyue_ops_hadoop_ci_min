"""Live-cluster integration checks.

Skipped by default.  Enable on the ops host with:

    HODOOPFORGE_LIVE=1 pytest -m integration -v

These tests are intentionally read-only.
"""
import json
import os
import shutil
import subprocess

import pytest

pytestmark = pytest.mark.integration

LIVE = os.environ.get("HODOOPFORGE_LIVE", "").strip() in {"1", "true", "yes"}
HAS_DOCKER = shutil.which("docker") is not None
def _load_env_file(path="/etc/hodoopforge/ambari.env"):
    try:
        with open(path, "r") as handle:
            for raw in handle:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())
    except OSError:
        pass


_load_env_file()

AMBARI = os.environ.get("AMBARI_URL", "http://localhost:20609")
CLUSTER = os.environ.get("AMBARI_CLUSTER", "qixuandata")
AMBARI_USER = os.environ.get("AMBARI_USER", "admin")
AMBARI_PASS = os.environ.get("AMBARI_PASS", "admin")


def _skip():
    if not LIVE:
        pytest.skip("set HODOOPFORGE_LIVE=1 to run live integration tests")
    if not HAS_DOCKER:
        pytest.skip("docker is required for live integration tests")


def _docker(container: str, command: str, timeout: int = 60) -> str:
    result = subprocess.run(
        ["docker", "exec", container, "bash", "-c", command],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return result.stdout + result.stderr


def _ambari(path: str, timeout: int = 30):
    import urllib.request
    import base64

    url = "%s/api/v1/clusters/%s%s" % (AMBARI, CLUSTER, path)
    request = urllib.request.Request(url)
    token = base64.b64encode(("%s:%s" % (AMBARI_USER, AMBARI_PASS)).encode()).decode()
    request.add_header("Authorization", "Basic " + token)
    request.add_header("X-Requested-By", "ambari")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode())


def test_ambari_has_no_critical_alerts():
    _skip()
    data = _ambari("/alerts?fields=Alert/state,Alert/label&page_size=500")
    critical = [
        item["Alert"]["label"]
        for item in data.get("items", [])
        if item["Alert"]["state"] == "CRITICAL"
    ]
    assert not critical, "CRITICAL alerts: %s" % critical


def test_hdfs_ha_has_active_and_standby():
    _skip()
    out = _docker(
        "bigtop_hostname0",
        "su -s /bin/bash hdfs -c 'hdfs haadmin -getAllServiceState'",
    )
    assert "active" in out
    assert "standby" in out
    assert "Failed to connect" not in out


def test_hdfs_has_no_missing_blocks():
    _skip()
    out = _docker(
        "bigtop_hostname0",
        "su -s /bin/bash hdfs -c 'hdfs dfsadmin -report'",
    )
    assert "Missing blocks: 0" in out
    assert "Live datanodes (3)" in out


def test_hbase_has_active_master():
    _skip()
    out = _docker(
        "bigtop_hostname0",
        "echo 'status' | hbase shell 2>/dev/null",
        timeout=90,
    )
    assert "active master" in out
    assert "0 dead" in out


def test_kafka_partitions_are_rf3_and_fully_in_sync():
    _skip()
    out = _docker(
        "bigtop_hostname0",
        "kafka-topics.sh --bootstrap-server 192.168.0.60:9092 --describe 2>/dev/null",
        timeout=90,
    )
    partitions = [line for line in out.splitlines() if "Partition:" in line]
    assert partitions, "no Kafka partitions returned"
    for line in partitions:
        assert "Leader: -1" not in line, line
        isr = line.split("Isr:")[1].split()[0] if "Isr:" in line else ""
        assert len(isr.split(",")) == 3, "ISR not 3: %s" % line


def test_flink_job_is_running():
    _skip()
    import urllib.request

    url = os.environ.get("FLINK_URL", "http://172.19.0.2:8081") + "/jobs/overview"
    with urllib.request.urlopen(url, timeout=10) as response:
        data = json.loads(response.read().decode())
    states = [job["state"] for job in data.get("jobs", [])]
    assert "RUNNING" in states, states


def test_warehouse_alignment_is_clean():
    _skip()
    result = subprocess.run(
        ["python3", "datalake/tools/check_lake_alignment.py", "--json"],
        cwd=os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        capture_output=True,
        text=True,
        timeout=1200,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    data = json.loads(result.stdout)
    assert data["misaligned"] == 0
    assert data["aligned"] == data["new_tables"]


def test_prometheus_targets_are_up():
    _skip()
    import urllib.request

    base = os.environ.get("PROM_URL", "http://172.19.0.5:9090")
    with urllib.request.urlopen(base + "/api/v1/targets", timeout=10) as response:
        data = json.loads(response.read().decode())
    down = [
        (target["labels"].get("job"), target["scrapeUrl"], target.get("lastError"))
        for target in data["data"]["activeTargets"]
        if target["health"] != "up"
    ]
    assert not down, "Prometheus targets down: %s" % down


def test_prometheus_rules_are_loaded():
    _skip()
    import urllib.request

    base = os.environ.get("PROM_URL", "http://172.19.0.5:9090")
    with urllib.request.urlopen(base + "/api/v1/rules", timeout=10) as response:
        data = json.loads(response.read().decode())
    groups = {group["name"]: len(group["rules"]) for group in data["data"]["groups"]}
    assert groups.get("hodoopforge-availability", 0) >= 10
    assert groups.get("hodoopforge-capacity", 0) >= 3


def test_ambari_exporter_reports_zero_critical():
    _skip()
    import urllib.request

    url = os.environ.get("AMBARI_EXPORTER_URL", "http://172.19.0.5:9402") + "/metrics"
    with urllib.request.urlopen(url, timeout=10) as response:
        body = response.read().decode()
    assert 'ambari_alerts{state="CRITICAL"} 0' in body
    assert "ambari_up 1" in body


def test_prometheus_standby_is_ready():
    _skip()
    import urllib.request

    base = os.environ.get("PROM_STANDBY_URL", "http://172.19.0.3:9090")
    with urllib.request.urlopen(base + "/api/v1/targets", timeout=10) as response:
        data = json.loads(response.read().decode())
    down = [t["scrapeUrl"] for t in data["data"]["activeTargets"] if t["health"] != "up"]
    assert not down, "standby Prometheus targets down: %s" % down


def test_alertmanager_cluster_has_two_peers():
    _skip()
    import urllib.request

    for url in ("http://172.19.0.5:9093", "http://172.19.0.3:9093"):
        with urllib.request.urlopen(url + "/api/v2/status", timeout=10) as response:
            data = json.loads(response.read().decode())
        peers = data.get("cluster", {}).get("peers", [])
        assert len(peers) >= 2, "%s has peers=%s" % (url, peers)


def test_flink_ha_has_two_jobmanagers_with_the_job():
    _skip()
    import urllib.request

    running = []
    for base in ("http://172.19.0.2:8081", "http://172.19.0.5:8081"):
        with urllib.request.urlopen(base + "/jobs/overview", timeout=10) as response:
            data = json.loads(response.read().decode())
        running.append({j["jid"] for j in data.get("jobs", []) if j["state"] == "RUNNING"})
    assert running[0], "JM1 reports no RUNNING job"
    assert running[0] == running[1], "JM1/JM2 disagree on the running job: %s" % running


def test_containers_have_restart_policy_and_boot_unit():
    _skip()
    for name in ("bigtop_hostname0", "bigtop_hostname1", "bigtop_hostname2", "bigtop_hostname3"):
        policy = subprocess.check_output(
            ["docker", "inspect", "-f", "{{.HostConfig.RestartPolicy.Name}}", name],
            text=True,
        ).strip()
        assert policy == "unless-stopped", "%s restart=%s" % (name, policy)
    unit = subprocess.check_output(
        [
            "docker", "run", "--rm", "--privileged", "--pid=host",
            "-v", "/:/host", "-e", "SYSTEMD_IGNORE_CHROOT=1",
            "busybox", "chroot", "/host", "systemctl",
            "is-enabled", "hodoopforge-containers.service",
        ],
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()
    assert unit == "enabled"


def test_management_plane_units_are_enabled():
    _skip()
    assert "enabled" in _docker("bigtop_hostname0", "systemctl is-enabled mysqld")
    assert "enabled" in _docker("bigtop_hostname0", "systemctl is-enabled ambari-server")
    for name in ("bigtop_hostname0", "bigtop_hostname1", "bigtop_hostname2", "bigtop_hostname3"):
        assert "enabled" in _docker(name, "systemctl is-enabled ambari-agent")


def test_management_exporter_reports_no_drift():
    _skip()
    import urllib.request

    with urllib.request.urlopen("http://172.19.0.1:9404/metrics", timeout=20) as response:
        body = response.read().decode()
    assert "mgmt_ambari_up 1" in body
    assert "mgmt_config_drift 0" in body
    assert 'mgmt_container_restart_policy{name="bigtop_hostname0",policy="unless-stopped"} 1' in body
