#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ambari alerts/services -> Prometheus exporter (:9402).

Reads credentials from /etc/hodoopforge/ambari.env (or AMBARI_USER/AMBARI_PASS)
and exposes alert counts and service states.  This is the bridge that lets
Prometheus/Alertmanager reuse Ambari's HARD alert definitions without
duplicating every check.
"""
import base64
import json
import os
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import Request, urlopen

PORT = int(os.environ.get("AMBARI_EXPORTER_PORT", "9402"))
CACHE_TTL = float(os.environ.get("AMBARI_EXPORTER_CACHE_TTL", "15"))


def load_env_file(path="/etc/hodoopforge/ambari.env"):
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


load_env_file()
AMBARI = os.environ.get("AMBARI_URL", "http://localhost:20609")
CLUSTER = os.environ.get("AMBARI_CLUSTER", "qixuandata")
USER = os.environ.get("AMBARI_USER", "admin")
PASSWORD = os.environ.get("AMBARI_PASS", "admin")
_cache = {"ts": 0.0, "body": ""}


def api(path, timeout=8):
    url = "%s/api/v1/clusters/%s%s" % (AMBARI, CLUSTER, path)
    request = Request(url)
    token = base64.b64encode(("%s:%s" % (USER, PASSWORD)).encode()).decode()
    request.add_header("Authorization", "Basic " + token)
    request.add_header("X-Requested-By", "ambari")
    with urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def alert_counts(items):
    return Counter(item["Alert"]["state"] for item in items)


def service_states(items):
    return {
        item["ServiceInfo"]["service_name"]: item["ServiceInfo"]["state"]
        for item in items
    }


def render(counts, services):
    lines = ["ambari_up 1"]
    for state in ("OK", "WARNING", "CRITICAL", "UNKNOWN"):
        lines.append('ambari_alerts{state="%s"} %d' % (state, counts.get(state, 0)))
    for name in sorted(services):
        lines.append(
            'ambari_services{service="%s",state="%s"} 1' % (name, services[name])
        )
    return "\n".join(lines) + "\n"


def collect():
    try:
        alerts = api("/alerts?fields=Alert/state&page_size=500")
        services = api(
            "/services?fields=ServiceInfo/service_name,ServiceInfo/state"
        )
        return render(
            alert_counts(alerts.get("items", [])),
            service_states(services.get("items", [])),
        )
    except Exception:  # noqa: BLE001
        return "ambari_up 0\n"


def cached_metrics():
    now = time.time()
    if now - _cache["ts"] < CACHE_TTL and _cache["body"]:
        return _cache["body"]
    body = collect()
    _cache["body"] = body
    _cache["ts"] = now
    return body


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/metrics", "/"):
            body = cached_metrics().encode()
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
