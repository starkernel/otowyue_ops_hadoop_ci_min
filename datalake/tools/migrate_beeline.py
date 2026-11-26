#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Beeline-based Iceberg oldice -> newice migration (no PyHive/SASL dependency)."""
import argparse
import base64
import json
import re
import subprocess
import sys

H1 = "bigtop_hostname1"
JDBC = "jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/default;transportMode=binary"
OLD = "hdfs://qixuandata/iceberg-warehouse"
NEW = "hdfs://qixuandata/iceberg-warehouse-ha"
DBS = ["edulake_learning", "edulake_knowledge", "edulake_ai", "edulake_meta",
       "edulake_models", "edulake_user", "edulake_pronunciation", "edulake_governance"]

SETS = (
    "SET spark.sql.catalog.oldice=org.apache.iceberg.spark.SparkCatalog;\n"
    "SET spark.sql.catalog.oldice.type=hadoop;\n"
    "SET spark.sql.catalog.oldice.warehouse=%s;\n"
    "SET spark.sql.catalog.newice=org.apache.iceberg.spark.SparkCatalog;\n"
    "SET spark.sql.catalog.newice.type=hadoop;\n"
    "SET spark.sql.catalog.newice.warehouse=%s;\n"
) % (OLD, NEW)


def run_beeline(sql, timeout=300):
    b64 = base64.b64encode(sql.encode("utf-8")).decode("ascii")
    cmd = (
        "echo %s | base64 -d > /tmp/mig_q.sql; "
        "beeline -u '%s' -n spark --silent=true --outputformat=tsv2 -f /tmp/mig_q.sql 2>&1"
    ) % (b64, JDBC)
    p = subprocess.Popen(["docker", "exec", H1, "bash", "-c", cmd],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out, _ = p.communicate(timeout=timeout)
    return p.returncode, out.decode("utf-8", "replace")


def list_tables(db):
    rc, out = run_beeline(SETS + "SHOW TABLES IN oldice.%s;\n" % db, 120)
    if rc != 0:
        raise RuntimeError("list %s failed: %s" % (db, out[-500:]))
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


def show_create(table):
    rc, out = run_beeline(SETS + "SHOW CREATE TABLE oldice.%s;\n" % table, 120)
    if rc != 0:
        raise RuntimeError("ddl %s failed: %s" % (table, out[-500:]))
    lines = out.splitlines()
    try:
        i = lines.index("createtab_stmt")
    except ValueError:
        raise RuntimeError("no ddl header for %s: %s" % (table, out[-500:]))
    ddl = "\n".join(lines[i + 1:]).strip()
    if not ddl.startswith("CREATE TABLE"):
        raise RuntimeError("unexpected ddl for %s: %s" % (table, ddl[:300]))
    return ddl


def strip_ddl(ddl, table):
    ddl = ddl.replace("CREATE TABLE oldice.%s" % table, "CREATE TABLE newice.%s" % table, 1)
    ddl = re.sub(r"\n\s*LOCATION\s+'[^']*'", "", ddl)
    ddl = re.sub(r"\n\s*TBLPROPERTIES\s*\(.*?\)\s*$", "", ddl, flags=re.S)
    return ddl.strip()


def count(table, catalog):
    rc, out = run_beeline(SETS + "SELECT COUNT(*) FROM %s.%s;\n" % (catalog, table), 180)
    if rc != 0:
        raise RuntimeError("count %s.%s failed: %s" % (catalog, table, out[-500:]))
    for line in out.splitlines():
        line = line.strip()
        if re.match(r"^\d+$", line):
            return int(line)
    raise RuntimeError("cannot parse count for %s: %s" % (table, out[-500:]))


def migrate_one(table):
    ddl = strip_ddl(show_create(table), table)
    sql = (
        SETS
        + "DROP TABLE IF EXISTS newice.%s;\n" % table
        + ddl + ";\n"
        + "INSERT INTO newice.%s SELECT * FROM oldice.%s;\n" % (table, table)
    )
    rc, out = run_beeline(sql, 1800)
    if rc != 0:
        raise RuntimeError("migrate %s failed: %s" % (table, out[-1200:]))
    old_n = count(table, "oldice")
    new_n = count(table, "newice")
    return {"table": table, "old_rows": old_n, "new_rows": new_n,
            "status": "ok" if old_n == new_n else "count_mismatch"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--tables", default="")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()

    if args.tables:
        tables = [t.strip().replace("iceberg.", "") for t in args.tables.split(",") if t.strip()]
    else:
        tables = []
        for db in DBS:
            try:
                tables.extend(list_tables(db))
            except Exception as exc:
                print("skip %s: %s" % (db, exc))
    print("tables=%d" % len(tables))

    if args.dry_run:
        for t in tables:
            try:
                print("  %s old=%d" % (t, count(t, "oldice")))
            except Exception as exc:
                print("  %s ERR %s" % (t, str(exc)[:200]))
        return

    results = []
    for t in tables:
        try:
            r = migrate_one(t)
        except Exception as exc:
            r = {"table": t, "status": "failed", "error": str(exc)[:500]}
        print(json.dumps(r, ensure_ascii=False))
        results.append(r)
        if r.get("status") != "ok":
            print("STOP on failure: %s" % t)
            break
    print(json.dumps({"total": len(results),
                      "ok": sum(1 for r in results if r.get("status") == "ok"),
                      "failed": [r for r in results if r.get("status") != "ok"]},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
