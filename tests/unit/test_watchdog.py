"""Unit tests for scripts/watchdog.py."""
from __future__ import annotations

import json


def test_parse_ha_state_healthy(watchdog_module):
    text = (
        "bigtop-hostname0.bigtop.apache.org:8020            standby   \n"
        "bigtop-hostname3.bigtop.apache.org:8020            active    \n"
    )
    result = watchdog_module.parse_ha_state(text)
    assert result["healthy"] is True
    assert result["active"] == ["bigtop-hostname3.bigtop.apache.org:8020"]
    assert result["standby"] == ["bigtop-hostname0.bigtop.apache.org:8020"]


def test_parse_ha_state_one_namenode_down(watchdog_module):
    text = (
        "bigtop-hostname0.bigtop.apache.org:8020            Failed to connect: "
        "Connection refused\n"
        "bigtop-hostname3.bigtop.apache.org:8020            active    \n"
    )
    result = watchdog_module.parse_ha_state(text)
    assert result["healthy"] is False
    assert result["active"] == ["bigtop-hostname3.bigtop.apache.org:8020"]
    assert result["unknown"]


def test_parse_ha_state_empty(watchdog_module):
    assert watchdog_module.parse_ha_state("")["healthy"] is False


def test_parse_listening(watchdog_module):
    output = (
        "LISTEN 0 128 [::ffff:172.19.0.2]:9092 [::]:*  \n"
        "LISTEN 0 128 [::ffff:172.19.0.2]:16000 [::]:* \n"
    )
    assert watchdog_module.parse_listening(output, 9092) is True
    assert watchdog_module.parse_listening(output, 9093) is False


def test_parse_flink_jobs(watchdog_module):
    payload = {
        "jobs": [
            {"jid": "a", "state": "RUNNING"},
            {"jid": "b", "state": "FINISHED"},
        ]
    }
    result = watchdog_module.parse_flink_jobs(payload)
    assert result["healthy"] is True
    assert result["running"] == 1
    assert result["job_ids"] == ["a"]


def test_parse_flink_jobs_empty(watchdog_module):
    assert watchdog_module.parse_flink_jobs({})["healthy"] is False


def _state(**overrides):
    base = {
        "containers": {"healthy": True},
        "ambari": {"healthy": True},
        "agents": {"healthy": True},
        "mysql": {"healthy": True},
        "yarn": {"healthy": True},
        "hive": {"healthy": True},
        "kdc": {"healthy": True},
        "backup": {"healthy": True},
        "hdfs": {"healthy": True},
        "hbase": {"healthy": True},
        "kafka": {"healthy": True},
        "flink": {"healthy": True},
        "flink_jm2": {"healthy": True},
        "spark": {"healthy": True},
        "monitoring": {"healthy": True},
        "time_sync": {"healthy": True},
    }
    base.update(overrides)
    return base


def test_decide_healthy_has_no_actions(watchdog_module):
    assert watchdog_module.decide(_state()) == []


def test_decide_orders_hdfs_before_others(watchdog_module):
    actions = watchdog_module.decide(
        _state(
            hdfs={"healthy": False},
            hbase={"healthy": False},
            kafka={"healthy": False},
            flink={"healthy": False},
            flink_jm2={"healthy": False},
            spark={"healthy": False},
            monitoring={"healthy": False},
            time_sync={"healthy": False},
        )
    )
    assert actions == [
        "start_chronyd",
        "start_hdfs",
        "start_hbase",
        "start_kafka",
        "start_flink",
        "start_flink_jm2",
        "start_spark",
        "start_monitoring",
    ]


def test_decide_restarts_standby_jobmanager(watchdog_module):
    assert watchdog_module.decide(_state(flink_jm2={"healthy": False})) == [
        "start_flink_jm2"
    ]


def test_decide_restarts_spark_thriftserver(watchdog_module):
    assert watchdog_module.decide(_state(spark={"healthy": False})) == ["start_spark"]


def test_parse_clock_offset(watchdog_module):
    mod = watchdog_module
    assert mod.parse_clock_offset(
        "System time     : 0.000690882 seconds fast of NTP time"
    ) == 0.000690882
    assert mod.parse_clock_offset("nonsense") is None


def test_decide_restarts_chronyd(watchdog_module):
    assert watchdog_module.decide(_state(time_sync={"healthy": False})) == [
        "start_chronyd"
    ]


def test_decide_restarts_monitoring(watchdog_module):
    assert watchdog_module.decide(_state(monitoring={"healthy": False})) == ["start_monitoring"]


def test_decide_starts_ambari(watchdog_module):
    assert watchdog_module.decide(_state(ambari={"healthy": False})) == ["start_ambari"]


def test_decide_starts_containers_first(watchdog_module):
    assert watchdog_module.decide(_state(containers={"healthy": False})) == [
        "start_containers"
    ]


def test_decide_starts_management_plane(watchdog_module):
    assert watchdog_module.decide(_state(agents={"healthy": False})) == ["start_agents"]
    assert watchdog_module.decide(_state(mysql={"healthy": False})) == ["start_mysql"]
    assert watchdog_module.decide(_state(kdc={"healthy": False})) == ["start_kdc"]


def test_decide_starts_hive_and_yarn(watchdog_module):
    assert watchdog_module.decide(_state(hive={"healthy": False})) == ["start_hive"]
    assert watchdog_module.decide(_state(yarn={"healthy": False})) == ["start_yarn"]


def test_main_check_reports_json(watchdog_module, monkeypatch, capsys):
    mod = watchdog_module
    monkeypatch.setattr(mod, "probe_all", lambda: dict(_state(), actions=[], healthy=True))
    monkeypatch.setattr(mod.sys, "argv", ["watchdog.py", "--check", "--json"])
    assert mod.main() == 0
    data = json.loads(capsys.readouterr().out)
    assert data["healthy"] is True
    assert data["performed"] == []


def test_main_returns_two_when_ambari_down(watchdog_module, monkeypatch):
    mod = watchdog_module
    monkeypatch.setattr(
        mod,
        "probe_all",
        lambda: dict(_state(ambari={"healthy": False}), actions=["wait_ambari"], healthy=False),
    )
    monkeypatch.setattr(mod.sys, "argv", ["watchdog.py", "--check"])
    assert mod.main() == 2


def test_main_fix_runs_recovery(watchdog_module, monkeypatch, capsys):
    mod = watchdog_module
    unhealthy = dict(_state(hdfs={"healthy": False}), actions=["start_hdfs"], healthy=False)
    healthy = dict(_state(), actions=[], healthy=True)
    calls = {"n": 0}

    def fake_probe():
        calls["n"] += 1
        return unhealthy if calls["n"] == 1 else healthy

    monkeypatch.setattr(mod, "probe_all", fake_probe)
    monkeypatch.setattr(mod, "recover", lambda state, submit=False: ["start_hdfs:ok"])
    monkeypatch.setattr(mod.sys, "argv", ["watchdog.py", "--fix", "--json"])
    assert mod.main() == 0
    data = json.loads(capsys.readouterr().out)
    assert data["performed"] == ["start_hdfs:ok"]
    assert data["healthy"] is True
