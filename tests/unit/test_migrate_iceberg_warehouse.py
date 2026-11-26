"""Unit tests for datalake/pipelines/migrate_iceberg_warehouse.py."""
from __future__ import annotations

import pytest


class FakeCursor:
    """Minimal DB-API cursor that answers the pipeline's SQL patterns."""

    def __init__(self, source_rows=3, target_rows=3, files_outside=0, files_error=False):
        self.source_rows = source_rows
        self.target_rows = target_rows
        self.files_outside = files_outside
        self.files_error = files_error
        self.executed = []
        self._rows = []

    def execute(self, sql):
        self.executed.append(sql)
        self._rows = []
        if sql.startswith("SHOW CREATE TABLE"):
            self._rows = [
                (
                    "CREATE TABLE oldice.demo.t (id int)\n"
                    "USING iceberg\n"
                    "LOCATION 'hdfs://old/iceberg-warehouse/demo/t'\n"
                    "TBLPROPERTIES ('format-version'='2')",
                )
            ]
        elif sql.startswith("SELECT COUNT(*) FROM oldice."):
            self._rows = [(self.source_rows,)]
        elif ".files" in sql:
            if self.files_error:
                raise RuntimeError("no metadata table")
            self._rows = [(self.files_outside,)]
        elif sql.startswith("SELECT COUNT(*) FROM newice."):
            self._rows = [(self.target_rows,)]
        elif sql.startswith("SHOW TABLES IN"):
            self._rows = [("edulake_ai", "ods_a"), ("edulake_ai", "ods_b")]

    def fetchall(self):
        return list(self._rows)


def test_strip_location_renames_and_drops_paths(migrate_pipeline_module):
    mod = migrate_pipeline_module
    ddl = (
        "CREATE TABLE oldice.demo.t (id int)\n"
        "USING iceberg\n"
        "LOCATION 'hdfs://old/iceberg-warehouse/demo/t'\n"
        "TBLPROPERTIES ('format-version'='2')"
    )
    out = mod._strip_location(ddl, "oldice.demo.t", "newice.demo.t")
    assert out.startswith("CREATE TABLE newice.demo.t")
    assert "LOCATION" not in out
    assert "TBLPROPERTIES" not in out


def test_setup_catalogs_issues_six_set_statements(migrate_pipeline_module):
    mod = migrate_pipeline_module
    cur = FakeCursor()
    mod._setup_catalogs(cur, "hdfs://old", "hdfs://new")
    assert len(cur.executed) == 6
    assert any("oldice.warehouse=hdfs://old" in s for s in cur.executed)
    assert any("newice.warehouse=hdfs://new" in s for s in cur.executed)


def test_table_names_maps_second_column(migrate_pipeline_module):
    mod = migrate_pipeline_module
    cur = FakeCursor()
    assert mod._table_names(cur, "edulake_ai", "oldice") == [
        "edulake_ai.ods_a",
        "edulake_ai.ods_b",
    ]


def test_migrate_table_dry_run(migrate_pipeline_module):
    mod = migrate_pipeline_module
    cur = FakeCursor(source_rows=11)
    result = mod.migrate_table(cur, "demo.t", dry_run=True)
    assert result == {"table": "demo.t", "source_rows": 11, "status": "planned"}
    # Only the source count query should have run.
    assert len(cur.executed) == 1


def test_migrate_table_ok(migrate_pipeline_module):
    mod = migrate_pipeline_module
    cur = FakeCursor(source_rows=3, target_rows=3, files_outside=0)
    result = mod.migrate_table(cur, "demo.t", dry_run=False)
    assert result["status"] == "ok"
    assert result["source_rows"] == 3
    assert result["target_rows"] == 3
    assert result["files_outside_nameservice"] == 0
    assert any("INSERT INTO newice.demo.t" in s for s in cur.executed)
    assert any("DROP TABLE IF EXISTS newice.demo.t" in s for s in cur.executed)


def test_migrate_table_count_mismatch(migrate_pipeline_module):
    mod = migrate_pipeline_module
    cur = FakeCursor(source_rows=3, target_rows=2)
    result = mod.migrate_table(cur, "demo.t", dry_run=False)
    assert result["status"] == "count_mismatch"
    assert result["target_rows"] == 2


def test_migrate_table_tolerates_missing_files_metadata(migrate_pipeline_module):
    mod = migrate_pipeline_module
    cur = FakeCursor(source_rows=3, target_rows=3, files_error=True)
    result = mod.migrate_table(cur, "demo.t", dry_run=False)
    assert result["status"] == "ok"
    assert result["files_outside_nameservice"] is None


def test_migrate_table_rejects_bad_name(migrate_pipeline_module):
    mod = migrate_pipeline_module
    cur = FakeCursor()
    with pytest.raises(ValueError):
        mod.migrate_table(cur, "no_database_table", dry_run=True)


def test_new_base_points_at_ha_namespace(migrate_pipeline_module):
    mod = migrate_pipeline_module
    assert mod.NEW_BASE.startswith("hdfs://qixuandata/")
