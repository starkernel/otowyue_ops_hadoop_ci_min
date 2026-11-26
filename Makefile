# HodoopForge local test helpers (CI uses .github/workflows/ci.yml).
PYTHON ?= python3
PYTEST ?= pytest

.PHONY: help install test unit static integration live coverage clean

help:
	@echo "make install      install test dependencies"
	@echo "make test         run all non-integration tests"
	@echo "make unit         run unit tests"
	@echo "make static       run static/contract tests only"
	@echo "make live         run read-only live cluster checks (HODOOPFORGE_LIVE=1)"
	@echo "make coverage     run tests with coverage report"
	@echo "make clean        remove local test artifacts"

install:
	$(PYTHON) -m pip install -r requirements-dev.txt

test:
	$(PYTEST) -m "not integration" -v

unit:
	$(PYTEST) tests/unit -v

static:
	$(PYTEST) tests/unit/test_scripts_static.py tests/unit/test_repo_assets.py \
		tests/unit/test_docs_links.py tests/unit/test_ha_invariants.py -v

integration:
	HODOOPFORGE_LIVE=1 $(PYTEST) -m integration -v

live: integration

coverage:
	$(PYTEST) -m "not integration" --cov=datalake --cov=opstools --cov=scripts \
		--cov-report=term-missing:skip-covered --cov-report=html

clean:
	rm -rf reports .pytest_cache allure-results allure-report allure-history .coverage
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
