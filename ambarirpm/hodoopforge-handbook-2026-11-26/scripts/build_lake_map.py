#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Embed docs/lake-map-data.json into docs/lake-map.html.

Why: the old page used fetch("./lake-map-data.json"), which fails when the
HTML is opened via file:// (CORS) or copied alone into another system.  The
map is now a single self-contained HTML file; the JSON snapshot stays in the
repo for tooling and is also embedded in the page.

Usage:
  python3 scripts/build_lake_map.py
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "docs", "lake-map-data.json")
HTML = os.path.join(ROOT, "docs", "lake-map.html")
START = '<script id="lake-map-data" type="application/json">'
END = '</script>'


def main():
    with open(DATA, encoding="utf-8") as handle:
        data = json.load(handle)
    with open(HTML, encoding="utf-8") as handle:
        html = handle.read()
    if START not in html:
        print("ERROR: embedded-data marker missing in %s" % HTML, file=sys.stderr)
        return 1
    head, rest = html.split(START, 1)
    _, tail = rest.split(END, 1)
    payload = json.dumps(data, ensure_ascii=False, indent=1).replace("</", "<\\/")
    with open(HTML, "w", encoding="utf-8") as handle:
        handle.write(head + START + "\n" + payload + "\n" + END + tail)
    print("embedded %s into %s (%d bytes JSON)" % (DATA, HTML, len(payload)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
