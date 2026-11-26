#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Alertmanager webhook receiver (:9500).

Why: Alertmanager can evaluate and group alerts, but without a receiver the
alerts only live in its UI.  This receiver gives us a durable local log and an
optional forward to a real IM/phone gateway.

Environment:
  ALERT_LOG       default /var/log/hodoopforge-alerts.jsonl
  ALERT_WEBHOOK_URL  optional upstream webhook; the original payload is forwarded
  ALERT_WEBHOOK_PORT default 9500

The JSONL log is intentionally simple so it can be tailed, shipped or replayed.
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import Request, urlopen

PORT = int(os.environ.get("ALERT_WEBHOOK_PORT", "9500"))
LOG_PATH = os.environ.get("ALERT_LOG", "/var/log/hodoopforge-alerts.jsonl")
FORWARD_URL = os.environ.get("ALERT_WEBHOOK_URL", "").strip()


def summarize(payload):
    """Flatten an Alertmanager v4 payload into one record per alert."""
    records = []
    common = payload or {}
    for alert in common.get("alerts", []):
        labels = alert.get("labels", {}) or {}
        annotations = alert.get("annotations", {}) or {}
        records.append(
            {
                "received_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "status": alert.get("status", common.get("status", "")),
                "alertname": labels.get("alertname", ""),
                "severity": labels.get("severity", ""),
                "instance": labels.get("instance", ""),
                "summary": annotations.get("summary", ""),
                "description": annotations.get("description", ""),
                "startsAt": alert.get("startsAt", ""),
                "endsAt": alert.get("endsAt", ""),
                "fingerprint": alert.get("fingerprint", ""),
            }
        )
    return records


def append_log(records):
    if not records:
        return
    directory = os.path.dirname(LOG_PATH)
    if directory and not os.path.isdir(directory):
        os.makedirs(directory)
    with open(LOG_PATH, "a") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def forward(raw):
    if not FORWARD_URL:
        return
    try:
        request = Request(
            FORWARD_URL,
            data=raw,
            headers={"Content-Type": "application/json"},
        )
        urlopen(request, timeout=5).read()
    except Exception:  # noqa: BLE001
        pass


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path not in ("/alerts", "/"):
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8", "replace"))
        except ValueError:
            payload = {}
        records = summarize(payload)
        append_log(records)
        forward(raw)
        body = json.dumps({"received": len(records)}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/-/healthy":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
        elif self.path == "/alerts":
            try:
                with open(LOG_PATH, "r") as handle:
                    lines = handle.readlines()[-50:]
            except OSError:
                lines = []
            body = "".join(lines).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
