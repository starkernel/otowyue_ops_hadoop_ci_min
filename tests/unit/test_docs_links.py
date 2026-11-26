"""Documentation link and consistency checks."""
from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]

# Entry-point documents that must stay internally consistent. Historical
# reports are intentionally excluded: they are allowed to describe past state.
ENTRY_DOCS = [
    "README.md",
    "docs/INDEX.md",
    "docs/ARCHITECTURE.md",
    "docs/CURRENT_STATE.md",
    "docs/KERBEROS_GUARD.md",
    "docs/OPERATIONS_AUTOMATION.md",
    "docs/POST_SNAPSHOT_RUNBOOK.md",
    "docs/WAREHOUSE_ALIGNMENT_FIX_2026-11-19.md",
    "docs/KAFKA_EXTERNAL_ACCESS.md",
    "docs/TEST_STRATEGY.md",
    "docs/CI_CD.md",
    "uttest/README.md",
]

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def _links(text: str):
    for raw in LINK_RE.findall(text):
        target = raw.strip()
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        if target.startswith(("http://", "https://", "mailto:", "#", "tel:")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        yield target


@pytest.mark.parametrize("doc", ENTRY_DOCS)
def test_entry_doc_relative_links_resolve(doc):
    path = REPO / doc
    assert path.is_file(), "missing entry doc %s" % doc
    missing = []
    for target in _links(path.read_text(encoding="utf-8")):
        candidate = (path.parent / target).resolve()
        try:
            candidate.relative_to(REPO)
        except ValueError:
            # Link points outside the repository; not our concern.
            continue
        if not candidate.exists():
            missing.append(target)
    assert not missing, "%s has broken links: %s" % (doc, missing)


def test_current_state_documents_ha_topology():
    text = (REPO / "docs/CURRENT_STATE.md").read_text(encoding="utf-8")
    assert "h3 Active" in text
    assert "h0 Standby" in text
    assert "77/77" in text
    assert "iceberg-warehouse-ha" in text


def test_readme_links_to_map_and_current_state():
    text = (REPO / "README.md").read_text(encoding="utf-8")
    assert "docs/lake-map.html" in text
    assert "docs/CURRENT_STATE.md" in text
    assert "docs/INDEX.md" in text
    assert "docs/ARCHITECTURE.md" in text


def test_docs_index_covers_entry_docs():
    text = (REPO / "docs/INDEX.md").read_text(encoding="utf-8")
    for name in ("CURRENT_STATE.md", "lake-map.html", "OPERATIONS_AUTOMATION.md"):
        assert name in text
