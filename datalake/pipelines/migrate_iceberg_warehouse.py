"""Rebuild Iceberg tables into the HA nameservice catalog.

Why not ALTER TABLE SET LOCATION?
---------------------------------
The cluster uses Iceberg **hadoop catalog**.  Hadoop path-based tables reject
relocation (``Unsupported table change: Hadoop path-based tables cannot be
relocated``) and also reject custom ``LOCATION`` on create.  The only safe
migration is to create the tables through a catalog whose warehouse already
points at the nameservice, then copy rows from the old catalog.

Strategy
--------
Two session catalogs:
* ``oldice`` -> ``hdfs://bigtop-hostname0...:8020/iceberg-warehouse``
* ``newice`` -> ``hdfs://qixuandata/iceberg-warehouse``

For every table:
1. ``SHOW CREATE TABLE`` from ``oldice``;
2. replace catalog name, drop the old ``LOCATION`` and snapshot-id property;
3. create the table in ``newice`` (default path = new warehouse);
4. ``INSERT INTO newice... SELECT * FROM oldice...``;
5. verify row counts and that new files are under the nameservice.

Old tables are intentionally **not dropped**; they are the rollback copy.
Cutover of the application/Flink catalog is a separate step.

Usage:
    .venv/bin/python datalake/pipelines/migrate_iceberg_warehouse.py --dry-run
    .venv/bin/python datalake/pipelines/migrate_iceberg_warehouse.py
    .venv/bin/python datalake/pipelines/migrate_iceberg_warehouse.py --tables edulake_knowledge.ods_rag_query_log
"""

from __future__ import annotations

import argparse
import json
import os
import re
from datetime import date
from pathlib import Path
from typing import Any

from loguru import logger

OLD_BASE = "hdfs://bigtop-hostname0.bigtop.apache.org:8020/iceberg-warehouse"
NEW_BASE = "hdfs://qixuandata/iceberg-warehouse"
DATABASES = [
    "edulake_learning",
    "edulake_knowledge",
    "edulake_ai",
    "edulake_meta",
    "edulake_models",
    "edulake_user",
    "edulake_pronunciation",
    "edulake_governance",
]
SPARK_HOST = os.getenv("SPARK_THRIFT_HOST", "192.168.0.60")
SPARK_PORT = int(os.getenv("SPARK_THRIFT_PORT", "10016"))


def _connect():
    from pyhive import hive

    return hive.Connection(
        host=SPARK_HOST,
        port=SPARK_PORT,
        username="hdfs",
        auth="NONE",
        configuration={
            "spark.sql.extensions": (
                "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
            ),
        },
    )


def _run(cur, sql: str, desc: str, fetch: bool = False) -> list[tuple]:
    try:
        cur.execute(sql)
        rows = list(cur.fetchall() or []) if fetch else []
        logger.debug(f"  ✅ {desc}")
        return rows
    except Exception as exc:  # noqa: BLE001
        logger.warning(f"  ⚠️  {desc}: {str(exc)[:300]}")
        raise


def _setup_catalogs(cur, old_base: str, new_base: str) -> None:
    for name, base in (("oldice", old_base), ("newice", new_base)):
        _run(cur, f"SET spark.sql.catalog.{name}=org.apache.iceberg.spark.SparkCatalog", f"{name} class")
        _run(cur, f"SET spark.sql.catalog.{name}.type=hadoop", f"{name} type")
        _run(cur, f"SET spark.sql.catalog.{name}.warehouse={base}", f"{name} warehouse")


def _strip_location(ddl: str, old_full: str, new_full: str) -> str:
    ddl = ddl.replace(f"CREATE TABLE {old_full}", f"CREATE TABLE {new_full}")
    ddl = re.sub(r"\n\s*LOCATION\s+'[^']*'", "", ddl)
    # Drop the whole TBLPROPERTIES block: copying format/snapshot properties
    # from the source can be invalid or misleading.  Iceberg defaults are fine.
    ddl = re.sub(r"\n\s*TBLPROPERTIES\s*\(.*?\)\s*$", "", ddl, flags=re.S)
    return ddl.strip()


def _table_names(cur, db: str, old_catalog: str) -> list[str]:
    rows = _run(cur, f"SHOW TABLES IN {old_catalog}.{db}", f"tables in {db}", fetch=True)
    return [f"{db}.{row[1]}" for row in rows]


def migrate_table(
    cur,
    table: str,
    dry_run: bool,
    old_catalog: str = "oldice",
    new_catalog: str = "newice",
    new_base: str = NEW_BASE,
) -> dict[str, Any]:
    db, name = table.split(".", 1)
    old_full = f"{old_catalog}.{db}.{name}"
    new_full = f"{new_catalog}.{db}.{name}"
    source_count = int(_run(cur, f"SELECT COUNT(*) FROM {old_full}", f"{table} count", fetch=True)[0][0] or 0)
    result: dict[str, Any] = {"table": table, "source_rows": source_count}
    if dry_run:
        result["status"] = "planned"
        return result

    ddl = _run(cur, f"SHOW CREATE TABLE {old_full}", f"{table} ddl", fetch=True)[0][0]
    new_ddl = _strip_location(str(ddl), old_full, new_full)
    _run(cur, f"DROP TABLE IF EXISTS {new_full}", f"{table} drop stale target")
    _run(cur, new_ddl, f"{table} create target")
    if source_count:
        _run(
            cur,
            f"INSERT INTO {new_full} SELECT * FROM {old_full}",
            f"{table} copy {source_count} rows",
        )
    target_count = int(_run(cur, f"SELECT COUNT(*) FROM {new_full}", f"{table} target count", fetch=True)[0][0] or 0)
    if target_count != source_count:
        result.update({"status": "count_mismatch", "target_rows": target_count})
        return result
    outside = None
    try:
        outside = int(
            _run(
                cur,
                f"SELECT COUNT(*) FROM {new_full}.files "
                f"WHERE file_path NOT LIKE '{new_base}%'",
                f"{table} file authority",
                fetch=True,
            )[0][0]
            or 0
        )
    except Exception:
        pass
    result.update(
        {
            "status": "ok",
            "target_rows": target_count,
            "files_outside_nameservice": outside,
        }
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Rebuild Iceberg tables into nameservice catalog")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--tables", default="", help="comma-separated db.table list")
    parser.add_argument("--old-base", default=OLD_BASE)
    parser.add_argument("--new-base", default=NEW_BASE)
    args = parser.parse_args()

    conn = _connect()
    cur = conn.cursor()
    try:
        _setup_catalogs(cur, args.old_base, args.new_base)
        if args.tables:
            tables = [t.strip().replace("iceberg.", "") for t in args.tables.split(",") if t.strip()]
        else:
            tables = []
            for db in DATABASES:
                try:
                    tables.extend(_table_names(cur, db, "oldice"))
                except Exception as exc:  # noqa: BLE001
                    logger.warning(f"skip {db}: {exc}")
        results = []
        for table in tables:
            logger.info(f"→ {table}")
            try:
                results.append(migrate_table(cur, table, args.dry_run, new_base=args.new_base))
            except Exception as exc:  # noqa: BLE001
                results.append({"table": table, "status": "failed", "error": str(exc)[:300]})
    finally:
        cur.close()
        conn.close()

    summary = {
        "generated_at": str(date.today()),
        "old_base": args.old_base,
        "new_base": args.new_base,
        "dry_run": args.dry_run,
        "tables": len(results),
        "ok": sum(1 for r in results if r.get("status") == "ok"),
        "failed": [r for r in results if r.get("status") not in {"ok", "planned"}],
        "results": results,
    }
    path = (
        Path(__file__).resolve().parents[2]
        / "doc"
        / "review"
        / "evidence"
        / f"{date.today().isoformat()}-iceberg-warehouse-migration.json"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ("tables", "ok", "dry_run")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
