#!/usr/bin/env bash
# Publish a sanitized snapshot of this repository to the public CI mirror repo
# used by Qixuan CloudBuild (https://as.long.kim:12131).
#
#   GITHUB_TOKEN=ghp_xxx bash scripts/sync_ci_mirror.sh
#
# The platform runner cannot `git clone` the full private repo (times out), so
# it downloads the mirror tarball instead. Never mirror secrets: keytabs,
# /etc/hodoopforge/*.env, cluster data or the RPM/jar payloads.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR_REPO="${MIRROR_REPO:-starkernel/otowyue_ops_hadoop_ci_min}"
BRANCH="${MIRROR_BRANCH:-master}"

if [[ -z "${GITHUB_TOKEN:-}" && -f "$HOME/.hodoopforge-ci.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.hodoopforge-ci.env"
fi
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required (repo scope for ${MIRROR_REPO})" >&2
  exit 1
fi

WORK="$(mktemp -d /tmp/hf-ci-mirror.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cd "$REPO_ROOT"
SOURCE_SHA="$(git rev-parse --short HEAD)"
git archive HEAD | tar -x -C "$WORK"

# Large / binary payloads that the unit tests do not need. Everything text-ish
# stays, so parametrized static checks see the same files as the main repo.
rm -rf \
  "$WORK"/docs/screenshots \
  "$WORK"/docs/*.pptx \
  "$WORK"/ambari3/ambari-repo \
  "$WORK"/data

# docs/*.md link to one screenshot; keep the link checker green with a placeholder.
mkdir -p "$WORK/docs/screenshots"
: > "$WORK/docs/screenshots/61-kafka-rf3.jpeg"

# The handbook package is gitignored in the main repo but linked from README.
if ! git check-ignore -q ambarirpm/hodoopforge-handbook-2026-11-26 2>/dev/null; then
  :
fi
git archive HEAD ambarirpm/hodoopforge-handbook-2026-11-26 2>/dev/null | tar -x -C "$WORK" || true

# Drop the handbook download line (package lives outside docs/INDEX.md scope).
if [[ -f "$WORK/docs/INDEX.md" ]]; then
  python3 - "$WORK/docs/INDEX.md" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.readlines()
with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(line for line in lines if "hodoopforge-handbook" not in line)
PY
fi

cat > "$WORK/CI_MIRROR.md" <<EOF
# HodoopForge CI mirror

Sanitized snapshot of \`starkernel/otowyue_ops_hadoop\` for the Qixuan
CloudBuild runner at <https://as.long.kim:12131>.

- Source commit: \`${SOURCE_SHA}\`
- Excluded: real screenshots/videos, PowerPoint, RPM/jar repositories, bulk
  data, handbook package (placeholder files keep doc links valid).
- Regenerate with \`scripts/sync_ci_mirror.sh\` in the main repository.

Run: \`python3 -m pytest -q tests/unit\`

Do not commit credentials, keytabs or cluster data here.
EOF

# Publish a self-contained tarball too: the runner fetches it from
# raw.githubusercontent.com when codeload.github.com throttles archive builds.
# A single top-level directory keeps extraction identical to a GitHub archive.
STAGE="$(mktemp -d /tmp/hf-ci-stage.XXXXXX)"
mkdir -p "$STAGE/mirror"
cp -a "$WORK/." "$STAGE/mirror/"
tar czf "$WORK/mirror.tar.gz" -C "$STAGE" mirror
rm -rf "$STAGE"

cd "$WORK"
git init -q
git config user.email "ci@hodoopforge.local"
git config user.name "HodoopForge CI"
git add -A
git add -f ambarirpm/hodoopforge-handbook-2026-11-26 2>/dev/null || true
git commit -q -m "ci: mirror from ${SOURCE_SHA}"

AUTH="$(python3 -c 'import base64,sys;print(base64.b64encode(("x-access-token:"+sys.argv[1]).encode()).decode())' "$GITHUB_TOKEN")"
GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0=http.extraheader \
GIT_CONFIG_VALUE_0="Authorization: Basic ${AUTH}" \
  git push --force "https://github.com/${MIRROR_REPO}.git" "HEAD:${BRANCH}"

# raw.githubusercontent.com caches by path for ~5 minutes, so a build fired
# right after sync could unpack the previous snapshot. Poll until the CDN
# serves this commit (skip with MIRROR_VERIFY=0).
if [[ "${MIRROR_VERIFY:-1}" == "1" ]]; then
  RAW="https://raw.githubusercontent.com/${MIRROR_REPO}/${BRANCH}/mirror.tar.gz"
  for attempt in $(seq 1 24); do
    if curl -fsSL --max-time 120 -o "$WORK/verify.tar.gz" "$RAW" 2>/dev/null \
      && tar xzOf "$WORK/verify.tar.gz" mirror/CI_MIRROR.md 2>/dev/null | grep -q "${SOURCE_SHA}"; then
      echo "raw CDN serves ${SOURCE_SHA} (attempt ${attempt})"
      break
    fi
    if [[ "$attempt" == "24" ]]; then
      echo "WARN: raw CDN still stale after 6 minutes; retry later" >&2
    fi
    sleep 15
  done
fi

echo "mirrored ${SOURCE_SHA} -> ${MIRROR_REPO} (${BRANCH}), $(du -sh "$WORK" | cut -f1)"
