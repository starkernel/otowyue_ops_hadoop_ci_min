# CI/CD 说明

> 工作流：[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)
> 测试策略：[`TEST_STRATEGY.md`](TEST_STRATEGY.md)
> 平台侧流水线（Qixuan CloudBuild）：[`CI_QIXUAN_CLOUDBUILD.md`](CI_QIXUAN_CLOUDBUILD.md)

## 1. 触发条件

| 事件 | 行为 |
|---|---|
| `push` 到 `master` / `main` | 跑全部 L1~L3，生成 Allure 报告 |
| `pull_request` 到 `master` / `main` | 跑全部 L1~L3，PR 上显示用例级结果 |
| `workflow_dispatch` | 手动触发；可配合 `LIVE_SMOKE=true` 跑真实集群只读冒烟 |

## 2. 两个 Job

### 2.1 `test`：单元与静态测试

```text
checkout → Python 3.12 → pip install -r requirements-dev.txt
        → python scripts/config_drift_check.py --static
        → pytest --junitxml --alluredir --cov
        → dorny/test-reporter  (PR/Job Summary 显示 Passed/Failed/Skipped)
        → upload-artifact test-reports
```

产物：

- `reports/junit.xml` — JUnit 用例级结果
- `reports/allure-results/` — Allure 原始数据
- `reports/coverage.xml` — 覆盖率

### 2.2 `allure`：可视化仪表盘

- 下载 `test-reports`
- 用 `simple-elf/allure-report-action` 生成 `allure-report`
- 上传 `allure-report` Artifact（保留 30 天）
- 可选发布到 GitHub Pages（见第 4 节）

## 3. 查看测试结果

1. 仓库 → **Actions** → 选择 `CI` 运行记录。
2. 左侧 **Unit & static tests** → **Run tests** 查看日志。
3. 同一页面下方 **HodoopForge test results** 查看用例级统计。
4. **Artifacts** 下载 `test-reports` 或 `allure-report`。
5. PR 页面 → **Checks** → **HodoopForge test results**。

## 4. 启用 Allure 在线 Dashboard（可选）

私有仓库同样适用，报告只对有权访问仓库的人可见。

1. 仓库 **Settings → Pages → Build and deployment → Source: GitHub Actions**。
2. 仓库 **Settings → Secrets and variables → Actions → Variables** 新建：
   - `ALLURE_PAGES = true`
3. 重新运行 `CI`。`allure` Job 会：
   - 上传 Pages artifact；
   - 调用 `actions/deploy-pages` 发布。
4. 发布地址：`https://<owner>.github.io/<repo>/`。

> 未设置 `ALLURE_PAGES` 时，只上传 Artifact，不会因 Pages 未开启而失败。

## 5. 真实集群冒烟（self-hosted）

GitHub 托管 Runner 无法访问内网集群。需要：

1. 在运维机注册 self-hosted runner（标签默认 `self-hosted`），并确保 `python3` ≥ 3.9、`docker` CLI 可用。
2. 仓库变量 `LIVE_SMOKE = true`。
3. **Actions → CI → Run workflow**。
4. `live-smoke` Job 执行：

```bash
HODOOPFORGE_LIVE=1 pytest -m integration -v
```

用例全部只读，不会改集群状态。

## 6. 本地复现 CI

CI 使用 Python 3.12；本机只有 3.6 时可用容器：

```bash
docker run --rm -v "$PWD:/repo" -w /repo python:3.12-slim bash -c '
  pip install -q -r requirements-dev.txt &&
  pytest -v
'
```

## 7. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `dorny/test-reporter` 报权限错误 | PR 来自 fork | 允许 `checks: write`，或忽略该 step |
| Allure Job 未运行 | PR 事件被排除 | 合并到 master 后运行 |
| Pages 部署失败 | 未开启 Pages 或未设变量 | 按第 4 节配置 |
| `live-smoke` 一直排队 | 无 self-hosted runner | 注册 runner 或取消该 Job |
| 覆盖率偏低 | 集群脚本以子进程执行 | 属预期，重点看用例通过率 |

## 8. 维护约定

- 新增 `scripts/*.sh`：无需改 CI，`test_scripts_static.py` 自动覆盖。
- 新增 `datalake/**/*.py`：建议补充 `tests/unit/`。
- 修改 HA/仓库路径：必须同步 `docs/CURRENT_STATE.md` 与 `test_ha_invariants.py`。
- 修改 CI 依赖：更新 `requirements-dev.txt`。
