"""Unit tests for scripts/gen_lake_map_data.py."""
from __future__ import annotations

import json


def test_find_node_searches_layers(lake_map_module):
    data = {"layers": [{"nodes": [{"id": "hdfs"}, {"id": "flink"}]}]}
    assert lake_map_module.find_node(data, "flink")["id"] == "flink"
    assert lake_map_module.find_node(data, "missing") is None


def test_find_node_returns_none_for_empty(lake_map_module):
    assert lake_map_module.find_node({}, "hdfs") is None


def test_curl_json_returns_empty_on_failure(lake_map_module, monkeypatch):
    def boom(*a, **k):
        raise OSError("no network")

    monkeypatch.setattr(lake_map_module.subprocess, "check_output", boom)
    assert lake_map_module.curl_json("http://invalid") == {}


def test_shell_returns_empty_on_failure(lake_map_module, monkeypatch):
    def boom(*a, **k):
        raise OSError("no docker")

    monkeypatch.setattr(lake_map_module.subprocess, "check_output", boom)
    assert lake_map_module.shell("docker ps") == ""


def test_main_updates_summary_and_nodes(lake_map_module, monkeypatch, tmp_path):
    mod = lake_map_module
    data_file = tmp_path / "lake-map-data.json"
    data_file.write_text(
        json.dumps(
            {
                "generated_at": "",
                "summary": [],
                "layers": [
                    {
                        "id": "storage",
                        "nodes": [{"id": "hdfs"}, {"id": "flink"}, {"id": "ambari"}],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(mod, "DATA_FILE", str(data_file))
    monkeypatch.setattr(mod, "port_open", lambda host, port: True)
    monkeypatch.setattr(
        mod, "hdfs_state",
        lambda: ("bigtop-hostname0", "bigtop-hostname3", "3"),
    )
    monkeypatch.setattr(
        mod, "flink_job",
        lambda: ("42c0fdb46751781c640b17be70550b9b", "RUNNING", "7500"),
    )
    monkeypatch.setattr(
        mod, "curl_json",
        lambda url, timeout=8: {"Clusters": {"security_type": "KERBEROS"}},
    )

    assert mod.main() == 0
    result = json.loads(data_file.read_text(encoding="utf-8"))

    labels = {item["label"]: item for item in result["summary"]}
    assert labels["核心服务"]["value"] == "7/7 UP"
    assert labels["核心服务"]["status"] == "ok"
    assert labels["Kerberos"]["value"].startswith("KERBEROS")
    assert labels["HDFS"]["status"] == "ok"
    assert "bigtop-hostname0" in labels["HDFS"]["value"]
    assert "3 DN" in labels["HDFS"]["value"]
    assert labels["Flink"]["status"] == "ok"
    assert "RUNNING" in labels["Flink"]["value"]
    assert result["generated_at"]

    nodes = {n["id"]: n for n in result["layers"][0]["nodes"]}
    assert nodes["hdfs"]["status"] == "ok"
    assert "3 DN" in " ".join(nodes["hdfs"]["metrics"])
    assert nodes["flink"]["status"] == "ok"
    assert any("completed=7500" in m for m in nodes["flink"]["metrics"])
    assert nodes["ambari"]["status"] == "ok"


def test_main_marks_down_services(lake_map_module, monkeypatch, tmp_path):
    mod = lake_map_module
    data_file = tmp_path / "lake-map-data.json"
    data_file.write_text(
        json.dumps({"generated_at": "", "summary": [], "layers": []}),
        encoding="utf-8",
    )
    monkeypatch.setattr(mod, "DATA_FILE", str(data_file))
    monkeypatch.setattr(mod, "port_open", lambda host, port: False)
    monkeypatch.setattr(mod, "hdfs_state", lambda: ("", "", "0"))
    monkeypatch.setattr(mod, "flink_job", lambda: ("", "UNKNOWN", "?"))
    monkeypatch.setattr(
        mod, "curl_json",
        lambda url, timeout=8: {"Clusters": {"security_type": "NONE"}},
    )
    assert mod.main() == 0
    result = json.loads(data_file.read_text(encoding="utf-8"))
    labels = {item["label"]: item for item in result["summary"]}
    assert labels["核心服务"]["status"] == "warn"
    assert labels["HDFS"]["status"] == "bad"
    assert labels["Kerberos"]["status"] == "warn"


def test_main_missing_data_file_returns_one(lake_map_module, monkeypatch, tmp_path):
    mod = lake_map_module
    monkeypatch.setattr(mod, "DATA_FILE", str(tmp_path / "nope.json"))
    assert mod.main() == 1
