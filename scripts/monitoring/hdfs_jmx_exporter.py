#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Minimal HDFS NameNode JMX -> Prometheus exporter.

Hadoop exposes JSON at /jmx?qry=...; Prometheus cannot scrape that directly and
we do not want to restart the NameNodes with a JMX agent.  This sidecar polls
both NameNodes and renders a small text exposition on :9401/metrics.

Metrics:
  hdfs_namenode_up{host}
  hdfs_namenode_active{host}
  hdfs_capacity_total_bytes{host}
  hdfs_capacity_used_bytes{host}
  hdfs_capacity_free_bytes{host}
  hdfs_missing_blocks{host}
  hdfs_under_replicated_blocks{host}
  hdfs_pending_deletion_blocks{host}
  hdfs_corrupt_blocks{host}
  hdfs_blocks_total{host}
  hdfs_live_datanodes{host}
  hdfs_last_checkpoint_timestamp_seconds{host}
  hdfs_transactions_since_last_checkpoint{host}
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.error import URLError
from urllib.request import urlopen

NAMENODES = [
    ("bigtop-hostname0", "172.19.0.2", 50070),
    ("bigtop-hostname3", "172.19.0.4", 50070),
]
CACHE_TTL = float(os.environ.get("HDFS_EXPORTER_CACHE_TTL", "10"))
PORT = int(os.environ.get("HDFS_EXPORTER_PORT", "9401"))
_cache = {"ts": 0.0, "body": ""}


def jmx(host, port, bean, timeout=4):
    url = "http://%s:%d/jmx?qry=%s" % (host, port, bean)
    with urlopen(url, timeout=timeout) as response:
        data = json.loads(response.read().decode("utf-8", "replace"))
    beans = data.get("beans") or []
    return beans[0] if beans else {}


def parse_status(bean):
    return (bean.get("State") or "").strip().lower()


def parse_inode_info(bean):
    live = bean.get("LiveNodes") or "{}"
    try:
        live_count = len(json.loads(live))
    except Exception:  # noqa: BLE001
        live_count = 0
    return {
        "capacity_total": float(bean.get("Total") or 0),
        "capacity_used": float(bean.get("Used") or 0),
        "capacity_free": float(bean.get("Free") or 0),
        "live_datanodes": float(live_count),
    }


def parse_fsnamesystem(bean):
    return {
        "missing_blocks": float(bean.get("MissingBlocks") or 0),
        "under_replicated": float(bean.get("UnderReplicatedBlocks") or 0),
        "pending_deletion": float(bean.get("PendingDeletionBlocks") or 0),
        "corrupt_blocks": float(bean.get("CorruptBlocks") or 0),
        "blocks_total": float(bean.get("BlocksTotal") or 0),
        "last_checkpoint_ms": float(bean.get("LastCheckpointTime") or 0),
        "txns_since_checkpoint": float(
            bean.get("TransactionsSinceLastCheckpoint") or 0
        ),
    }


def render_node(host, state, info, fs):
    """Pure renderer used by tests and by collect()."""
    lines = [
        'hdfs_namenode_up{host="%s"} 1' % host,
        'hdfs_namenode_active{host="%s"} %d'
        % (host, 1 if state == "active" else 0),
        'hdfs_capacity_total_bytes{host="%s"} %.0f' % (host, info["capacity_total"]),
        'hdfs_capacity_used_bytes{host="%s"} %.0f' % (host, info["capacity_used"]),
        'hdfs_capacity_free_bytes{host="%s"} %.0f' % (host, info["capacity_free"]),
        'hdfs_live_datanodes{host="%s"} %.0f' % (host, info["live_datanodes"]),
        'hdfs_missing_blocks{host="%s"} %.0f' % (host, fs["missing_blocks"]),
        'hdfs_under_replicated_blocks{host="%s"} %.0f' % (host, fs["under_replicated"]),
        'hdfs_pending_deletion_blocks{host="%s"} %.0f' % (host, fs["pending_deletion"]),
        'hdfs_corrupt_blocks{host="%s"} %.0f' % (host, fs["corrupt_blocks"]),
        'hdfs_blocks_total{host="%s"} %.0f' % (host, fs["blocks_total"]),
        'hdfs_last_checkpoint_timestamp_seconds{host="%s"} %.0f'
        % (host, fs["last_checkpoint_ms"] / 1000.0),
        'hdfs_transactions_since_last_checkpoint{host="%s"} %.0f'
        % (host, fs["txns_since_checkpoint"]),
    ]
    return lines


def collect():
    lines = []
    for host, ip, port in NAMENODES:
        try:
            state = parse_status(
                jmx(ip, port, "Hadoop:service=NameNode,name=NameNodeStatus")
            )
            info = parse_inode_info(
                jmx(ip, port, "Hadoop:service=NameNode,name=NameNodeInfo")
            )
            fs = parse_fsnamesystem(
                jmx(ip, port, "Hadoop:service=NameNode,name=FSNamesystem")
            )
            lines.extend(render_node(host, state, info, fs))
        except (URLError, OSError, ValueError, KeyError):
            lines.append('hdfs_namenode_up{host="%s"} 0' % host)
            lines.append('hdfs_namenode_active{host="%s"} 0' % host)
    return "\n".join(lines) + "\n"


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

    def log_message(self, fmt, *args):  # keep journald quiet
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
