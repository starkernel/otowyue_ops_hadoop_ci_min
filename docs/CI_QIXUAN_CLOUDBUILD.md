# Qixuan CloudBuild CI（as.long.kim:12131）

> 状态：2026-11-26 已接入并跑通；构建 **SUCCESS · 272 passed · junit.xml 已归档**。  
> 平台：<https://as.long.kim:12131>  
> 项目：`otowyue_ops_hadoop_ci`

## 1. 账号与入口

| 项 | 值 |
|---|---|
| 平台 | `https://as.long.kim:12131` |
| 组织 | `hodoopforge-ci-org` |
| 账号 | CI 专用账号（邮箱见 `~/.hodoopforge-ci.env`，不写入公开镜像） |
| 密码 | 不写入仓库；见宿主机 `~/.hodoopforge-ci.env`（0600） |
| 项目 | `otowyue_ops_hadoop_ci`（project id `prj_7efee1f4e086473997b7d781fac6cf94`） |

## 2. 当前流水线

平台到 GitHub 的 `git clone` 会超时（私有主仓库 167MB；公开镜像也一样），
但单个文件 `curl` 下载可用，因此流水线采用「公开镜像 + tarball」：

1. 从 `raw.githubusercontent.com` 下载 `mirror.tar.gz`（主路径）；
   codeload archive 作为兜底。
2. 解压到 `/tmp/hf`（统一 `--strip-components=1`）。
3. `pip install pytest PyYAML loguru requests`。
4. `python3 -m pytest -q tests/unit --junitxml=reports/junit.xml`，
   并把 XML 复制回工作区，作为平台制品归档（保留 7 天）。

要点：

- `curl` 增加 `--http1.1 --retry 5 --retry-all-errors`：codeload 偶尔会
  `HTTP/2 stream not closed` 或空响应，直接失败会误报。
- `raw.githubusercontent.com` 按路径缓存约 5 分钟。`sync_ci_mirror.sh` 推送后
  会轮询 `mirror.tar.gz`，确认其内 `CI_MIRROR.md` 已指向新 commit 才返回，
  避免刚同步就构建时跑到上一版快照。
- 平台侧 pipeline 与仓库内 [`ci/qixuan-pipeline.yml`](../ci/qixuan-pipeline.yml)
  保持一致，修改后需 `PUT /api/v1/projects/<id>/pipeline`。

一次成功运行示例（`master` 分支，镜像由 `scripts/sync_ci_mirror.sh` 生成）：

```text
run id : bld_107b7446e7bf48b6bca730050bc7c53d
result : SUCCESS
tests  : 272 passed in 1.91s
artifact: junit.xml（35 KB）
```

> 计数少于本地（303）是因为本地存在未跟踪/被忽略的 `ambarirpm/*.json`
> 资产；CI 只校验仓库实际跟踪的文件。

## 3. 如何触发

平台 UI：项目 → 「模拟推送」/「立即构建」。

API：

```bash
curl -k -X POST \
  -H "Authorization: Bearer $CI_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{}' \
  https://as.long.kim:12131/api/v1/projects/prj_7efee1f4e086473997b7d781fac6cf94/simulate-push
```

查看日志：

```bash
curl -k "https://as.long.kim:12131/api/v1/runs/<run-id>/log?token=$CI_TOKEN"
curl -k -H "Authorization: Bearer $CI_TOKEN" \
  "https://as.long.kim:12131/api/v1/projects/$CLOUDBUILD_PROJECT/artifacts"
```

本地便捷脚本（读取 `~/.hodoopforge-ci.env`，可跟踪到结束）：

```bash
bash scripts/ci_trigger.sh --watch
```

## 4. CI mirror

- 主仓库：`starkernel/otowyue_ops_hadoop`（私有，约 15GB 工作区，git clone 超时）
- CI mirror：`starkernel/otowyue_ops_hadoop_ci_min`（公开、sanitized、约 7.6MB）
- 内容：`tests/`、`scripts/`、`datalake/`、`opstools/`、`docs/`（截图用占位文件）、
  `ambari3/`（去掉 `ambari-repo` 大 jar 仓库）、`blueprints/`、`uttest/`、`ci/`、
  handbook 包，以及供流水线直接下载的 `mirror.tar.gz`。
- 排除：真实截图/视频（17MB）、PPT、`ambari3/ambari-repo`（7GB）、
  `data/salaries.csv`（16MB）等大文件。

同步 mirror（构建 + 打包 + 强推）：

```bash
source ~/.hodoopforge-ci.env      # 含 GITHUB_TOKEN
bash scripts/sync_ci_mirror.sh
```

> 不要 sync 密码、keytab、`/etc/hodoopforge/*.env` 或集群数据。
> mirror 是快照：主仓库改动后先 sync，再触发构建。

## 5. 已知限制

1. 平台项目仍挂在 `samples/python-lib`（local 源，slug 不可改），只借用它的
   流水线执行能力；代码由 tarball 下载，因此 GitHub Push Webhook 不会自动
   路由到本项目。目前通过 UI「模拟推送」/「立即构建」或 API 触发。
2. 若要真正 Push 即构建，需要平台侧修复 GitHub git clone 网络/凭据，
   或把 mirror 放到平台可快速访问的 Git 服务（如内网 Gitee/GitLab）。
3. 真正的 Push 即构建需要平台侧修复 GitHub 连接，或把 mirror 放到平台可快速
   访问的 Git 服务（内网 Gitee/GitLab）；在那之前可用「主仓库 post-push hook
   调用 simulate-push」补齐自动化（token 放 `~/.hodoopforge-ci.env`）。

## 6. 测试覆盖

当前 `tests/unit` 覆盖：

- 文档链接、架构/Kerberos/guard 契约；
- lake-map 数据 schema 与单文件自包含；
- HA/管理面脚本静态检查；
- 监控 exporter、备份、MySQL 切换、Kerberos KDC 脚本；
- 仓库资产 JSON/YAML、shell 语法、Python 编译；
- CI 自身契约：两条流水线都包含 pytest、镜像下载带重试、文档状态一致。

集成测试 `tests/integration` 默认 skip（需要 `HODOOPFORGE_LIVE=1` 与集群）。
