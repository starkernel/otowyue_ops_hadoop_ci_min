"""Static checks for shell scripts and first-party Python sources."""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
VENDOR = "ambarirpm/ambari-trunk"


def _shell_scripts():
    scripts = []
    for path in REPO.rglob("*.sh"):
        rel = path.relative_to(REPO).as_posix()
        if rel.startswith(VENDOR) or "/.git/" in rel:
            continue
        scripts.append(path)
    return sorted(scripts)


@pytest.mark.parametrize("script", _shell_scripts(), ids=lambda p: str(p).split("hadoop-ops-course/")[-1])
def test_shell_script_syntax(script):
    result = subprocess.run(
        ["bash", "-n", str(script)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


PYTHON_DIRS = ["datalake", "scripts", "opstools", "tests", "ambari3/scripts"]


def _python_sources():
    files = []
    for directory in PYTHON_DIRS:
        base = REPO / directory
        if not base.exists():
            continue
        files.extend(p for p in base.rglob("*.py") if "__pycache__" not in p.parts)
    return sorted(files)


@pytest.mark.parametrize("source", _python_sources(), ids=lambda p: str(p).split("hadoop-ops-course/")[-1])
def test_python_source_compiles(source):
    compile(source.read_text(encoding="utf-8"), str(source), "exec")


def test_shell_scripts_have_shebang():
    missing = []
    for script in _shell_scripts():
        first = script.read_text(encoding="utf-8", errors="ignore").splitlines()[:1]
        if not first or not first[0].startswith("#!"):
            missing.append(str(script.relative_to(REPO)))
    assert not missing, "scripts without shebang: %s" % missing
