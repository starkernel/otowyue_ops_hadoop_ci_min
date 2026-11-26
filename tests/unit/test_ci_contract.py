"""CI contract tests: keep architecture, guard, map and pipeline honest.

These tests are intentionally dependency-light so they also run in the
Qixuan CloudBuild Python runner.
"""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def test_architecture_documents_current_state():
    text = (REPO / "docs/ARCHITECTURE.md").read_text(encoding="utf-8")
    assert "security_type=KERBEROS" in text
    assert "kerberos_guard" in text
    assert "h3 Active" in text
    assert "h0 Standby" in text
    assert "Kafka" in text and "SASL_PLAINTEXT" in text


def test_lake_map_is_self_contained():
    html = (REPO / "docs/lake-map.html").read_text(encoding="utf-8")
    assert 'id="lake-map-data"' in html
    assert "fetch(" not in html, "map must not depend on fetch/lake-map-data.json"
    start = html.index('<script id="lake-map-data" type="application/json">')
    start = html.index(">", start) + 1
    end = html.index("</script>", start)
    data = json.loads(html[start:end])
    assert data["summary"]
    assert len(data["layers"]) >= 5
    assert any(node["id"] == "guard" for layer in data["layers"] for node in layer["nodes"])


def test_guard_does_not_kill_agent_cgroup():
    guard = (REPO / "scripts/kerberos_guard.py").read_text(encoding="utf-8")
    assert 'run(["systemctl", "stop", "ambari-agent"' not in guard
    assert 'dexec(h, "systemctl stop ambari-agent' not in guard
    assert "proc_running" in guard
    assert "cooling" in guard
    docs = (REPO / "docs/KERBEROS_GUARD.md").read_text(encoding="utf-8")
    assert "KillMode=control-group" in docs
    assert "只按 PID" in docs


def test_ci_pipeline_contains_tests():
    import yaml

    data = yaml.safe_load((REPO / "ci/pipeline.yml").read_text(encoding="utf-8"))
    commands = []
    for job in data["jobs"].values():
        commands.extend(job.get("commands", []))
    assert any("pytest" in command for command in commands)
    assert any("requirements-dev.txt" in command for command in commands)


def test_qixuan_pipeline_is_resilient_and_runs_tests():
    import yaml

    data = yaml.safe_load((REPO / "ci/qixuan-pipeline.yml").read_text(encoding="utf-8"))
    commands = []
    for job in data["jobs"].values():
        commands.extend(job.get("commands", []))
    fetch = next(c for c in commands if "curl" in c)
    assert "otowyue_ops_hadoop_ci_min" in fetch
    assert "--retry" in fetch and "--retry-all-errors" in fetch
    # raw.githubusercontent is primary, codeload archive is the fallback.
    assert "raw.githubusercontent.com" in fetch and "codeload.github.com" in fetch
    assert any("pytest" in c and "tests/unit" in c for c in commands)


def test_current_state_mentions_dual_namenode_and_guard():
    text = (REPO / "docs/CURRENT_STATE.md").read_text(encoding="utf-8")
    assert "h3 Active" in text
    assert "h0 Standby" in text
    assert "kerberos_guard.timer" in text
    assert "security_type=KERBEROS" in text


def test_kerberos_docs_do_not_claim_plaintext_kafka():
    text = (REPO / "docs/KAFKA_EXTERNAL_ACCESS.md").read_text(encoding="utf-8")
    assert "SASL_PLAINTEXT" in text
    assert "=PLAINTEXT://192.168.0.60" not in text
