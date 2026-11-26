"""Repository asset tests: JSON/YAML validity, map schema, required files."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

SKIP_DIRS = {
    ".git",
    "ambarirpm/ambari-trunk",
    "node_modules",
    "__pycache__",
    "reports",
    "allure-results",
    "allure-report",
    "allure-history",
    ".pytest_cache",
    ".venv-ci",
}


def _iter_files(root: Path, suffix: str):
    for path in root.rglob("*%s" % suffix):
        rel = path.relative_to(root).as_posix()
        if any(rel.startswith(s) for s in SKIP_DIRS):
            continue
        if path.is_file():
            yield path


@pytest.mark.parametrize(
    "path", sorted(_iter_files(Path(__file__).resolve().parents[2], ".json")),
    ids=lambda p: str(p).split("hadoop-ops-course/")[-1],
)
def test_json_files_are_valid(path):
    with path.open(encoding="utf-8") as fh:
        json.load(fh)


@pytest.mark.skipif(yaml is None, reason="PyYAML not installed")
def test_yaml_files_are_valid(repo_root):
    files = list(_iter_files(repo_root, ".yml")) + list(_iter_files(repo_root, ".yaml"))
    assert files, "expected at least one YAML file"
    for path in files:
        with path.open(encoding="utf-8") as fh:
            yaml.safe_load(fh)


@pytest.mark.parametrize(
    "relative",
    [
        "README.md",
        "docs/CURRENT_STATE.md",
        "docs/INDEX.md",
        "docs/lake-map.html",
        "docs/lake-map-data.json",
        "docs/OPERATIONS_AUTOMATION.md",
        "docs/WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md",
        "scripts/post_snapshot_recover.sh",
        "scripts/gen_lake_map_data.py",
        "datalake/tools/check_lake_alignment.py",
        "pytest.ini",
        "requirements-dev.txt",
        ".github/workflows/ci.yml",
    ],
)
def test_required_project_files_exist(repo_root, relative):
    assert (repo_root / relative).is_file(), "missing %s" % relative


def test_lake_map_schema(repo_root):
    data = json.loads((repo_root / "docs/lake-map-data.json").read_text(encoding="utf-8"))
    for key in ("generated_at", "cluster", "title", "subtitle", "summary", "flow", "layers"):
        assert key in data, "lake-map-data.json missing %r" % key

    valid_status = {"ok", "warn", "bad", "plan", "off"}
    assert data["summary"], "summary must not be empty"
    for item in data["summary"]:
        assert set(item) >= {"label", "value", "status"}
        assert item["status"] in valid_status

    node_ids = []
    for layer in data["layers"]:
        assert set(layer) >= {"id", "name", "nodes"}
        assert layer["nodes"], "layer %s has no nodes" % layer["id"]
        for node in layer["nodes"]:
            assert set(node) >= {"id", "name", "sub", "status"}
            assert node["status"] in valid_status
            assert node["metrics"] or node["desc"], "node %s needs metrics or desc" % node["id"]
            node_ids.append(node["id"])
    assert len(node_ids) == len(set(node_ids)), "node ids must be unique"

    for step in data["flow"]:
        assert set(step) >= {"id", "name", "sub", "status"}
        assert step["status"] in valid_status


def test_lake_map_html_is_self_contained(repo_root):
    html = (repo_root / "docs/lake-map.html").read_text(encoding="utf-8")
    # The map must work via file:// / when copied alone: data is embedded,
    # not fetched from a sibling JSON file.
    assert 'id="lake-map-data"' in html
    assert "fetch(" not in html
    assert "lake-map-data.json" in html  # footer/tooling reference only


def test_blueprint_json_has_blueprint_name(repo_root):
    for name in ("blueprints/blueprint.json", "blueprints/template.json"):
        data = json.loads((repo_root / name).read_text(encoding="utf-8"))
        assert "Blueprints" in data or "blueprint_name" in data or "host_groups" in data
