#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""HodoopForge 60-second watchdog.

Why this exists
---------------
Host snapshots freeze the guest and send SIGTERM to container processes.  The
containers themselves are not restarted, so ``hodoopforge-postsnapshot.service``
(which only runs at boot) never fires and a NameNode can stay down for hours.
The 10-minute healthcheck only reports.  This watchdog probes the real data
plane and starts what is missing.

Usage:
  python3 scripts/watchdog.py --check          # report only
  python3 scripts/watchdog.py --fix            # start missing services
  python3 scripts/watchdog.py --fix --json     # machine-readable result
  python3 scripts/watchdog.py --fix --submit-flink

Exit codes:
  0  healthy, or every detected problem was fixed
  1  still unhealthy after recovery
  2  Ambari is unreachable (nothing else is attempted)
"""
import argparse
import base64
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

def _load_env_file(path="/etc/hodoopforge/ambari.env"):
    """Load root-only Ambari credentials without putting them in the repo."""
    try:
        with open(path, "r") as handle:
            for raw in handle:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())
    except PermissionError:
        import sys as _sys
        print("WARN: cannot read %s; run as root or export AMBARI_PASS" % path,
              file=_sys.stderr)
    except OSError:
        pass


_load_env_file()

AMBARI = os.environ.get("AMBARI_URL", "http://localhost:20609")
CLUSTER = os.environ.get("AMBARI_CLUSTER", "qixuandata")
USER = os.environ.get("AMBARI_USER", "admin")
PASSWORD = os.environ.get("AMBARI_PASS", "admin")
FLINK_URL = os.environ.get("FLINK_URL", "http://172.19.0.2:8081")
FLINK_HA_URL = os.environ.get("FLINK_HA_URL", "http://172.19.0.5:8081")
KAFKA_BROKERS = [
    ("bigtop_hostname0", 9092),
    ("bigtop_hostname2", 9092),
    ("bigtop_hostname3", 9092),
]
HDFS_CONTAINER = os.environ.get("HDFS_CONTAINER", "bigtop_hostname0")
HBASE_MASTER_CONTAINER = os.environ.get("HBASE_MASTER_CONTAINER", "bigtop_hostname0")
HBASE_RS_CONTAINER = os.environ.get("HBASE_RS_CONTAINER", "bigtop_hostname3")
SPARK_CONTAINER = os.environ.get("SPARK_CONTAINER", "bigtop_hostname1")
SPARK_PORT = int(os.environ.get("SPARK_PORT", "10016"))
SPARK_HOST = os.environ.get("SPARK_HOST", "bigtop-hostname1.bigtop.apache.org")
PROM_URL = os.environ.get("PROM_URL", "http://172.19.0.5:9090")
ALERTMANAGER_URL = os.environ.get("ALERTMANAGER_URL", "http://172.19.0.5:9093")
MONITORING_HOST = os.environ.get("MONITORING_HOST", "bigtop_hostname1")
MONITORING_STANDBY_HOST = os.environ.get("MONITORING_STANDBY_HOST", "bigtop_hostname2")
STANDBY_UNITS = ["prometheus", "alertmanager", "alert_webhook", "prom_proxy"]
YARN_RM_URL = os.environ.get("YARN_RM_URL", "http://172.19.0.2:8088")
SPARK_APP_NAME = "Thrift JDBC/ODBC Server"
MONITORING_UNITS = [
    "prometheus",
    "alertmanager",
    "kafka_exporter",
    "hdfs_jmx_exporter",
    "ambari_exporter",
    "flink_exporter",
    "alert_webhook",
]
EXPORTER_PORTS = [9100, 9308, 9401, 9402, 9403, 9500]
NODE_EXPORTER_NODES = [
    "bigtop_hostname0",
    "bigtop_hostname1",
    "bigtop_hostname2",
    "bigtop_hostname3",
]
DOCKER_CONTAINERS = list(NODE_EXPORTER_NODES)
CONTAINER_IPS = {
    "bigtop_hostname0": "172.19.0.2",
    "bigtop_hostname1": "172.19.0.5",
    "bigtop_hostname2": "172.19.0.3",
    "bigtop_hostname3": "172.19.0.4",
}
HIVE_COMPONENTS = [
    ("bigtop-hostname0.bigtop.apache.org", "HIVE_METASTORE", 9083),
    ("bigtop-hostname1.bigtop.apache.org", "HIVE_METASTORE", 9083),
    ("bigtop-hostname0.bigtop.apache.org", "HIVE_SERVER", 10000),
    ("bigtop-hostname3.bigtop.apache.org", "HIVE_SERVER", 10000),
]
KDC_HOSTS = ["bigtop_hostname0", "bigtop_hostname3"]
BACKUP_DIR = os.environ.get("BACKUP_DIR", "/var/backups/hodoopforge")


# --------------------------------------------------------------------------
# Parsing helpers (pure functions, covered by tests/unit/test_watchdog.py)
# --------------------------------------------------------------------------
def parse_ha_state(text: str) -> dict:
    """Parse ``hdfs haadmin -getAllServiceState`` output."""
    active, standby, unknown = [], [], []
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if "Failed to connect" in line or "Connection refused" in line:
            unknown.append(line)
            continue
        lowered = line.lower()
        if lowered.endswith("active"):
            active.append(line.split()[0])
        elif lowered.endswith("standby"):
            standby.append(line.split()[0])
        elif "active" in lowered or "standby" in lowered:
            # Tolerate trailing whitespace / log noise.
            host = line.split()[0]
            (active if "active" in lowered else standby).append(host)
        else:
            unknown.append(line)
    return {
        "active": active,
        "standby": standby,
        "unknown": unknown,
        "healthy": len(active) == 1 and len(standby) == 1,
    }


def parse_listening(output: str, port: int) -> bool:
    """True if ``ss -ltn`` output shows the given port."""
    needle = ":%d " % port
    for line in (output or "").splitlines():
        if needle in line + " ":
            return True
    return False


def parse_flink_jobs(payload: dict) -> dict:
    jobs = (payload or {}).get("jobs", [])
    running = [job for job in jobs if job.get("state") == "RUNNING"]
    return {
        "total": len(jobs),
        "running": len(running),
        "job_ids": [job.get("jid", "") for job in running],
        "healthy": bool(running),
    }


def decide(state: dict) -> list:
    """Return the ordered list of recovery actions for a probe result."""
    actions = []
    if not state.get("containers", {}).get("healthy", False):
        actions.append("start_containers")
    if not state.get("ambari", {}).get("healthy", False):
        actions.append("start_ambari")
        # Everything below depends on Ambari; re-check on the next cycle.
        return actions
    if not state.get("agents", {}).get("healthy", False):
        actions.append("start_agents")
    if not state.get("mysql", {}).get("healthy", False):
        actions.append("start_mysql")
    if not state.get("time_sync", {}).get("healthy", False):
        actions.append("start_chronyd")
    if not state.get("hdfs", {}).get("healthy", False):
        actions.append("start_hdfs")
    if not state.get("hbase", {}).get("healthy", False):
        actions.append("start_hbase")
    if not state.get("yarn", {}).get("healthy", False):
        actions.append("start_yarn")
    if not state.get("hive", {}).get("healthy", False):
        actions.append("start_hive")
    if not state.get("kafka", {}).get("healthy", False):
        actions.append("start_kafka")
    if not state.get("flink", {}).get("healthy", False):
        actions.append("start_flink")
    if not state.get("flink_jm2", {}).get("healthy", False):
        actions.append("start_flink_jm2")
    if not state.get("spark", {}).get("healthy", False):
        actions.append("start_spark")
    if not state.get("monitoring", {}).get("healthy", False):
        actions.append("start_monitoring")
    if not state.get("kdc", {}).get("healthy", False):
        actions.append("start_kdc")
    return actions


# --------------------------------------------------------------------------
# Probes
# --------------------------------------------------------------------------
def _docker(container: str, command: str, timeout: int = 20) -> str:
    try:
        proc = subprocess.run(
            ["docker", "exec", container, "bash", "-c", command],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return proc.stdout.decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        return "ERROR: %s" % exc


def _http_json(url: str, timeout: int = 10) -> dict:
    request = urllib.request.Request(url)
    token = base64.b64encode(("%s:%s" % (USER, PASSWORD)).encode()).decode()
    request.add_header("Authorization", "Basic " + token)
    request.add_header("X-Requested-By", "ambari")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def _ambari(path: str, timeout: int = 20) -> dict:
    return _http_json(AMBARI + "/api/v1/clusters/" + CLUSTER + path, timeout)


def probe_ambari() -> dict:
    try:
        data = _ambari("/services?fields=ServiceInfo/state", 10)
        states = {
            item["ServiceInfo"]["service_name"]: item["ServiceInfo"]["state"]
            for item in data.get("items", [])
        }
        return {"healthy": True, "services": states}
    except Exception as exc:  # noqa: BLE001
        return {"healthy": False, "error": str(exc)[:200]}


def probe_hdfs() -> dict:
    out = _docker(
        HDFS_CONTAINER,
        "su -s /bin/bash hdfs -c 'hdfs haadmin -getAllServiceState' 2>/dev/null",
        40,
    )
    result = parse_ha_state(out)
    result["raw"] = out.strip()[:400]
    return result


def probe_hbase() -> dict:
    master = _docker(HBASE_MASTER_CONTAINER, "ss -ltn 2>/dev/null", 10)
    regionserver = _docker(HBASE_RS_CONTAINER, "ss -ltn 2>/dev/null", 10)
    master_ok = parse_listening(master, 16000)
    rs_ok = parse_listening(regionserver, 16020)
    return {
        "master": master_ok,
        "regionserver": rs_ok,
        "healthy": master_ok and rs_ok,
    }


def probe_kafka() -> dict:
    brokers = {}
    for host, port in KAFKA_BROKERS:
        out = _docker(host, "ss -ltn 2>/dev/null", 10)
        brokers[host] = parse_listening(out, port)
    return {"brokers": brokers, "healthy": all(brokers.values())}


def probe_flink() -> dict:
    """Query both JobManagers; HA means either one can serve the job."""
    errors = []
    results = []
    for base in (FLINK_URL, FLINK_HA_URL):
        try:
            data = _http_json(base + "/jobs/overview", 8)
            result = parse_flink_jobs(data)
            result["url"] = base
            results.append(result)
            if result.get("healthy"):
                result["peers"] = [r.get("url") for r in results]
                return result
        except Exception as exc:  # noqa: BLE001
            errors.append("%s: %s" % (base, str(exc)[:80]))
    if results:
        merged = results[0]
        merged["peers"] = [r.get("url") for r in results]
        return merged
    return {"healthy": False, "error": "; ".join(errors)[:200], "running": 0, "total": 0}


def probe_flink_jm2() -> dict:
    out = _docker("bigtop_hostname1", "systemctl is-active flink-jobmanager-2 2>/dev/null", 10).strip()
    return {"healthy": out == "active", "unit": out or "unknown"}


def probe_spark() -> dict:
    """YARN may place the ThriftServer AM on any node.

    The old check only looked at port 10016 on h1, which produced a false
    negative (and a duplicate start) when YARN moved the AM.  The authoritative
    signal is the YARN application itself; the port is only a fallback.
    """
    try:
        data = _http_json(YARN_RM_URL + "/ws/v1/cluster/apps?states=RUNNING,ACCEPTED,SUBMITTED,NEW,NEW_SAVING", 8)
        apps = [
            app for app in (data.get("apps") or {}).get("app", [])
            if app.get("name", "").startswith(SPARK_APP_NAME)
        ]
        running = [app for app in apps if app.get("state") == "RUNNING"]
        if running:
            return {
                "healthy": True,
                "source": "yarn",
                "state": running[0].get("state"),
                "app": running[0].get("id"),
                "host": running[0].get("amHostHttpAddress"),
            }
        if apps:
            return {"healthy": False, "source": "yarn", "state": apps[0].get("state"), "app": apps[0].get("id")}
    except Exception as exc:  # noqa: BLE001
        yarn_error = str(exc)[:160]
    else:
        yarn_error = "no app"
    out = _docker(SPARK_CONTAINER, "ss -ltn 2>/dev/null", 10)
    return {"healthy": parse_listening(out, SPARK_PORT), "port": SPARK_PORT, "yarn": yarn_error}



def _http_ok(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return 200 <= response.status < 300
    except Exception:  # noqa: BLE001
        return False


def parse_clock_offset(text):
    match = re.search(r"System time\s*:\s*([0-9.]+)\s+seconds", text or "")
    if not match:
        return None
    return float(match.group(1))


def probe_time_sync() -> dict:
    offsets = {}
    for host in NODE_EXPORTER_NODES:
        out = _docker(host, "chronyc tracking 2>/dev/null | grep 'System time'", 8)
        offsets[host] = parse_clock_offset(out)
    healthy = all(
        value is not None and abs(value) < 300 for value in offsets.values()
    )
    return {"offsets": offsets, "healthy": healthy}


def probe_monitoring() -> dict:
    exporters = {}
    for port in EXPORTER_PORTS:
        path = "/-/healthy" if port == 9500 else "/metrics"
        exporters[port] = _http_ok("http://172.19.0.5:%d%s" % (port, path))
    node = {}
    for host in NODE_EXPORTER_NODES:
        out = _docker(host, "ss -ltn 2>/dev/null", 8)
        node[host] = parse_listening(out, 9100)
    prometheus = _http_ok(PROM_URL + "/-/ready")
    alertmanager = _http_ok(ALERTMANAGER_URL + "/-/ready")
    standby = (
        _http_ok("http://172.19.0.3:9090/-/ready")
        and _http_ok("http://172.19.0.3:9093/-/ready")
        and _http_ok("http://172.19.0.3:9500/-/healthy")
    )
    proxy = _http_ok("http://172.19.0.3:9099/-/ready")
    return {
        "prometheus": prometheus,
        "alertmanager": alertmanager,
        "standby": standby,
        "proxy": proxy,
        "exporters": exporters,
        "node_exporter": node,
        "healthy": prometheus and alertmanager and standby and proxy
        and all(exporters.values()) and all(node.values()),
    }


def _tcp_ok(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        sock = socket.create_connection((host, port), timeout)
        sock.close()
        return True
    except OSError:
        return False


def probe_containers() -> dict:
    states = {}
    for name in DOCKER_CONTAINERS:
        try:
            out = subprocess.run(
                ["docker", "inspect", "-f", "{{.State.Running}}", name],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8,
            ).stdout.decode("utf-8", "replace").strip()
        except Exception:  # noqa: BLE001
            out = ""
        states[name] = out == "true"
    return {"states": states, "healthy": all(states.values())}


def probe_agents() -> dict:
    states = {}
    for name in DOCKER_CONTAINERS:
        out = _docker(name, "pgrep -f AmbariAgent.py >/dev/null 2>&1 && echo yes || echo no", 8)
        states[name] = out.strip() == "yes"
    return {"states": states, "healthy": all(states.values())}


def probe_mysql() -> dict:
    primary = _docker(
        "bigtop_hostname0", "mysqladmin ping --silent >/dev/null 2>&1 && echo yes || echo no", 10
    ).strip() == "yes"
    out = _docker("bigtop_hostname3", "mysql -e 'SHOW REPLICA STATUS\\G' 2>/dev/null", 10)
    io_ok = "Replica_IO_Running: Yes" in out
    sql_ok = "Replica_SQL_Running: Yes" in out
    lag = None
    for line in out.splitlines():
        if "Seconds_Behind_Source:" in line:
            value = line.split(":", 1)[1].strip()
            lag = int(value) if value.isdigit() else None
    healthy = primary and io_ok and sql_ok and (lag is None or lag < 300)
    return {
        "primary": primary,
        "replica_io": io_ok,
        "replica_sql": sql_ok,
        "lag": lag,
        "healthy": healthy,
    }


def probe_yarn() -> dict:
    return {"healthy": _tcp_ok(CONTAINER_IPS["bigtop_hostname0"], 8088)}


def probe_hive() -> dict:
    components = {}
    for host, component, port in HIVE_COMPONENTS:
        ip = CONTAINER_IPS[host.split(".")[0].replace("-", "_")]
        components["%s:%d" % (host.split(".")[0], port)] = _tcp_ok(ip, port)
    return {"components": components, "healthy": all(components.values())}


def probe_kdc() -> dict:
    states = {host: _tcp_ok(CONTAINER_IPS[host], 88) for host in KDC_HOSTS}
    return {"hosts": states, "healthy": all(states.values())}


def probe_backup() -> dict:
    try:
        entries = [
            os.path.join(BACKUP_DIR, name)
            for name in os.listdir(BACKUP_DIR)
            if os.path.isdir(os.path.join(BACKUP_DIR, name))
        ]
        if not entries:
            return {"healthy": False, "age_hours": None, "latest": None}
        latest = max(entries, key=os.path.getmtime)
        age_hours = (time.time() - os.path.getmtime(latest)) / 3600.0
        return {"healthy": age_hours < 30, "age_hours": round(age_hours, 1), "latest": latest}
    except PermissionError:
        # Manual runs as a non-root user cannot read the 0700 backup dir;
        # the systemd timer runs as root and does the real check.
        return {"healthy": True, "note": "permission denied (run as root)"}
    except OSError as exc:  # noqa: BLE001
        return {"healthy": False, "error": str(exc)[:120]}


def probe_all() -> dict:
    state = {
        "containers": probe_containers(),
        "ambari": probe_ambari(),
        "agents": probe_agents(),
        "mysql": probe_mysql(),
        "hdfs": probe_hdfs(),
        "hbase": probe_hbase(),
        "yarn": probe_yarn(),
        "hive": probe_hive(),
        "kafka": probe_kafka(),
        "flink": probe_flink(),
        "flink_jm2": probe_flink_jm2(),
        "spark": probe_spark(),
        "monitoring": probe_monitoring(),
        "time_sync": probe_time_sync(),
        "kdc": probe_kdc(),
        "backup": probe_backup(),
    }
    state["warnings"] = []
    if not state["backup"].get("healthy"):
        state["warnings"].append("backup_stale")
    state["actions"] = decide(state)
    state["healthy"] = not state["actions"]
    return state


# --------------------------------------------------------------------------
# Recovery
# --------------------------------------------------------------------------
def _ambari_put(path: str, body: dict, timeout: int = 30) -> dict:
    data = json.dumps(body).encode()
    request = urllib.request.Request(AMBARI + "/api/v1/clusters/" + CLUSTER + path, data=data)
    token = base64.b64encode(("%s:%s" % (USER, PASSWORD)).encode()).decode()
    request.add_header("Authorization", "Basic " + token)
    request.add_header("X-Requested-By", "ambari")
    request.add_header("Content-Type", "application/json")
    request.get_method = lambda: "PUT"
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def wait_request(request_id, timeout: int = 600) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data = _ambari("/requests/%s" % request_id, 10)
            status = data.get("Requests", {}).get("request_status", "")
        except Exception:  # noqa: BLE001
            status = ""
        if status in ("COMPLETED", "FAILED", "ABORTED", "TIMEDOUT"):
            return status
        time.sleep(5)
    return "TIMEOUT"


def start_service(service: str) -> bool:
    try:
        data = _ambari_put(
            "/services/%s" % service,
            {
                "RequestInfo": {"context": "watchdog: start %s" % service},
                "ServiceInfo": {"state": "STARTED"},
            },
        )
        request_id = data.get("Requests", {}).get("id")
        if not request_id:
            return True
        return wait_request(request_id) == "COMPLETED"
    except Exception as exc:  # noqa: BLE001
        print("watchdog: start %s failed: %s" % (service, exc))
        return False


def start_host_component(host: str, component: str) -> bool:
    try:
        if component == "SPARK_THRIFTSERVER":
            # Ambari keeps the component STARTED even after the YARN application
            # disappears.  Stop it first so Ambari actually re-submits.
            try:
                _ambari_put(
                    "/hosts/%s/host_components/%s" % (host, component),
                    {
                        "RequestInfo": {"context": "watchdog: reset %s on %s" % (component, host)},
                        "HostRoles": {"state": "INSTALLED"},
                    },
                )
            except Exception:  # noqa: BLE001
                pass
            time.sleep(5)
        data = _ambari_put(
            "/hosts/%s/host_components/%s" % (host, component),
            {
                "RequestInfo": {"context": "watchdog: start %s on %s" % (component, host)},
                "HostRoles": {"state": "STARTED"},
            },
        )
        request_id = data.get("Requests", {}).get("id")
        if not request_id:
            return True
        return wait_request(request_id) == "COMPLETED"
    except Exception as exc:  # noqa: BLE001
        print("watchdog: start %s on %s failed: %s" % (component, host, exc))
        return False


def start_kafka_brokers(state: dict) -> bool:
    brokers = state.get("kafka", {}).get("brokers", {})
    ok = True
    if not brokers.get("bigtop_hostname0", True):
        ok = start_service("KAFKA") and ok
    for host in ("bigtop_hostname2", "bigtop_hostname3"):
        if brokers.get(host, True):
            continue
        out = _docker(host, "systemctl start kafka-broker 2>&1", 60)
        if "Failed" in out or "ERROR" in out:
            print("watchdog: kafka on %s: %s" % (host, out.strip()[:200]))
            ok = False
    return ok


def submit_flink_if_needed() -> bool:
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "post_snapshot_recover.sh")
    if not os.path.isfile(script):
        return False
    try:
        proc = subprocess.run(
            ["bash", script, "--submit-flink"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=600,
        )
        return proc.returncode == 0
    except Exception as exc:  # noqa: BLE001
        print("watchdog: submit flink failed: %s" % exc)
        return False


def start_containers() -> bool:
    ok = True
    for name in DOCKER_CONTAINERS:
        try:
            proc = subprocess.run(
                ["docker", "start", name],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
            )
            if proc.returncode != 0:
                ok = False
        except Exception:  # noqa: BLE001
            ok = False
    time.sleep(5)
    return ok


def start_ambari() -> bool:
    out = _docker(
        "bigtop_hostname0",
        "systemctl reset-failed ambari-server >/dev/null 2>&1; systemctl start ambari-server 2>&1",
        180,
    )
    if "Failed" in out:
        return False
    for _ in range(36):
        if _http_ok(AMBARI + "/api/v1/clusters", 5):
            return True
        time.sleep(5)
    return False


def start_agents() -> bool:
    ok = True
    for name in DOCKER_CONTAINERS:
        out = _docker(name, "systemctl start ambari-agent 2>&1", 30)
        if "Failed" in out:
            ok = False
    return ok


def start_mysql() -> bool:
    ok = True
    for name in ("bigtop_hostname0", "bigtop_hostname3"):
        out = _docker(name, "systemctl start mysqld 2>&1", 60)
        if "Failed" in out:
            ok = False
    # The replica may be up while replication is stopped.
    out = _docker("bigtop_hostname3", "mysql -e 'START REPLICA;' 2>&1", 30)
    if "ERROR" in out:
        ok = False
    return ok


def start_hive() -> bool:
    ok = True
    for host, component, port in HIVE_COMPONENTS:
        ip = CONTAINER_IPS[host.split(".")[0].replace("-", "_")]
        if _tcp_ok(ip, port):
            continue
        if not start_host_component(host, component):
            ok = False
    return ok


def start_kdc() -> bool:
    ok = True
    for name in KDC_HOSTS:
        out = _docker(name, "systemctl start krb5kdc 2>&1", 30)
        if "Failed" in out:
            ok = False
    return ok


def recover(state: dict, submit_flink: bool = False) -> list:
    performed = []
    for action in state.get("actions", []):
        if action == "start_containers":
            performed.append("%s:%s" % (action, "ok" if start_containers() else "fail"))
        elif action == "start_ambari":
            performed.append("%s:%s" % (action, "ok" if start_ambari() else "fail"))
        elif action == "start_agents":
            performed.append("%s:%s" % (action, "ok" if start_agents() else "fail"))
        elif action == "start_mysql":
            performed.append("%s:%s" % (action, "ok" if start_mysql() else "fail"))
        elif action == "start_yarn":
            ok = start_host_component(
                "bigtop-hostname0.bigtop.apache.org", "RESOURCEMANAGER"
            )
            performed.append("%s:%s" % (action, "ok" if ok else "fail"))
        elif action == "start_hive":
            performed.append("%s:%s" % (action, "ok" if start_hive() else "fail"))
        elif action == "start_kdc":
            performed.append("%s:%s" % (action, "ok" if start_kdc() else "fail"))
        elif action == "start_chronyd":
            ok = True
            for host in NODE_EXPORTER_NODES:
                out = _docker(host, "systemctl restart hodoopforge-chronyd 2>&1", 20)
                if "Failed" in out:
                    ok = False
            performed.append("%s:%s" % (action, "ok" if ok else "fail"))
        elif action == "start_hdfs":
            performed.append("%s:%s" % (action, "ok" if start_service("HDFS") else "fail"))
        elif action == "start_hbase":
            performed.append("%s:%s" % (action, "ok" if start_service("HBASE") else "fail"))
        elif action == "start_kafka":
            performed.append("%s:%s" % (action, "ok" if start_kafka_brokers(state) else "fail"))
        elif action == "start_flink":
            ok = start_service("FLINK")
            if submit_flink and ok:
                submit_flink_if_needed()
            performed.append("%s:%s" % (action, "ok" if ok else "fail"))
        elif action == "start_flink_jm2":
            out = _docker("bigtop_hostname1", "systemctl start flink-jobmanager-2 2>&1", 60)
            performed.append("%s:%s" % (action, "ok" if "Failed" not in out else "fail"))
        elif action == "start_spark":
            ok = start_host_component(SPARK_HOST, "SPARK_THRIFTSERVER")
            performed.append("%s:%s" % (action, "ok" if ok else "fail"))
        elif action == "start_monitoring":
            ok = True
            for unit in MONITORING_UNITS:
                out = _docker(MONITORING_HOST, "systemctl start %s 2>&1" % unit, 30)
                if "Failed" in out:
                    ok = False
            for unit in STANDBY_UNITS:
                out = _docker(MONITORING_STANDBY_HOST, "systemctl start %s 2>&1" % unit, 30)
                if "Failed" in out:
                    ok = False
            for host in NODE_EXPORTER_NODES:
                out = _docker(host, "systemctl start node_exporter 2>&1", 20)
                if "Failed" in out:
                    ok = False
            performed.append("%s:%s" % (action, "ok" if ok else "fail"))
    return performed


def main() -> int:
    parser = argparse.ArgumentParser(description="HodoopForge watchdog")
    parser.add_argument("--check", action="store_true", help="report only (default)")
    parser.add_argument("--fix", action="store_true", help="start missing services")
    parser.add_argument("--json", action="store_true", help="print JSON")
    parser.add_argument("--submit-flink", action="store_true", help="resubmit Flink job if missing")
    args = parser.parse_args()

    state = probe_all()
    performed = []
    if args.fix and state["actions"]:
        performed = recover(state, args.submit_flink)
        state = probe_all()
    state["performed"] = performed
    if args.json:
        print(json.dumps(state, ensure_ascii=False, indent=2))
    else:
        def mark(key):
            return "ok" if state.get(key, {}).get("healthy") else "down"

        print("containers=%s ambari=%s agents=%s mysql=%s time=%s hdfs=%s hbase=%s "
              "yarn=%s hive=%s kafka=%s flink=%s jm2=%s spark=%s monitoring=%s kdc=%s" % (
                  mark("containers"), mark("ambari"), mark("agents"), mark("mysql"),
                  mark("time_sync"), mark("hdfs"), mark("hbase"), mark("yarn"),
                  mark("hive"), mark("kafka"), mark("flink"), mark("flink_jm2"),
                  mark("spark"), mark("monitoring"), mark("kdc"),
              ))
        if state.get("warnings"):
            print("warnings: %s" % ", ".join(state["warnings"]))
        if state.get("actions"):
            print("actions: %s" % ", ".join(state["actions"]))
        else:
            print("healthy")
    if not state["ambari"]["healthy"]:
        return 2
    return 0 if state["healthy"] else 1


if __name__ == "__main__":
    sys.exit(main())
