"""Shared fixtures for the HodoopForge test-suite.

The repository is an operations project, not an installable Python package, so
several modules live in directories with hyphens or without ``__init__.py``.
``load_module`` imports them by file path instead.
"""
import importlib.util
import os
import sys
from pathlib import Path
from types import ModuleType

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]


def load_module(relative_path: str, module_name: str) -> ModuleType:
    """Load a Python file from the repository by path."""
    path = REPO_ROOT / relative_path
    if not path.is_file():
        raise FileNotFoundError(path)
    spec = importlib.util.spec_from_file_location(module_name, str(path))
    if spec is None or spec.loader is None:  # pragma: no cover - defensive
        raise ImportError("cannot load %s" % path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def lake_alignment_module() -> ModuleType:
    return load_module("datalake/tools/check_lake_alignment.py", "hf_lake_alignment")


@pytest.fixture(scope="session")
def migrate_beeline_module() -> ModuleType:
    return load_module("datalake/tools/migrate_beeline.py", "hf_migrate_beeline")


@pytest.fixture(scope="session")
def migrate_pipeline_module() -> ModuleType:
    return load_module(
        "datalake/pipelines/migrate_iceberg_warehouse.py", "hf_migrate_pipeline"
    )


@pytest.fixture(scope="session")
def lake_map_module() -> ModuleType:
    return load_module("scripts/gen_lake_map_data.py", "hf_lake_map")


@pytest.fixture(scope="session")
def watchdog_module() -> ModuleType:
    return load_module("scripts/watchdog.py", "hf_watchdog")


@pytest.fixture(scope="session")
def hdfs_exporter_module() -> ModuleType:
    return load_module("scripts/monitoring/hdfs_jmx_exporter.py", "hf_hdfs_exporter")


@pytest.fixture(scope="session")
def ambari_exporter_module() -> ModuleType:
    return load_module("scripts/monitoring/ambari_exporter.py", "hf_ambari_exporter")


@pytest.fixture(scope="session")
def flink_exporter_module() -> ModuleType:
    return load_module("scripts/monitoring/flink_exporter.py", "hf_flink_exporter")


@pytest.fixture(scope="session")
def alert_webhook_module() -> ModuleType:
    return load_module("scripts/monitoring/alert_webhook.py", "hf_alert_webhook")


@pytest.fixture(scope="session")
def prom_proxy_module() -> ModuleType:
    return load_module("scripts/monitoring/prom_proxy.py", "hf_prom_proxy")


@pytest.fixture(scope="session")
def config_validator_module() -> ModuleType:
    return load_module("opstools/python/config-validator.py", "hf_config_validator")


@pytest.fixture(scope="session")
def service_checker_module() -> ModuleType:
    return load_module("opstools/python/service-checker.py", "hf_service_checker")


@pytest.fixture(scope="session")
def log_analyzer_module() -> ModuleType:
    return load_module("opstools/python/log-analyzer.py", "hf_log_analyzer")


def live_cluster_enabled() -> bool:
    return os.environ.get("HODOOPFORGE_LIVE", "").strip() in {"1", "true", "yes"}
