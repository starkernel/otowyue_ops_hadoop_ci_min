#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check Iceberg warehouse alignment (old vs -ha) through the Spark catalog.

- Lists table dirs under both warehouses (HDFS).
- Runs `DESCRIBE EXTENDED iceberg.<db>.<table>` for every -ha table in one
  Beeline session and verifies the Location prefix.
- Reports missing tables and misaligned locations.

Usage:
  python3 datalake/tools/check_lake_alignment.py
  python3 datalake/tools/check_lake_alignment.py --json
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

CONTAINER = os.environ.get("HDFS_CONTAINER", "bigtop_hostname0")
SPARK_CONTAINER = os.environ.get("SPARK_CONTAINER", "bigtop_hostname1")
JDBC = os.environ.get(
    "SPARK_JDBC",
    "jdbc:hive2://bigtop-hostname1.bigtop.apache.org:10016/default;transportMode=binary",
)
OLD = os.environ.get("OLD_WAREHOUSE", "/iceberg-warehouse")
NEW = os.environ.get("NEW_WAREHOUSE", "/iceberg-warehouse-ha")
EXPECTED = os.environ.get(
    "EXPECTED_LOCATION_PREFIX", "hdfs://qixuandata/iceberg-warehouse-ha/"
)


def run(cmd, timeout=300):
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate(timeout=timeout)
    return p.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def hdfs_ls_dirs(base):
    cmd = ["docker", "exec", CONTAINER, "bash", "-c",
           "su -s /bin/bash hdfs -c 'hdfs dfs -ls -d %s/*/*/metadata'" % base]
    rc, out, _ = run(cmd, 120)
    if rc != 0:
        return []
    tables = []
    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        path = parts[-1]
        if path.endswith("/metadata"):
            tables.append(path[len(base) + 1:-len("/metadata")])
    return sorted(tables)


def describe_locations(tables):
    """Return {table: location} using one Beeline session."""
    sql = []
    for t in tables:
        dotted = t.replace("/", ".")
        sql.append("SELECT 'T:%s';" % dotted)
        sql.append("DESCRIBE EXTENDED iceberg.%s;" % dotted)
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write("\n".join(sql) + "\n")
        local = f.name
    remote = "/tmp/lake_alignment.sql"
    run(["docker", "cp", local, "%s:%s" % (SPARK_CONTAINER, remote)], 60)
    os.unlink(local)

    cmd = ["docker", "exec", SPARK_CONTAINER, "bash", "-c",
           "beeline -u '%s' -n spark --outputformat=tsv2 -f %s 2>/dev/null"
           % (JDBC, remote)]
    rc, out, _ = run(cmd, 900)

    result = {}
    cur = None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("T:"):
            cur = s[2:].replace(".", "/")
        elif s.startswith("Location") and cur:
            result[cur] = s.split("\t", 1)[-1].strip()
            cur = None
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    old = hdfs_ls_dirs(OLD)
    new = hdfs_ls_dirs(NEW)
    locs = describe_locations(new)

    aligned = 0
    misaligned = []
    for t in new:
        loc = locs.get(t, "")
        if loc.startswith(EXPECTED):
            aligned += 1
        else:
            misaligned.append({"table": t, "location": loc})

    only_old = sorted(set(old) - set(new))
    only_new = sorted(set(new) - set(old))
    result = {
        "old_tables": len(old),
        "new_tables": len(new),
        "described": len(locs),
        "aligned": aligned,
        "misaligned": len(misaligned),
        "only_in_old": only_old,
        "only_in_new": only_new,
        "misaligned_tables": misaligned[:20],
        "expected_prefix": EXPECTED,
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("tables=%d aligned=%d misaligned=%d described=%d" %
              (len(new), aligned, len(misaligned), len(locs)))
        if only_old:
            print("only_in_old=%s" % ",".join(only_old))
        if only_new:
            print("only_in_new=%s" % ",".join(only_new))
        for m in misaligned[:10]:
            print("  MISALIGNED %s -> %s" % (m["table"], m["location"]))
    return 0 if (not misaligned and not only_old and not only_new) else 1


if __name__ == "__main__":
    sys.exit(main())
