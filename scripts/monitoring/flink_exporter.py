#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Flink REST -> Prometheus exporter (:9403).

Exposes job state, TaskManager count and checkpoint counters without enabling
Flink's metric reporter (which would require a JobManager restart).
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import urlopen

PORT = int(os.environ.get("FLINK_EXPORTER_PORT", "9403"))
FLINK = os.environ.get("FLINK_URL", "http://172.19.0.2:8081")
BASES = [u.strip().rstrip("/") for u in os.environ.get(
    "FLINK_URLS", FLINK + ",http://172.19.0.5:8081").split(",") if u.strip()]
CACHE_TTL = float(os.environ.get("FLINK_EXPORTER_CACHE_TTL", "10"))
_cache = {"ts": 0.0, "body": ""}


def get_json(path, timeout=6):
    last = None
    for base in BASES:
        try:
            with urlopen(base + path, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8", "replace"))
        except Exception as exc:  # noqa: BLE001
            last = exc
    raise last


def render(jobs_payload, tm_payload, checkpoints):
    jobs = (jobs_payload or {}).get("jobs", [])
    running = [job for job in jobs if job.get("state") == "RUNNING"]
    tms = (tm_payload or {}).get("taskmanagers", [])
    counts = (checkpoints or {}).get("counts", {})
    lines = [
        "flink_up 1",
        "flink_job_running %d" % (1 if running else 0),
        "flink_taskmanagers %d" % len(tms),
    ]
    for job in jobs:
        lines.append(
            'flink_jobs{state="%s"} 1' % (job.get("state") or "UNKNOWN")
        )
    if running:
        job = running[0]
        jid = job.get("jid", "")
        lines.append('flink_checkpoints_completed{job="%s"} %s'
                     % (jid, counts.get("completed", 0)))
        lines.append('flink_checkpoints_failed{job="%s"} %s'
                     % (jid, counts.get("failed", 0)))
        lines.append('flink_checkpoints_restored{job="%s"} %s'
                     % (jid, counts.get("restored", 0)))
    return "\n".join(lines) + "\n"


def collect():
    try:
        jobs = get_json("/jobs/overview")
        tms = get_json("/taskmanagers")
        checkpoints = {}
        running = [j for j in jobs.get("jobs", []) if j.get("state") == "RUNNING"]
        if running:
            checkpoints = get_json("/jobs/%s/checkpoints" % running[0].get("jid"))
        return render(jobs, tms, checkpoints)
    except Exception:  # noqa: BLE001
        return "flink_up 0\n"


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
