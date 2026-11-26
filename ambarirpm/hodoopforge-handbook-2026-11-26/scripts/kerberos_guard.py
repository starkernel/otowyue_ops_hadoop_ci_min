#!/usr/bin/env python3
"""Manual-Kerberos guard for HodoopForge.

Why
---
While the cluster is in *manual* Kerberos mode, Ambari still has the old
simple config in its database.  A single "Start/Restart" from the Ambari UI
would rewrite /etc/hadoop/conf, /etc/hbase/conf, /etc/hive/conf and
/etc/hadoop/conf-dn and silently turn the data plane back to simple.

This guard makes that impossible while the sentinel file exists:

  * stops ambari-agent on all four containers (so Ambari cannot execute
    START/STOP/restart commands);
  * stops hodoopforge-watchdog.timer (the old watchdog only understands
    simple auth);
  * detects configuration drift (auth != kerberos) and restores the
    snapshotted Kerberos configs;
  * starts missing HDFS/HBase/Hive/YARN processes with the Kerberos
    startup order.

Usage
-----
  sudo python3 scripts/kerberos_guard.py snapshot   # refresh config snapshot
  sudo python3 scripts/kerberos_guard.py enable     # create sentinel + run guard
  sudo python3 scripts/kerberos_guard.py status
  sudo python3 scripts/kerberos_guard.py --fix      # one repair pass (timer)
  sudo python3 scripts/kerberos_guard.py disable    # remove sentinel (final cutover)

The systemd unit calls `--fix` every 30 seconds.
"""
import fcntl
from typing import List, Optional
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GUARD_HOME = Path(os.environ.get("KERBEROS_GUARD_HOME", "/etc/hodoopforge"))
SENTINEL = GUARD_HOME / "kerberos-manual.enabled"
SNAPSHOT = GUARD_HOME / "kerberos-snapshot"
LOCK = GUARD_HOME / "kerberos-guard.lock"
LOG = GUARD_HOME / "kerberos-guard.log"

HOSTS = (0, 1, 2, 3)
IPS = {0: "172.19.0.2", 1: "172.19.0.5", 2: "172.19.0.3", 3: "172.19.0.4"}
CONF = "/etc/hadoop/conf"
CONF_DN = "/etc/hadoop/conf-dn"
HBASE_CONF = "/etc/hbase/conf"
HIVE_CONF = "/etc/hive/conf"
FLINK_CONF = "/etc/flink/conf"
KAFKA_CONF = "/etc/kafka/conf"

# Config files that must be part of the Kerberos snapshot.
SNAP_FILES = {
    0: [f"{CONF}/core-site.xml", f"{CONF}/hdfs-site.xml", f"{CONF}/yarn-site.xml",
        f"{HBASE_CONF}/hbase-site.xml", f"{HIVE_CONF}/hive-site.xml",
        f"{FLINK_CONF}/flink-conf.yaml", f"{KAFKA_CONF}/server.properties"],
    1: [f"{CONF}/core-site.xml", f"{CONF}/hdfs-site.xml", f"{CONF}/yarn-site.xml",
        f"{HBASE_CONF}/hbase-site.xml", f"{HIVE_CONF}/hive-site.xml",
        f"{CONF_DN}/hdfs-site.xml", f"{FLINK_CONF}/flink-conf.yaml",
        "/etc/flink/conf-jm2/flink-conf.yaml"],
    2: [f"{CONF}/core-site.xml", f"{CONF}/hdfs-site.xml", f"{CONF}/yarn-site.xml",
        f"{HBASE_CONF}/hbase-site.xml", f"{HIVE_CONF}/hive-site.xml",
        f"{CONF_DN}/hdfs-site.xml", f"{FLINK_CONF}/flink-conf.yaml",
        f"{KAFKA_CONF}/server.properties"],
    3: [f"{CONF}/core-site.xml", f"{CONF}/hdfs-site.xml", f"{CONF}/yarn-site.xml",
        f"{HBASE_CONF}/hbase-site.xml", f"{HIVE_CONF}/hive-site.xml",
        f"{CONF_DN}/hdfs-site.xml", f"{FLINK_CONF}/flink-conf.yaml",
        f"{KAFKA_CONF}/server.properties"],
}

# Which auth property tells us whether the service is still Kerberized.
AUTH_CHECKS = {
    "hdfs": (f"{CONF}/core-site.xml", "hadoop.security.authentication", "kerberos"),
    "hbase": (f"{HBASE_CONF}/hbase-site.xml", "hbase.security.authentication", "kerberos"),
    "hive": (f"{HIVE_CONF}/hive-site.xml", "hive.server2.authentication", "KERBEROS"),
}


def log(msg: str) -> None:
    line = f"{time.strftime('%Y-%m-%dT%H:%M:%S%z')} {msg}"
    print(line)
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def run(args, check=False, capture=True):
    return subprocess.run(args, check=check, universal_newlines=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT if capture else None)


def dexec(h, cmd, user=None, env=None, check=False):
    args = ["docker", "exec"]
    if user:
        args += ["-u", user]
    for k, v in (env or {}).items():
        args += ["-e", f"{k}={v}"]
    args += [f"bigtop_hostname{h}", "bash", "-lc", cmd]
    return run(args, check=check)


def proc_running(h, pattern):
    # Used to avoid starting a second daemon while the first one is still
    # initializing (RM/NN can take 30-90s).  The pattern uses [x] so the grep
    # process itself is not matched.
    out = dexec(h, 'ps -eo args --no-headers | grep -E "%s" | head -1' % pattern).stdout
    return bool(out.strip())


def cooling(name, seconds):
    # Prevent a restart storm while a slow daemon (RM/NN/HS2) is initializing.
    d = GUARD_HOME / "cooldown"
    d.mkdir(parents=True, exist_ok=True)
    path = d / name
    now = time.time()
    try:
        last = path.stat().st_mtime
    except OSError:
        last = 0
    if now - last < seconds:
        return True
    path.write_text(str(int(now)))
    return False


def port_open(ip: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def read_prop(h, path, name):
    # Ambari-generated XML mixes single-line and multi-line <property> blocks,
    # so parse XML instead of grepping one line.
    py = ("import os,xml.etree.ElementTree as ET;"
          "r=ET.parse(os.environ['P']).getroot();"
          "print(next((p.find('value').text for p in r.findall('property') "
          "if p.find('name').text==os.environ['N']),''))")
    cmd = ("P='%s' N='%s' python3 -c \"%s\"" % (path, name, py))
    return dexec(h, cmd).stdout.strip()


def config_drift() -> List[str]:
    drift = []
    for svc, (path, name, expected) in AUTH_CHECKS.items():
        hosts = (0, 3) if svc == "hbase" else HOSTS
        for h in hosts:
            actual = read_prop(h, path, name)
            if actual != expected:
                drift.append(f"h{h} {svc}: {name}={actual!r} expected {expected!r}")
    # HDFS principals must still be present (Ambari simple config drops them).
    for h in (0, 3):
        if not read_prop(h, f"{CONF}/hdfs-site.xml", "dfs.namenode.kerberos.principal"):
            drift.append(f"h{h} hdfs: dfs.namenode.kerberos.principal missing")
    # Flink: keytab login + simple ZK must stay enabled.
    for h in HOSTS:
        out = dexec(h, f"grep -E '^security.kerberos.login.keytab:|^zookeeper.sasl.disable:' {FLINK_CONF}/flink-conf.yaml 2>/dev/null").stdout
        if 'security.kerberos.login.keytab:' not in out or 'zookeeper.sasl.disable: true' not in out:
            drift.append(f"h{h} flink: kerberos keytab / zookeeper.sasl.disable missing")
    # Kafka: client listener must stay SASL_PLAINTEXT.
    for h in (0, 2, 3):
        out = dexec(h, f"grep -E '^(listeners|security.inter.broker.protocol)=' {KAFKA_CONF}/server.properties 2>/dev/null").stdout
        if 'SASL_PLAINTEXT' not in out:
            drift.append(f"h{h} kafka: SASL_PLAINTEXT listener missing")
    return drift


def snapshot() -> None:
    SNAPSHOT.mkdir(parents=True, exist_ok=True)
    for h, files in SNAP_FILES.items():
        d = SNAPSHOT / f"h{h}"
        d.mkdir(parents=True, exist_ok=True)
        for path in files:
            target = d / path.replace("/", "_")
            res = run(["docker", "cp", f"bigtop_hostname{h}:{path}", str(target)])
            if res.returncode != 0:
                log(f"snapshot WARN h{h} {path}: {(res.stdout or '').strip()}")
        # Keytabs are not XML configs but Ambari's Kerberos request can
        # overwrite them (observed 2026-11-26 on h0: nn/jn/kafka became invalid).
        # Keep a per-host tarball so a bad keytab can be restored quickly.
        kt = d / "keytabs.tgz"
        res = run(["docker", "exec", f"bigtop_hostname{h}", "bash", "-lc",
                   "tar czf /tmp/hodoopforge-keytabs-guard.tgz /etc/security/keytabs"])
        if res.returncode == 0:
            run(["docker", "cp", f"bigtop_hostname{h}:/tmp/hodoopforge-keytabs-guard.tgz", str(kt)])
        log(f"snapshot h{h}: {len(files)} files + keytabs.tgz")


def restore_host(h: int) -> None:
    d = SNAPSHOT / f"h{h}"
    if not d.is_dir():
        return
    for path in SNAP_FILES[h]:
        src = d / path.replace("/", "_")
        if not src.exists():
            continue
        dest_dir = os.path.dirname(path)
        dexec(h, f"mkdir -p {dest_dir}")
        res = run(["docker", "cp", str(src), f"bigtop_hostname{h}:{path}"])
        if res.returncode != 0:
            log(f"restore FAIL h{h} {path}: {(res.stdout or '').strip()}")
            continue
        # Config files are read by service users (hdfs/hbase/hive/yarn).
        owner = "hdfs:hadoop"
        if path.startswith(HBASE_CONF):
            owner = "hbase:hadoop"
        elif path.startswith(HIVE_CONF):
            owner = "hive:hadoop"
        elif path.endswith("yarn-site.xml"):
            owner = "yarn:hadoop"
        elif path.startswith(CONF_DN):
            owner = "hdfs:hadoop"
        elif path.startswith(FLINK_CONF) or path.startswith("/etc/flink/conf-jm2"):
            owner = "flink:hadoop"
        elif path.startswith(KAFKA_CONF):
            owner = "kafka:hadoop"
        dexec(h, f"chown {owner} {path}; chmod 644 {path}")
    log(f"restore h{h}: Kerberos snapshot applied")


def lock_ambari() -> None:
    for h in HOSTS:
        # Do NOT call `systemctl stop ambari-agent`: with the default
        # KillMode=control-group it can kill Hadoop daemons that were started
        # from the agent cgroup (this killed RM/NN repeatedly on 2026-11-26).
        # Kill only the Python agent processes by PID.
        dexec(h, "for p in $(ps -eo pid,args --no-headers "
                 "| grep -E '[A]mbariAgent.py|[a]mbari_agent/main.py|[a]mbari-sudo.sh' "
                 "| awk '{print $1}'); do kill -9 $p 2>/dev/null || true; done; "
                 "ps -eo args --no-headers | grep -Eq '[A]mbariAgent.py|[a]mbari_agent/main.py' "
                 "&& echo still-active || true")
    # IMPORTANT: never call host `systemctl stop/disable` here.  The guard
    # runs as a normal user; polkit would pop up an authentication dialog on
    # the desktop every 30 seconds.  The old watchdog is stopped manually by
    # the operator; this guard only reports whether it is still active.
    try:
        out = run(["systemctl", "is-active", "hodoopforge-watchdog.timer"],
                  capture=True).stdout.strip()
        if out == "active":
            log("WARN hodoopforge-watchdog.timer is active; stop it manually "
                "(guard will not call systemctl to avoid a password prompt)")
    except Exception:
        pass


def start_hdfs() -> None:
    log("fix: starting HDFS (JN -> NN -> DN -> ZKFC)")
    for h in (0, 1, 3):
        dexec(h, f"su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR={CONF}; "
                 f"hdfs --daemon start journalnode' >/dev/null 2>&1")
    time.sleep(8)
    for h in (0, 3):
        dexec(h, f"su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR={CONF}; "
                 f"hdfs --daemon start namenode' >/dev/null 2>&1")
    time.sleep(20)
    for h in (1, 2, 3):
        dexec(h, "export HADOOP_CONF_DIR=%s HDFS_DATANODE_SECURE_USER=hdfs; "
                 "/usr/bin/hdfs --daemon start datanode >/dev/null 2>&1" % CONF_DN,
              user="root")
    time.sleep(12)
    for h in (0, 3):
        dexec(h, f"su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR={CONF}; "
                 f"hdfs --daemon start zkfc' >/dev/null 2>&1")


def start_hbase() -> None:
    log("fix: starting HBase master/regionserver")
    dexec(0, "su -s /bin/bash hbase -c 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk "
             "HADOOP_CONF_DIR=%s HBASE_LOG_DIR=/var/log/hbase "
             "HBASE_PID_DIR=/var/run/hbase HBASE_MANAGES_ZK=false; "
             "/usr/lib/hbase/bin/hbase-daemon.sh start master' >/dev/null 2>&1" % CONF)
    dexec(3, "su -s /bin/bash hbase -c 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk "
             "HADOOP_CONF_DIR=%s HBASE_LOG_DIR=/var/log/hbase "
             "HBASE_PID_DIR=/var/run/hbase HBASE_MANAGES_ZK=false; "
             "/usr/lib/hbase/bin/hbase-daemon.sh start regionserver' >/dev/null 2>&1" % CONF)


def start_hive() -> None:
    log("fix: starting Hive HMS/HS2")
    for h in (0, 1):
        dexec(h, f"su -s /bin/bash hive -c 'export HADOOP_CONF_DIR={CONF} "
                 f"HIVE_CONF_DIR={HIVE_CONF}; nohup /usr/lib/hive/bin/hive "
                 f"--service metastore >/var/log/hive/hms-restart.out 2>&1 &'")
    time.sleep(8)
    for h in (0, 3):
        dexec(h, f"su -s /bin/bash hive -c 'export HADOOP_CONF_DIR={CONF} "
                 f"HIVE_CONF_DIR={HIVE_CONF}; nohup /usr/lib/hive/bin/hive "
                 f"--service hiveserver2 >/var/log/hive/hs2-restart.out 2>&1 &'")


def start_yarn() -> None:
    log("fix: starting YARN RM/NM")
    if not port_open(IPS[0], 8050) and not proc_running(0, '[p]roc_resourcemanager'):
        dexec(0, f"su -s /bin/bash yarn -c 'export HADOOP_CONF_DIR={CONF} "
                 f"YARN_CONF_DIR={CONF}; yarn --daemon start resourcemanager' >/dev/null 2>&1")
    # RM initializes ZK state store + Ranger slowly; wait for RPC before NMs.
    for _ in range(24):
        if port_open(IPS[0], 8050):
            break
        time.sleep(5)
    for h in (1, 2, 3):
        if not proc_running(h, '[p]roc_nodemanager'):
            dexec(h, f"su -s /bin/bash yarn -c 'export HADOOP_CONF_DIR={CONF} "
                     f"YARN_CONF_DIR={CONF}; yarn --daemon start nodemanager' >/dev/null 2>&1")


def start_flink() -> None:
    log("fix: starting Flink JM1/JM2/TMs")
    dexec(0, f"su -s /bin/bash flink -c 'kinit -kt /etc/security/keytabs/flink.headless.keytab "
              f"flink-qixuandata@HODOOPFORGE.LOCAL; export HADOOP_CONF_DIR={CONF} "
              f"FLINK_CONF_DIR={FLINK_CONF} FLINK_PID_DIR=/var/run/flink HOME=/home/flink; "
              f"export HADOOP_CLASSPATH=$(hadoop classpath); "
              f"/usr/lib/flink/bin/jobmanager.sh start' >/dev/null 2>&1")
    for h in (2, 3):
        dexec(h, f"su -s /bin/bash flink -c 'kinit -kt /etc/security/keytabs/flink.headless.keytab "
                  f"flink-qixuandata@HODOOPFORGE.LOCAL; export HADOOP_CONF_DIR={CONF} "
                  f"FLINK_CONF_DIR={FLINK_CONF} FLINK_PID_DIR=/var/run/flink HOME=/home/flink; "
                  f"export HADOOP_CLASSPATH=$(hadoop classpath); "
                  f"/usr/lib/flink/bin/taskmanager.sh start' >/dev/null 2>&1")
    dexec(1, "systemctl restart flink-jobmanager-2 >/dev/null 2>&1 || true")


def start_kafka() -> None:
    log("fix: starting Kafka brokers")
    for h in (0, 2, 3):
        dexec(h, "systemctl start kafka-broker >/dev/null 2>&1 || "
                 "su -s /bin/bash kafka -c 'LOG_DIR=/var/log/kafka "
                 "/usr/lib/kafka/bin/kafka-server-start.sh -daemon "
                 f"{KAFKA_CONF}/server.properties' >/dev/null 2>&1")


def repair() -> int:
    if not SENTINEL.exists():
        return 0
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with LOCK.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0

        lock_ambari()

        drift = config_drift()
        if drift:
            for item in drift:
                log(f"DRIFT {item}")
            for h in HOSTS:
                restore_host(h)
            # Restart the data plane because Ambari may have started it simple.
            dexec(0, "pkill -KILL -f '[p]roc_namenode' || true")
            dexec(3, "pkill -KILL -f '[p]roc_namenode' || true")
            for h in (1, 2, 3):
                dexec(h, "pkill -KILL -f '[p]roc_datanode' || true")
            for h in (0, 3):
                dexec(h, "pkill -KILL -f '[p]roc_master' || true; "
                         "pkill -KILL -f '[p]roc_regionserver' || true")
                dexec(h, "pkill -KILL -f '[H]iveMetaStore' || true; "
                         "pkill -KILL -f '[H]iveServer2' || true")
            dexec(0, "pkill -KILL -f '[p]roc_resourcemanager' || true")
            for h in (1, 2, 3):
                dexec(h, "pkill -KILL -f '[p]roc_nodemanager' || true")
            for h in HOSTS:
                dexec(h, "pkill -KILL -f '[S]tandaloneSessionClusterEntrypoint' || true; "
                         "pkill -KILL -f '[T]askManagerRunner' || true; "
                         "systemctl stop kafka-broker >/dev/null 2>&1 || true")
            time.sleep(3)

        # HDFS: require BOTH NameNodes, not just one.  A single NN can keep
        # clients working while the HA pair is degraded; the old guard missed it.
        nn0 = port_open(IPS[0], 8020)
        nn3 = port_open(IPS[3], 8020)
        if not nn0 and not nn3:
            if proc_running(0, '[p]roc_namenode') or proc_running(3, '[p]roc_namenode'):
                log("wait: NameNode process exists but 8020 not ready yet; not starting a duplicate")
            elif cooling("hdfs", 180):
                log("wait: HDFS start cooldown active")
            else:
                start_hdfs()
        else:
            for h, alive in ((0, nn0), (3, nn3)):
                if not alive and not proc_running(h, '[p]roc_namenode') and not cooling("nn%d" % h, 120):
                    log("fix: starting missing NameNode h%s" % h)
                    dexec(h, f"su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR={CONF}; "
                             f"hdfs --daemon start namenode' >/dev/null 2>&1")
                    time.sleep(10)
                    dexec(h, f"su -s /bin/bash hdfs -c 'export HADOOP_CONF_DIR={CONF}; "
                             f"hdfs --daemon start zkfc' >/dev/null 2>&1")
                elif not alive:
                    log("wait: h%s NameNode process exists but 8020 not ready; not starting duplicate" % h)
        for h in (1, 2, 3):
            if not port_open(IPS[h], 1019) and not proc_running(h, '[p]roc_datanode'):
                log("fix: DataNode h%s missing, starting" % h)
                dexec(h, "export HADOOP_CONF_DIR=%s HDFS_DATANODE_SECURE_USER=hdfs; "
                         "/usr/bin/hdfs --daemon start datanode >/dev/null 2>&1" % CONF_DN,
                      user="root")

        # HBase: wait if master/RS is still starting (process exists).
        if not (port_open(IPS[0], 16000) and port_open(IPS[3], 16020)):
            if proc_running(0, '[p]roc_master') or proc_running(3, '[p]roc_regionserver'):
                log("wait: HBase process exists but RPC not ready; not starting duplicate")
            elif cooling("hbase", 120):
                log("wait: HBase start cooldown active")
            else:
                start_hbase()

        # Hive: wait if HMS/HS2 is still initializing.
        if not (port_open(IPS[0], 9083) and port_open(IPS[1], 9083)
                and port_open(IPS[0], 10000) and port_open(IPS[3], 10000)):
            if (proc_running(0, '[H]iveMetaStore') or proc_running(1, '[H]iveMetaStore')
                    or proc_running(0, '[H]iveServer2') or proc_running(3, '[H]iveServer2')):
                log("wait: Hive process exists but port not ready; not starting duplicate")
            elif cooling("hive", 120):
                log("wait: Hive start cooldown active")
            else:
                start_hive()

        # YARN: RM can take 60-120s with ZK state store + Ranger; wait if running.
        if not port_open(IPS[0], 8050):
            if proc_running(0, '[p]roc_resourcemanager'):
                log("wait: ResourceManager process exists but 8050 not ready; not starting duplicate")
            elif cooling("yarn", 180):
                log("wait: YARN start cooldown active")
            else:
                start_yarn()

        # Flink: wait if JM process exists.
        if not (port_open(IPS[0], 8081) and port_open(IPS[1], 8081)):
            if proc_running(0, '[S]tandaloneSessionClusterEntrypoint') or proc_running(1, '[S]tandaloneSessionClusterEntrypoint'):
                log("wait: Flink JM process exists but REST not ready; not starting duplicate")
            elif cooling("flink", 120):
                log("wait: Flink start cooldown active")
            else:
                start_flink()

        # Kafka
        if not all(port_open(IPS[h], 9092) for h in (0, 2, 3)):
            start_kafka()

    return 0


def status() -> int:
    print(f"sentinel: {'ON' if SENTINEL.exists() else 'OFF'}")
    drift = config_drift() if SENTINEL.exists() else []
    print(f"config drift: {len(drift)}")
    for item in drift:
        print(f"  - {item}")
    checks = [
        ("HDFS 8020 h0", IPS[0], 8020), ("HDFS 8020 h3", IPS[3], 8020),
        ("HBase master", IPS[0], 16000), ("HBase rs", IPS[3], 16020),
        ("HMS h0", IPS[0], 9083), ("HMS h1", IPS[1], 9083),
        ("HS2 h0", IPS[0], 10000), ("HS2 h3", IPS[3], 10000),
        ("YARN RM", IPS[0], 8050),
        ("Flink JM1", IPS[0], 8081), ("Flink JM2", IPS[1], 8081),
        ("Kafka h0", IPS[0], 9092), ("Kafka h2", IPS[2], 9092), ("Kafka h3", IPS[3], 9092),
    ]
    for name, ip, port in checks:
        print(f"  {name}: {'ok' if port_open(ip, port) else 'DOWN'}")
    for h in HOSTS:
        out = dexec(h, "systemctl is-active ambari-agent 2>/dev/null || true").stdout.strip()
        print(f"  h{h} ambari-agent: {out or 'inactive'}")
    return 0


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "snapshot":
        snapshot()
        return 0
    if cmd == "enable":
        SENTINEL.parent.mkdir(parents=True, exist_ok=True)
        SENTINEL.write_text("manual kerberos mode; ambari-agent locked\n")
        snapshot()
        lock_ambari()
        log("guard enabled (sentinel created, agents/watchdog locked)")
        return repair()
    if cmd == "disable":
        if SENTINEL.exists():
            SENTINEL.unlink()
        for h in HOSTS:
            dexec(h, "systemctl start ambari-agent >/dev/null 2>&1 || true")
        log("guard disabled; start hodoopforge-watchdog.timer manually after "
            "the final Ambari cutover (guard does not call host systemctl)")
        log("guard disabled (sentinel removed, agents/watchdog re-enabled)")
        return 0
    if cmd == "status":
        return status()
    if cmd in ("--fix", "fix"):
        return repair()
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
