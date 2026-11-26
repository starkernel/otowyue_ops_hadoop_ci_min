"""Unit tests for datalake/tools/migrate_beeline.py."""
from __future__ import annotations


def test_sets_point_at_nameservice(migrate_beeline_module):
    mod = migrate_beeline_module
    assert "oldice.warehouse=%s" % mod.OLD in mod.SETS
    assert "newice.warehouse=%s" % mod.NEW in mod.SETS
    assert mod.NEW == "hdfs://qixuandata/iceberg-warehouse-ha"


def test_strip_ddl_renames_catalog(migrate_beeline_module):
    mod = migrate_beeline_module
    ddl = (
        "CREATE TABLE oldice.edulake_ai.ods_a (\n"
        "  id bigint\n"
        ")\n"
        "USING iceberg\n"
        "LOCATION 'hdfs://old/iceberg-warehouse/edulake_ai/ods_a'\n"
        "TBLPROPERTIES ('format-version'='2')"
    )
    out = mod.strip_ddl(ddl, "edulake_ai.ods_a")
    assert out.startswith("CREATE TABLE newice.edulake_ai.ods_a")
    assert "LOCATION" not in out
    assert "TBLPROPERTIES" not in out
    assert "USING iceberg" in out
    assert "id bigint" in out


def test_strip_ddl_without_location_or_properties(migrate_beeline_module):
    mod = migrate_beeline_module
    ddl = "CREATE TABLE oldice.demo.t (id int)\nUSING iceberg"
    out = mod.strip_ddl(ddl, "demo.t")
    assert out == "CREATE TABLE newice.demo.t (id int)\nUSING iceberg"


def test_list_tables_parses_tsv(migrate_beeline_module, monkeypatch):
    mod = migrate_beeline_module
    output = (
        "namespace\ttableName\tisTemporary\n"
        "edulake_ai\tods_a\tfalse\n"
        "edulake_ai\tods_b\tfalse\n"
    )
    monkeypatch.setattr(mod, "run_beeline", lambda sql, timeout=300: (0, output))
    assert mod.list_tables("edulake_ai") == [
        "edulake_ai.ods_a",
        "edulake_ai.ods_b",
    ]


def test_list_tables_raises_on_failure(migrate_beeline_module, monkeypatch):
    mod = migrate_beeline_module
    monkeypatch.setattr(mod, "run_beeline", lambda sql, timeout=300: (1, "denied"))
    try:
        mod.list_tables("edulake_ai")
    except RuntimeError as exc:
        assert "list edulake_ai failed" in str(exc)
    else:  # pragma: no cover
        raise AssertionError("expected RuntimeError")


def test_count_parses_last_numeric_line(migrate_beeline_module, monkeypatch):
    mod = migrate_beeline_module
    monkeypatch.setattr(
        mod, "run_beeline", lambda sql, timeout=300: (0, "col\n42\n")
    )
    assert mod.count("demo.t", "oldice") == 42


def test_count_raises_when_unparseable(migrate_beeline_module, monkeypatch):
    mod = migrate_beeline_module
    monkeypatch.setattr(mod, "run_beeline", lambda sql, timeout=300: (0, "col\n"))
    try:
        mod.count("demo.t", "oldice")
    except RuntimeError as exc:
        assert "cannot parse count" in str(exc)
    else:  # pragma: no cover
        raise AssertionError("expected RuntimeError")


def test_migrate_one_ok(migrate_beeline_module, monkeypatch):
    mod = migrate_beeline_module
    monkeypatch.setattr(
        mod,
        "show_create",
        lambda table: "CREATE TABLE oldice.demo.t (id int)\nUSING iceberg\n"
        "LOCATION 'hdfs://old/x'",
    )
    monkeypatch.setattr(mod, "run_beeline", lambda sql, timeout=1800: (0, "ok"))
    monkeypatch.setattr(mod, "count", lambda table, catalog: 7)
    result = mod.migrate_one("demo.t")
    assert result == {"table": "demo.t", "old_rows": 7, "new_rows": 7, "status": "ok"}


def test_migrate_one_count_mismatch(migrate_beeline_module, monkeypatch):
    mod = migrate_beeline_module
    monkeypatch.setattr(mod, "show_create", lambda table: "CREATE TABLE oldice.demo.t (id int)")
    monkeypatch.setattr(mod, "run_beeline", lambda sql, timeout=1800: (0, "ok"))

    def fake_count(table, catalog):
        return 7 if catalog == "oldice" else 5

    monkeypatch.setattr(mod, "count", fake_count)
    result = mod.migrate_one("demo.t")
    assert result["status"] == "count_mismatch"
    assert result["old_rows"] == 7
    assert result["new_rows"] == 5


def test_migrate_one_propagates_failure(migrate_beeline_module, monkeypatch):
    mod = migrate_beeline_module
    monkeypatch.setattr(mod, "show_create", lambda table: "CREATE TABLE oldice.demo.t (id int)")
    monkeypatch.setattr(mod, "run_beeline", lambda sql, timeout=1800: (2, "syntax error"))
    try:
        mod.migrate_one("demo.t")
    except RuntimeError as exc:
        assert "migrate demo.t failed" in str(exc)
    else:  # pragma: no cover
        raise AssertionError("expected RuntimeError")
