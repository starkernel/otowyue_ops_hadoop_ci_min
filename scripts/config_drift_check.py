#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Detect drift between the repository, Docker, systemd and Ambari.

Usage:
  python3 scripts/config_drift_check.py            # static + live
  python3 scripts/config_drift_check.py --static   # CI-safe, no Docker
  python3 scripts/config_drift_check.py --json

Exit code 0 = no issues, 1 = drift detected, 2 = checker error.
"""
import argparse
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOSE = os.path.join(REPO, "ambari3/docker-compose.yml")
EXPECTED_MEM = {
    "bigtop_hostname0": 20 * 1024 ** 3,
    "bigtop_hostname1": 10 * 1024 ** 3,
    "bigtop_hostname2": 9 * 1024 ** 3,
    "bigtop_hostname3": 10 * 1024 ** 3,
}
CONTAINERS = list(EXPECTED_MEM)
issues = []


def issue(code, message):
    issues.append({"code": code, "message": message})


def run(cmd, timeout=10):
    try:
        return subprocess.check_output(
            cmd, stderr=subprocess.STDOUT, timeout=timeout, universal_newlines=True
        ).strip()
    except Exception as exc:  # noqa: BLE001
        return "ERROR: %s" % exc


def docker_available():
    return run(["docker", "info", "--format", "{{.ServerVersion}}"], 5).startswith("2")


def check_static():
    try:
        import yaml
    except ImportError:
        issue("compose.yaml", "PyYAML not installed; cannot parse compose")
        return
    try:
        data = yaml.safe_load(open(COMPOSE, encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        issue("compose.parse", "cannot parse compose: %s" % exc)
        return
    services = data.get("services", {})
    for name in CONTAINERS:
        svc = services.get(name, {})
        if svc.get("restart") != "unless-stopped":
            issue("compose.restart", "%s restart=%r (want unless-stopped)" % (name, svc.get("restart")))
        if not svc.get("healthcheck"):
            issue("compose.healthcheck", "%s has no healthcheck" % name)
        logging = svc.get("logging", {})
        if logging.get("driver") != "json-file" or not logging.get("options"):
            issue("compose.logging", "%s has no bounded json-file logging" % name)

    install = open(os.path.join(REPO, "scripts/install_ops_automation.sh"), encoding="utf-8").read()
    if "hodoopforge-containers.service" not in install:
        issue("unit.containers", "install_ops_automation.sh does not install hodoopforge-containers.service")
    if "docker compose up" not in install and "禁止" not in install:
        # The unit must document why it does not use compose.
        issue("unit.containers.doc", "container unit lacks the 'do not compose up' guard note")

    model = os.path.join(REPO, "docs/MANAGEMENT_MODEL.md")
    if not os.path.isfile(model):
        issue("docs.model", "docs/MANAGEMENT_MODEL.md missing")
    else:
        text = open(model, encoding="utf-8").read()
        for needle in ("归属矩阵", "禁止事项", "hodoopforge-containers.service"):
            if needle not in text:
                issue("docs.model.content", "MANAGEMENT_MODEL.md missing %r" % needle)

    watchdog = open(os.path.join(REPO, "scripts/watchdog.py"), encoding="utf-8").read()
    for needle in ("probe_containers", "probe_agents", "probe_mysql", "probe_hive", "probe_kdc", "probe_yarn"):
        if needle not in watchdog:
            issue("watchdog.coverage", "watchdog.py missing %s" % needle)


def check_live():
    if not docker_available():
        issue("docker.unavailable", "docker is not reachable; live checks skipped")
        return
    for name in CONTAINERS:
        state = run(["docker", "inspect", "-f", "{{.State.Running}}", name], 5)
        if state != "true":
            issue("container.state", "%s is not running (%s)" % (name, state))
        policy = run(["docker", "inspect", "-f", "{{.HostConfig.RestartPolicy.Name}}", name], 5)
        if policy != "unless-stopped":
            issue("container.restart", "%s restart=%s" % (name, policy))
        mem = run(["docker", "inspect", "-f", "{{.HostConfig.Memory}}", name], 5)
        try:
            mem = int(mem)
        except ValueError:
            mem = -1
        if mem != EXPECTED_MEM[name]:
            issue("container.memory", "%s memory=%s (want %s)" % (name, mem, EXPECTED_MEM[name]))

    host_unit = run(["systemctl", "is-enabled", "hodoopforge-containers.service"], 5)
    if host_unit != "enabled":
        issue("unit.containers", "hodoopforge-containers.service is %s" % host_unit)

    def unit_enabled(container, unit):
        out = run(["docker", "exec", container, "systemctl", "is-enabled", unit], 8)
        if "enabled" not in out:
            issue("unit.enabled", "%s %s is %s" % (container, unit, out[-80:]))

    unit_enabled("bigtop_hostname0", "mysqld")
    unit_enabled("bigtop_hostname0", "ambari-server")
    for name in CONTAINERS:
        unit_enabled(name, "ambari-agent")

    # Declared ownership of components that are intentionally outside Ambari.
    for container, unit in (
        ("bigtop_hostname2", "kafka-broker"),
        ("bigtop_hostname3", "kafka-broker"),
        ("bigtop_hostname1", "flink-jobmanager-2"),
        ("bigtop_hostname0", "krb5kdc"),
        ("bigtop_hostname3", "krb5kdc"),
        ("bigtop_hostname0", "ambari-metrics-grafana"),
    ):
        enabled = run(["docker", "exec", container, "systemctl", "is-enabled", unit], 8)
        active = run(["docker", "exec", container, "systemctl", "is-active", unit], 8)
        if "enabled" not in enabled:
            issue("unit.owner_enabled", "%s %s is %s" % (container, unit, enabled[-60:]))
        if active != "active":
            issue("unit.owner_active", "%s %s is %s" % (container, unit, active[-60:]))

    for container, units in (
        ("bigtop_hostname1", ("prometheus", "alertmanager")),
        ("bigtop_hostname2", ("prometheus", "alertmanager", "prom_proxy")),
    ):
        for unit in units:
            active = run(["docker", "exec", container, "systemctl", "is-active", unit], 8)
            if active != "active":
                issue("unit.monitoring_active", "%s %s is %s" % (container, unit, active[-60:]))

    # Key configs that Ambari may overwrite if the repo is not the source.
    core = run(["docker", "exec", "bigtop_hostname0", "bash", "-c",
                "grep -c hadoop.proxyuser.hive /etc/hadoop/conf/core-site.xml || true"], 8)
    if core not in ("0", ""):
        issue("config.proxyuser", "core-site still contains hadoop.proxyuser.hive")
    hive = run(["docker", "exec", "bigtop_hostname0", "bash", "-c",
                "grep -A1 'notification.api.auth' /etc/hive/conf/hive-site.xml | tail -1"], 8)
    if "false" not in hive:
        issue("config.hive_notification", "hive-site notification.api.auth is not false")
    flink = run(["docker", "exec", "bigtop_hostname0", "bash", "-c",
                 "grep -c '^high-availability' /etc/flink/conf/flink-conf.yaml || true"], 8)
    try:
        if int(flink) < 5:
            issue("config.flink_ha", "flink-conf has %s HA keys (want >=5)" % flink)
    except ValueError:
        issue("config.flink_ha", "cannot read flink HA config: %s" % flink)

    # Backup freshness (warn only if the timer has not produced anything yet).
    backup_dir = "/var/backups/hodoopforge"
    try:
        entries = [os.path.join(backup_dir, d) for d in os.listdir(backup_dir)]
        entries = [e for e in entries if os.path.isdir(e)]
        if entries:
            import time
            age = time.time() - max(os.path.getmtime(e) for e in entries)
            if age > 30 * 3600:
                issue("backup.stale", "latest backup is %.1f hours old" % (age / 3600))
        else:
            issue("backup.missing", "no backup directory under %s" % backup_dir)
    except PermissionError:
        pass  # non-root runs cannot read the 0700 backup directory
    except OSError as exc:
        issue("backup.unreadable", str(exc))


def main():
    parser = argparse.ArgumentParser(description="HodoopForge config drift checker")
    parser.add_argument("--static", action="store_true", help="skip Docker/systemd checks")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()

    check_static()
    if not args.static:
        check_live()

    if args.json:
        print(json.dumps({"issues": issues}, ensure_ascii=False, indent=2))
    else:
        if issues:
            print("drift detected (%d):" % len(issues))
            for item in issues:
                print("  [%s] %s" % (item["code"], item["message"]))
        else:
            print("no drift")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
