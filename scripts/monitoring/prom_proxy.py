#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only Prometheus failover proxy (:9099).

The two Prometheus instances scrape independently and do not share storage, so
a query cannot be answered by both.  This proxy gives one stable endpoint:
it always talks to the first healthy upstream and transparently retries the
next one when a request fails.

    GET  /api/v1/query?...      proxied
    GET  /api/v1/targets        proxied
    GET  /-/ready               proxy readiness (any upstream up)
    GET  /proxy/status          JSON health of every upstream

Environment:
  PROM_PROXY_PORT       default 9099
  PROM_PROXY_UPSTREAMS  default "http://172.19.0.5:9090,http://172.19.0.3:9090"
"""
import json
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

PORT = int(os.environ.get("PROM_PROXY_PORT", "9099"))
UPSTREAMS = [
    u.strip().rstrip("/")
    for u in os.environ.get(
        "PROM_PROXY_UPSTREAMS",
        "http://172.19.0.5:9090,http://172.19.0.3:9090",
    ).split(",")
    if u.strip()
]

_state = {u: {"healthy": True, "checked": 0.0, "error": ""} for u in UPSTREAMS}


def _check(url, timeout=3):
    try:
        with urlopen(url + "/-/ready", timeout=timeout) as response:
            return 200 <= response.status < 300, ""
    except HTTPError as exc:
        return False, "HTTP %s" % exc.code
    except (URLError, socket.timeout, OSError) as exc:
        return False, str(exc)[:120]


def refresh(force=False):
    now = time.time()
    for url in UPSTREAMS:
        state = _state[url]
        if force or now - state["checked"] > 10:
            ok, error = _check(url)
            state.update(healthy=ok, checked=now, error=error)


def ordered_upstreams():
    refresh()
    healthy = [u for u in UPSTREAMS if _state[u]["healthy"]]
    unhealthy = [u for u in UPSTREAMS if not _state[u]["healthy"]]
    return healthy + unhealthy


def proxy(method, path, body, headers):
    errors = []
    for base in ordered_upstreams():
        request = Request(base + path, data=body, method=method)
        for key in ("Accept", "Content-Type", "Authorization"):
            if headers.get(key):
                request.add_header(key, headers[key])
        try:
            with urlopen(request, timeout=30) as response:
                return response.status, response.headers.get("Content-Type", "application/json"), response.read()
        except HTTPError as exc:
            # A 4xx/5xx from Prometheus is a real answer, not a transport error.
            return exc.code, exc.headers.get("Content-Type", "application/json"), exc.read()
        except (URLError, socket.timeout, OSError) as exc:
            errors.append("%s: %s" % (base, exc))
            _state[base].update(healthy=False, checked=time.time(), error=str(exc)[:120])
    payload = json.dumps({"status": "error", "error": "; ".join(errors)}).encode()
    return 503, "application/json", payload


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _respond(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/-/ready":
            ready = any(s["healthy"] for s in _state.values())
            refresh(force=True)
            ready = any(s["healthy"] for s in _state.values())
            self._respond(200 if ready else 503, "text/plain", b"ready\n" if ready else b"no upstream\n")
            return
        if parsed.path == "/proxy/status":
            refresh(force=True)
            self._respond(200, "application/json", json.dumps(_state, indent=2).encode())
            return
        status, content_type, body = proxy("GET", self.path, None, self.headers)
        self._respond(status, content_type, body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        status, content_type, payload = proxy("POST", self.path, body, self.headers)
        self._respond(status, content_type, payload)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    refresh(force=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
