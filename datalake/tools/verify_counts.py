#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Verify oldice vs newice row counts for all tables and report mismatches."""
import json
import re
import sys

sys.path.insert(0, "/tmp/opencode")
import migrate_beeline as m


def list_new(db):
    rc, out = m.run_beeline(m.SETS + "SHOW TABLES IN newice.%s;\n" % db, 120)
    if rc != 0:
        raise RuntimeError("list new %s failed: %s" % (db, out[-400:]))
    tables = []
    started = False
    for line in out.splitlines():
        if line.startswith("namespace\ttableName"):
            started = True
            continue
        if started and line.strip():
            parts = line.split("\t")
            if len(parts) >= 2:
                tables.append("%s.%s" % (db, parts[1]))
    return tables


def main():
    old, new = [], []
    for db in m.DBS:
        try:
            old.extend(m.list_tables(db))
        except Exception as exc:
            print("skip old %s: %s" % (db, exc))
        try:
            new.extend(list_new(db))
        except Exception as exc:
            print("skip new %s: %s" % (db, exc))
    print("old=%d new=%d" % (len(old), len(new)))
    union = sorted(set(old) | set(new))
    sql = [m.SETS]
    for t in union:
        sql.append("SELECT '%s', (SELECT COUNT(*) FROM oldice.%s), (SELECT COUNT(*) FROM newice.%s);\n" % (t, t, t))
    rc, out = m.run_beeline("".join(sql), 1800)
    if rc != 0:
        print("verify failed: %s" % out[-800:])
        return
    rows = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[0].count(".") >= 1 and re.match(r"^\d+$", parts[1].strip()):
            rows.append((parts[0].strip(), int(parts[1]), int(parts[2])))
    bad = [r for r in rows if r[1] != r[2]]
    missing = [t for t in old if t not in set(r[0] for r in rows)]
    print(json.dumps({"verified": len(rows), "mismatch": len(bad),
                      "missing": missing, "bad": bad[:50]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
