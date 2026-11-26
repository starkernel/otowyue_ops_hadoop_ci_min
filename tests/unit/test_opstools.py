"""Unit tests for opstools/python helpers."""
from __future__ import annotations

import socket
import textwrap


# --------------------------------------------------------------------------
# config-validator.py
# --------------------------------------------------------------------------
CORE_SITE = """<?xml version="1.0"?>
<configuration>
  <property><name>fs.defaultFS</name><value>hdfs://qixuandata</value></property>
  <property><name>hadoop.tmp.dir</name><value>/tmp/hadoop</value></property>
</configuration>
"""


def test_config_validator_accepts_valid_file(config_validator_module, tmp_path):
    (tmp_path / "core-site.xml").write_text(CORE_SITE, encoding="utf-8")
    validator = config_validator_module.ConfigValidator(str(tmp_path))
    assert validator.validate_file("core-site.xml") is True
    assert validator.errors == []


def test_config_validator_reports_missing_property(config_validator_module, tmp_path):
    (tmp_path / "core-site.xml").write_text(
        "<configuration><property><name>fs.defaultFS</name></property></configuration>",
        encoding="utf-8",
    )
    validator = config_validator_module.ConfigValidator(str(tmp_path))
    assert validator.validate_file("core-site.xml") is False
    assert any("hadoop.tmp.dir" in e for e in validator.errors)


def test_config_validator_reports_missing_file(config_validator_module, tmp_path):
    validator = config_validator_module.ConfigValidator(str(tmp_path))
    assert validator.validate_file("hdfs-site.xml") is False
    assert any("配置文件不存在" in e for e in validator.errors)


def test_config_validator_reports_malformed_xml(config_validator_module, tmp_path):
    (tmp_path / "core-site.xml").write_text("<configuration>", encoding="utf-8")
    validator = config_validator_module.ConfigValidator(str(tmp_path))
    assert validator.validate_file("core-site.xml") is False
    assert any("XML 解析错误" in e for e in validator.errors)


def test_config_validator_validate_all(config_validator_module, tmp_path):
    for name in ("core-site.xml", "hdfs-site.xml", "yarn-site.xml", "hive-site.xml"):
        (tmp_path / name).write_text(CORE_SITE, encoding="utf-8")
    validator = config_validator_module.ConfigValidator(str(tmp_path))
    errors, warnings = validator.validate_all()
    # core-site is the only file whose required keys are all present.
    assert errors
    assert isinstance(warnings, list)


# --------------------------------------------------------------------------
# service-checker.py
# --------------------------------------------------------------------------
def test_service_checker_detects_open_port(service_checker_module):
    checker = service_checker_module.ServiceChecker()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    port = server.getsockname()[1]
    try:
        assert checker.check_port("127.0.0.1", port) is True
    finally:
        server.close()


def test_service_checker_returns_false_for_closed_port(service_checker_module):
    checker = service_checker_module.ServiceChecker()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("127.0.0.1", 0))
    port = server.getsockname()[1]
    server.close()
    assert checker.check_port("127.0.0.1", port) is False


def test_service_checker_check_all_returns_expected_keys(service_checker_module):
    checker = service_checker_module.ServiceChecker()
    result = checker.check_all_services()
    assert set(result) == {
        "hdfs_namenode",
        "yarn_resourcemanager",
        "hive_server2",
        "hdfs_datanode",
    }
    for value in result.values():
        assert "service" in value
        assert "process" in value


# --------------------------------------------------------------------------
# log-analyzer.py
# --------------------------------------------------------------------------
def test_log_analyzer_counts_errors_and_warnings(log_analyzer_module, tmp_path):
    log = tmp_path / "app.log"
    log.write_text(
        textwrap.dedent(
            """\
            INFO starting
            ERROR something failed
            WARN deprecated option
            Exception in thread main
            INFO done
            """
        ),
        encoding="utf-8",
    )
    analyzer = log_analyzer_module.LogAnalyzer(str(tmp_path))
    result = analyzer.analyze_file(str(log))
    assert result["error_count"] == 2  # ERROR + Exception
    assert result["warning_count"] == 1
    assert result["errors"][0]["line"] == 2


def test_log_analyzer_missing_file(log_analyzer_module, tmp_path):
    analyzer = log_analyzer_module.LogAnalyzer(str(tmp_path))
    assert analyzer.analyze_file(str(tmp_path / "nope.log")) == {"error": "文件不存在"}


def test_log_analyzer_analyze_directory(log_analyzer_module, tmp_path):
    (tmp_path / "a.log").write_text("ERROR x\n", encoding="utf-8")
    (tmp_path / "b.log").write_text("WARN y\n", encoding="utf-8")
    (tmp_path / "ignore.txt").write_text("ERROR z\n", encoding="utf-8")
    analyzer = log_analyzer_module.LogAnalyzer(str(tmp_path))
    result = analyzer.analyze_directory()
    assert set(result) == {"a.log", "b.log"}
    assert result["a.log"]["error_count"] == 1
    assert result["b.log"]["warning_count"] == 1
