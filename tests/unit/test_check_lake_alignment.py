"""Unit tests for datalake/tools/check_lake_alignment.py."""
from __future__ import annotations

import json

import pytest


def test_hdfs_ls_dirs_parses_metadata_paths(lake_alignment_module, monkeypatch):
    mod = lake_alignment_module
    output = (
        "drwxr-xr-x   - hdfs hadoop 0 2026-11-19 01:00 /iceberg-warehouse-ha/edulake_ai/ods_a/metadata\n"
        "drwxr-xr-x   - hdfs hadoop 0 2026-11-19 01:00 /iceberg-warehouse-ha/demo/users/metadata\n"
        "drwxr-xr-x   - hdfs hadoop 0 2026-11-19 01:00 /iceberg-warehouse-ha/not-a-table\n"
    )
    monkeypatch.setattr(mod, "run", lambda *a, **k: (0, output, ""))
    assert mod.hdfs_ls_dirs("/iceberg-warehouse-ha") == [
        "demo/users",
        "edulake_ai/ods_a",
    ]


def test_hdfs_ls_dirs_returns_empty_on_failure(lake_alignment_module, monkeypatch):
    mod = lake_alignment_module
    monkeypatch.setattr(mod, "run", lambda *a, **k: (1, "", "boom"))
    assert mod.hdfs_ls_dirs("/missing") == []


def test_describe_locations_parses_beeline_output(lake_alignment_module, monkeypatch):
    mod = lake_alignment_module
    beeline = (
        "T:edulake_ai.ods_a\n"
        "Location\thdfs://qixuandata/iceberg-warehouse-ha/edulake_ai/ods_a\n"
        "T:demo.users\n"
        "Location\thdfs://qixuandata/iceberg-warehouse-ha/demo/users\n"
    )

    calls = {"n": 0}

    def fake_run(cmd, timeout=300):
        calls["n"] += 1
        if calls["n"] == 1:  # docker cp
            return 0, "", ""
        return 0, beeline, ""

    monkeypatch.setattr(mod, "run", fake_run)
    result = mod.describe_locations(["edulake_ai/ods_a", "demo/users"])
    assert result == {
        "edulake_ai/ods_a": "hdfs://qixuandata/iceberg-warehouse-ha/edulake_ai/ods_a",
        "demo/users": "hdfs://qixuandata/iceberg-warehouse-ha/demo/users",
    }


def _run_main(monkeypatch, mod, argv, old, new, locs):
    monkeypatch.setattr(mod, "hdfs_ls_dirs", lambda base: old if base == mod.OLD else new)
    monkeypatch.setattr(mod, "describe_locations", lambda tables: locs)
    monkeypatch.setattr(mod.sys, "argv", ["check_lake_alignment.py"] + argv)
    return mod.main()


def test_main_all_aligned_returns_zero(
    lake_alignment_module, monkeypatch, capsys
):
    mod = lake_alignment_module
    new = ["edulake_ai/ods_a", "demo/users"]
    locs = {
        t: mod.EXPECTED + t for t in new
    }
    rc = _run_main(monkeypatch, mod, ["--json"], new, new, locs)
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert out["new_tables"] == 2
    assert out["aligned"] == 2
    assert out["misaligned"] == 0
    assert out["only_in_old"] == []
    assert out["only_in_new"] == []


def test_main_misaligned_returns_one(lake_alignment_module, monkeypatch, capsys):
    mod = lake_alignment_module
    new = ["edulake_ai/ods_a"]
    locs = {"edulake_ai/ods_a": "hdfs://old/iceberg-warehouse/edulake_ai/ods_a"}
    rc = _run_main(monkeypatch, mod, ["--json"], new, new, locs)
    out = json.loads(capsys.readouterr().out)
    assert rc == 1
    assert out["misaligned"] == 1
    assert out["misaligned_tables"][0]["table"] == "edulake_ai/ods_a"


def test_main_reports_only_in_old(lake_alignment_module, monkeypatch, capsys):
    mod = lake_alignment_module
    old = ["edulake_ai/ods_a", "edulake_ai/ods_legacy"]
    new = ["edulake_ai/ods_a"]
    locs = {"edulake_ai/ods_a": mod.EXPECTED + "edulake_ai/ods_a"}
    rc = _run_main(monkeypatch, mod, ["--json"], old, new, locs)
    out = json.loads(capsys.readouterr().out)
    assert rc == 1
    assert out["only_in_old"] == ["edulake_ai/ods_legacy"]


def test_expected_prefix_is_nameservice(lake_alignment_module):
    assert lake_alignment_module.EXPECTED.startswith("hdfs://qixuandata/")
    assert lake_alignment_module.EXPECTED.endswith("iceberg-warehouse-ha/")
