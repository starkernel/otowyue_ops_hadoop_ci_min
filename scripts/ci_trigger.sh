#!/usr/bin/env bash
# Trigger the Qixuan CloudBuild pipeline and follow the log.
#
#   bash scripts/ci_trigger.sh            # trigger + tail log
#   bash scripts/ci_trigger.sh --watch    # keep polling until the job finishes
#
# Credentials come from ~/.hodoopforge-ci.env (0600), never from the repo:
#   CLOUDBUILD_URL, CLOUDBUILD_TOKEN, CLOUDBUILD_PROJECT
set -euo pipefail

if [[ -f "$HOME/.hodoopforge-ci.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.hodoopforge-ci.env"
fi
: "${CLOUDBUILD_URL:?CLOUDBUILD_URL missing}"
: "${CLOUDBUILD_TOKEN:?CLOUDBUILD_TOKEN missing}"
: "${CLOUDBUILD_PROJECT:?CLOUDBUILD_PROJECT missing}"

WATCH=0
[[ "${1:-}" == "--watch" ]] && WATCH=1

RUN_ID="$(python3 - "$CLOUDBUILD_URL" "$CLOUDBUILD_TOKEN" "$CLOUDBUILD_PROJECT" <<'PY'
import json, sys, urllib.request
base, token, project = sys.argv[1:4]
req = urllib.request.Request(
    f"{base}/api/v1/projects/{project}/simulate-push",
    data=b"{}", method="POST",
    headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
)
with urllib.request.urlopen(req, timeout=60) as resp:
    print(json.load(resp)["id"])
PY
)"
echo "run: $RUN_ID"
echo "log: $CLOUDBUILD_URL/api/v1/runs/$RUN_ID/log"

if [[ "$WATCH" == "1" ]]; then
  for _ in $(seq 1 90); do
    sleep 4
    LOG="$(curl -sk "$CLOUDBUILD_URL/api/v1/runs/$RUN_ID/log?token=$CLOUDBUILD_TOKEN")"
    # Wait for the real job, not the fast "checkout" job at the top of the log.
    if grep -qE 'job: (test|build) \((SUCCESS|FAILED)\)' <<<"$LOG"; then
      sed -n '/job: /,$p' <<<"$LOG" | tail -40
      grep -qE 'job: (test|build) \(SUCCESS\)' <<<"$LOG"
      exit
    fi
  done
  echo "timed out waiting for $RUN_ID" >&2
  exit 1
fi
