#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refresh docs/lake-map-data.json from the live HodoopForge cluster.

The lake map is intentionally probe-driven: after the 2026-11-26 manual
Kerberos cutover Ambari agents are locked by kerberos_guard, so Ambari service
states are stale.  This generator therefore checks real ports / Kerberos
commands / Flink REST instead of trusting Ambari service state.

Usage:
  AMBARI_PASS=... python3 scripts/gen_lake_map_data.py
"""
import datetime
import json
import os
import socket
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_FILE = os.path.join(ROOT, "docs", "lake-map-data.json")
AMBARI = "http://localhost:20609/api/v1/clusters/qixuandata"
AMBARI_USER = os.environ.get("AMBARI_USER", "admin")
AMBARI_PASS = os.environ.get("AMBARI_PASS", "")

IPS = {"h0": "172.19.0.2", "h1": "172.19.0.5", "h2": "172.19.0.3", "h3": "172.19.0.4"}
PORTS = [
    ("HDFS", "h0", 8020),
    ("HBase", "h0", 16000),
    ("Hive", "h0", 10000),
    ("YARN", "h0", 8050),
    ("Kafka", "h0", 9092),
    ("Spark", "h1", 10016),
    ("Flink", "h0", 8081),
]


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
AMBARI_PASS = os.environ.get("AMBARI_PASS", AMBARI_PASS)


def curl_json(url, timeout=8):
    if not AMBARI_PASS:
        return {}
    try:
        out = subprocess.check_output(
            ["curl", "-s", "--max-time", str(timeout), "-u",
             "%s:%s" % (AMBARI_USER, AMBARI_PASS),
             "-H", "X-Requested-By: hodoopforge", url])
        return json.loads(out.decode())
    except Exception:
        return {}


def shell(cmd, timeout=25):
    try:
        return subprocess.check_output(cmd, shell=True, timeout=timeout).decode(
            "utf-8", "replace")
    except Exception:
        return ""


def port_open(host, port):
    try:
        with socket.create_connection((IPS[host], port), timeout=2):
            return True
    except OSError:
        return False


def hdfs_state():
    out = shell(
        "docker exec bigtop_hostname0 bash -c \"su -s /bin/bash hdfs -c "
        "'export HADOOP_CONF_DIR=/etc/hadoop/conf; "
        "kinit -kt /etc/security/keytabs/hdfs.headless.keytab "
        "hdfs-qixuandata@HODOOPFORGE.LOCAL >/dev/null 2>&1; "
        "hdfs haadmin -getAllServiceState; "
        "hdfs dfsadmin -report 2>/dev/null | grep -E '^Live datanodes'; "
        "kdestroy'\" 2>/dev/null")
    active = standby = ""
    datanodes = "0"
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-1] == "active":
            active = parts[0].split(".")[0]
        if len(parts) >= 2 and parts[-1] == "standby":
            standby = parts[0].split(".")[0]
        if line.startswith("Live datanodes"):
            datanodes = line.split("(")[-1].split(")")[0]
    return active, standby, datanodes


def flink_job():
    data = http_json("http://172.19.0.2:8081/jobs/overview")
    jobs = data.get("jobs", [])
    running = [j for j in jobs if j.get("state") == "RUNNING"]
    job = running[0] if running else (jobs[0] if jobs else {})
    jid, state = job.get("jid", ""), job.get("state", "UNKNOWN")
    cp = http_json("http://172.19.0.2:8081/jobs/%s/checkpoints" % jid) if jid else {}
    completed = cp.get("counts", {}).get("completed", "?")
    return jid, state, completed


def http_json(url, timeout=8):
    try:
        out = subprocess.check_output(
            ["curl", "-s", "--max-time", str(timeout), url])
        return json.loads(out.decode())
    except Exception:
        return {}


def find_node(data, node_id):
    for layer in data.get("layers", []):
        for node in layer.get("nodes", []):
            if node.get("id") == node_id:
                return node
    return None


def set_node(data, node_id, **fields):
    node = find_node(data, node_id)
    if node:
        node.update(fields)


def main():
    if not os.path.exists(DATA_FILE):
        print("missing %s" % DATA_FILE, file=sys.stderr)
        return 1
    with open(DATA_FILE, encoding="utf-8") as handle:
        data = json.load(handle)

    # Probe real service ports; Ambari service states are not reliable while
    # kerberos_guard has ambari-agent stopped.
    up = [name for name, host, port in PORTS if port_open(host, port)]
    down = [name for name, host, port in PORTS if name not in up]

    active, standby, dns = hdfs_state()
    jid, jstate, cp_done = flink_job()

    security = (curl_json(AMBARI + "?fields=Clusters/security_type")
                .get("Clusters", {}).get("security_type", "UNKNOWN"))
    sentinel = os.path.exists(os.path.expanduser(
        "~/.hodoopforge-kerberos/kerberos-manual.enabled")) or os.path.exists(
        "/etc/hodoopforge/kerberos-manual.enabled")

    data["generated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    data["summary"] = [
        {"label": "核心服务", "value": "%d/%d UP" % (len(up), len(PORTS)),
         "status": "ok" if not down else "warn"},
        {"label": "Kerberos",
         "value": "%s · 7 服务" % security,
         "status": "ok" if security == "KERBEROS" else "warn"},
        {"label": "HDFS",
         "value": "%s Active · %s Standby · %s DN" % (active or "-", standby or "-", dns),
         "status": "ok" if active and dns == "3" else "bad"},
        {"label": "Flink",
         "value": "%s · checkpoint %s" % (jstate, cp_done),
         "status": "ok" if jstate == "RUNNING" else "warn"},
        {"label": "Guard",
         "value": "active · ambari-agent locked" if sentinel else "off",
         "status": "ok" if sentinel else "warn"},
    ]

    set_node(data, "hdfs",
             status="ok" if active and dns == "3" else "bad",
             sub="%s Active · %s Standby · %s DataNode" % (active or "-", standby or "-", dns),
             metrics=["3 JN · 2 ZKFC · %s DN" % dns,
                      "Kerberos RPC · DN 显式 FQDN",
                      "DN 使用 /etc/hadoop/conf-dn",
                      "nameservice qixuandata"])
    set_node(data, "flink",
             status="ok" if jstate == "RUNNING" else "warn",
             sub="JM1 h0 / JM2 h1 · Kerberos",
             metrics=["job %s %s" % (jid[:12] or "-", jstate),
                      "checkpoint completed=%s" % cp_done,
                      "Kafka SASL_PLAINTEXT/GSSAPI",
                      "zookeeper.sasl.disable=true"])
    set_node(data, "kafka",
             status="ok" if port_open("h0", 9092) and port_open("h2", 9092) and port_open("h3", 9092) else "warn",
             sub="3 broker · SASL_PLAINTEXT/GSSAPI",
             metrics=["RF3 · minISR=2",
                      "kafka/192.168.0.60 共享 principal",
                      "systemd kafka-broker 管理",
                      "advertised 192.168.0.60:9092/9093/9094"])
    set_node(data, "spark",
             status="ok" if port_open("h1", 10016) else "warn",
             sub="Spark 3.5.6 · 10016 · Kerberos",
             metrics=["ThriftServer --principal spark/...",
                      "spark.yarn.keytab=spark.service.keytab",
                      "YARN usercache/spark 已修复",
                      "beeline select 1 通过"])
    set_node(data, "ambari",
             status="ok",
             sub="20609 · security_type=%s" % security,
             metrics=["security_type=%s" % security,
                      "guard 锁定 ambari-agent",
                      "Ambari 告警非权威（Kerberos/agent）",
                      "收口 request 2472 COMPLETED"])
    set_node(data, "security",
             status="ok" if security == "KERBEROS" else "warn",
             name="Kerberos 安全总览",
             sub="MIT KDC h0/h3 · HDFS/HBase/Hive/YARN/Flink/Kafka/Spark",
             metrics=["security_type=KERBEROS",
                      "guard 30s · 锁 ambari-agent",
                      "keytab 快照 + 配置漂移恢复",
                      "Ranger/KMS 尚未 Kerberos 化"],
             commands=[
                 "python3 scripts/kerberos_guard.py status",
                 "kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-qixuandata@HODOOPFORGE.LOCAL",
                 "bash scripts/kerberos_hdfs_enable.sh rollback",
             ],
             docs=["docs/KERBEROS_ENABLEMENT.md", "docs/KERBEROS_GUARD.md",
                   "docs/KERBEROS_INCIDENT_2026-11-24.md"])
    set_node(data, "automation",
             sub="guard 30s · healthcheck 10min · 旧 watchdog 停止",
             metrics=["kerberos_guard.timer active",
                      "healthcheck.timer active",
                      "watchdog.timer 已停止",
                      "Ambari agent 由 guard 锁定"])

    # Keep the static flow/layers; only the dynamic fields above change.
    with open(DATA_FILE, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    # Keep the single-file HTML in sync (embedded JSON; works via file://).
    # Skip during unit tests that monkeypatch DATA_FILE to a temp path.
    if os.path.abspath(DATA_FILE) == os.path.abspath(os.path.join(ROOT, "docs", "lake-map-data.json")):
        try:
            subprocess.check_call([sys.executable, os.path.join(ROOT, "scripts", "build_lake_map.py")])
        except Exception as exc:
            print("WARN: build_lake_map.py failed: %s" % exc, file=sys.stderr)

    print("updated %s (up=%s down=%s hdfs=%s/%s %sDN flink=%s/%s)"
          % (DATA_FILE, len(up), len(down), active, standby, dns, jid[:8], jstate))
    return 0


if __name__ == "__main__":
    sys.exit(main())
