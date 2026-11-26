#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Management-plane exporter (:9404), run on the Docker host.

Why: the data-plane exporters cannot see Ambari, MySQL replication, KDC, the
backup directory, or container state.  This exporter gives Prometheus a small
set of management signals so "the thing that manages the cluster" is monitored
too.

Run:  python3 scripts/monitoring/management_exporter.py
Env:
  MGMT_EXPORTER_PORT   default 9404
  MGMT_CACHE_TTL       default 15 seconds
  MGMT_DRIFT_TTL       default 300 seconds
  MGMT_REPO            default /home/rkam/hadoop-ops-course
"""
import json
import os
import socket
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

PORT = int(os.environ.get("MGMT_EXPORTER_PORT", "9404"))
CACHE_TTL = float(os.environ.get("MGMT_CACHE_TTL", "15"))
DRIFT_TTL = float(os.environ.get("MGMT_DRIFT_TTL", "300"))
REPO = os.environ.get("MGMT_REPO", "/home/rkam/hadoop-ops-course")
BACKUP_DIR = os.environ.get("MGMT_BACKUP_DIR", "/var/backups/hodoopforge")
CONTAINERS = ["bigtop_hostname0", "bigtop_hostname1", "bigtop_hostname2", "bigtop_hostname3"]
HOST_IPS = {
    "bigtop_hostname0": "172.19.0.2",
    "bigtop_hostname1": "172.19.0.5",
    "bigtop_hostname2": "172.19.0.3",
    "bigtop_hostname3": "172.19.0.4",
}
_cache = {"ts": 0.0, "body": ""}
_drift = {"ts": 0.0, "count": -1}


def run(cmd, timeout=8):
    try:
        out = subprocess.check_output(
            cmd, stderr=subprocess.STDOUT, timeout=timeout,
            universal_newlines=True,
        )
        return 0, out
    except subprocess.CalledProcessError as exc:
        return exc.returncode, exc.output or ""
    except Exception as exc:  # noqa: BLE001
        return 1, str(exc)


def docker_exec(container, command, timeout=8):
    return run(["/usr/bin/docker", "exec", container, "/bin/bash", "-c", command], timeout)


def tcp_ok(host, port, timeout=2):
    try:
        sock = socket.create_connection((host, port), timeout)
        sock.close()
        return True
    except OSError:
        return False


def http_up(url, timeout=3):
    try:
        with urlopen(url, timeout=timeout) as response:
            return 200 <= response.status < 500
    except HTTPError as exc:
        return exc.code < 500
    except (URLError, OSError):
        return False


def container_running(name):
    code, out = run(["/usr/bin/docker", "inspect", "-f", "{{.State.Running}}", name], 5)
    return code == 0 and out.strip() == "true"


def container_restart_policy(name):
    code, out = run(
        ["/usr/bin/docker", "inspect", "-f", "{{.HostConfig.RestartPolicy.Name}}", name], 5
    )
    return out.strip() if code == 0 else "unknown"


def mysql_replica():
    code, out = docker_exec("bigtop_hostname3", "mysql -e 'SHOW REPLICA STATUS\\G' 2>/dev/null", 10)
    state = {"io": 0, "sql": 0, "lag": -1}
    if code != 0:
        return state
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Replica_IO_Running:"):
            state["io"] = 1 if line.split(":", 1)[1].strip() == "Yes" else 0
        elif line.startswith("Replica_SQL_Running:"):
            state["sql"] = 1 if line.split(":", 1)[1].strip() == "Yes" else 0
        elif line.startswith("Seconds_Behind_Source:"):
            value = line.split(":", 1)[1].strip()
            state["lag"] = int(value) if value.isdigit() else -1
    return state


def backup_age():
    try:
        entries = [
            os.path.join(BACKUP_DIR, name)
            for name in os.listdir(BACKUP_DIR)
            if os.path.isdir(os.path.join(BACKUP_DIR, name))
        ]
        if not entries:
            return -1, -1
        latest = max(entries, key=os.path.getmtime)
        ts = os.path.getmtime(latest)
        return int(ts), int(time.time() - ts)
    except OSError:
        return -1, -1


def drift_count():
    now = time.time()
    if now - _drift["ts"] < DRIFT_TTL:
        return _drift["count"]
    code, out = run(
        ["/usr/bin/python3", os.path.join(REPO, "scripts/config_drift_check.py"), "--json"],
        30,
    )
    count = -1
    try:
        data = json.loads(out)
        count = len(data.get("issues", []))
    except ValueError:
        count = -1
    _drift.update(ts=now, count=count)
    return count


def render():
    lines = []
    lines.append("mgmt_ambari_up %d" % (1 if http_up("http://127.0.0.1:20609/api/v1/clusters") else 0))
    lines.append("mgmt_yarn_rm_up %d" % (1 if tcp_ok("172.19.0.2", 8088) else 0))
    lines.append("mgmt_mysql_primary_up %d" % (
        1 if docker_exec("bigtop_hostname0", "mysqladmin ping --silent", 8)[0] == 0 else 0))
    replica = mysql_replica()
    lines.append("mgmt_mysql_replica_io_running %d" % replica["io"])
    lines.append("mgmt_mysql_replica_sql_running %d" % replica["sql"])
    lines.append("mgmt_mysql_replica_lag_seconds %d" % replica["lag"])

    for name in CONTAINERS:
        lines.append('mgmt_container_up{name="%s"} %d' % (name, 1 if container_running(name) else 0))
        lines.append('mgmt_container_restart_policy{name="%s",policy="%s"} 1'
                     % (name, container_restart_policy(name)))
        code, _ = docker_exec(name, "pgrep -f AmbariAgent.py >/dev/null", 5)
        lines.append('mgmt_agent_up{host="%s"} %d' % (name, 1 if code == 0 else 0))

    for host, port, metric in (
        ("bigtop_hostname0", 9083, "mgmt_hive_hms_up"),
        ("bigtop_hostname1", 9083, "mgmt_hive_hms_up"),
        ("bigtop_hostname0", 10000, "mgmt_hive_hs2_up"),
        ("bigtop_hostname3", 10000, "mgmt_hive_hs2_up"),
        ("bigtop_hostname0", 88, "mgmt_kdc_up"),
        ("bigtop_hostname3", 88, "mgmt_kdc_up"),
    ):
        lines.append('%s{host="%s"} %d' % (metric, host, 1 if tcp_ok(HOST_IPS[host], port) else 0))

    for host in ("bigtop_hostname2", "bigtop_hostname3"):
        code, out = docker_exec(host, "pgrep -fc TaskManagerRunner 2>/dev/null || true", 5)
        try:
            count = int(out.strip() or "0")
        except ValueError:
            count = -1
        lines.append('mgmt_flink_tm_count{host="%s"} %d' % (host, count))

    ts, age = backup_age()
    lines.append("mgmt_backup_last_success_timestamp %d" % ts)
    lines.append("mgmt_backup_age_seconds %d" % age)
    lines.append("mgmt_config_drift %d" % drift_count())
    return "\n".join(lines) + "\n"


def cached():
    now = time.time()
    if now - _cache["ts"] < CACHE_TTL and _cache["body"]:
        return _cache["body"]
    body = render()
    _cache.update(ts=now, body=body)
    return body


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/metrics", "/"):
            body = cached().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/-/healthy":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
