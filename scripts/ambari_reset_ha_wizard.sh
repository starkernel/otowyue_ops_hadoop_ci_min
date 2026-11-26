#!/usr/bin/env bash
# Reset a stale Ambari "current wizard" state that forces login to
# /#/main/services/highAvailability/NameNode/enable/step9.
#
# Background: Ambari persists CLUSTER_CURRENT_STATUS per user through
# /api/v1/persist. When the HA wizard is abandoned at step 5/7/9, the
# stored value keeps clusterState=HIGH_AVAILABILITY_DEPLOY and
# wizardControllerName=highAvailabilityWizardController. On every login
# getSection() routes the user back into the HA wizard, even from a clean
# browser or a clean machine.
#
# This script keeps clusterName, sets clusterState=CLUSTER_INSTALLED_4 and
# removes wizardControllerName. It does NOT touch HDFS config, services,
# requests or the HA deployment itself.
#
# NOTE: close any browser tab still sitting on the HA wizard step9 before
# running this. An open wizard tab can re-save the stale status.
#
# Usage:
#   AMBARI_URL=http://localhost:20609 AMBARI_USER=admin AMBARI_PASS=admin \
#     ./scripts/ambari_reset_ha_wizard.sh
#
# Optional: CLUSTER_NAME=qixuandata

set -euo pipefail

if [ -r /etc/hodoopforge/ambari.env ]; then
  . /etc/hodoopforge/ambari.env
elif [ -e /etc/hodoopforge/ambari.env ]; then
  echo "WARN: cannot read /etc/hodoopforge/ambari.env; run as root or export AMBARI_PASS" >&2
fi
AMBARI_URL="${AMBARI_URL:-http://localhost:20609}"
AMBARI_USER="${AMBARI_USER:-admin}"
AMBARI_PASS="${AMBARI_PASS:-admin}"
CLUSTER_NAME="${CLUSTER_NAME:-qixuandata}"
PERSIST_KEY="CLUSTER_CURRENT_STATUS"

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

if ! python3 -c 'import lzstring' >/dev/null 2>&1; then
  echo "python lzstring not found; installing to user site..."
  python3 -m pip install --user --quiet lzstring
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "GET $AMBARI_URL/api/v1/persist/$PERSIST_KEY"
http_code="$(curl -sS -o "$tmp/before.txt" -w '%{http_code}' \
  -u "$AMBARI_USER:$AMBARI_PASS" \
  -H 'X-Requested-By: ambari' \
  "$AMBARI_URL/api/v1/persist/$PERSIST_KEY")"

if [ "$http_code" != "200" ]; then
  echo "  no existing status (HTTP $http_code); a clean value will be created"
  : > "$tmp/before.txt"
fi

python3 - "$tmp/before.txt" "$CLUSTER_NAME" "$PERSIST_KEY" "$tmp/body.json" <<'PY'
import json
import sys

import lzstring

before_path, cluster_name, persist_key, body_path = sys.argv[1:5]
raw = open(before_path, encoding="utf-8").read().strip()

current = {}
if raw:
    try:
        if raw.startswith('"') and raw.endswith('"'):
            raw = json.loads(raw)
        decoded = lzstring.LZString().decompressFromBase64(raw)
        if decoded:
            current = json.loads(decoded)
    except Exception as exc:
        print("  WARNING: could not decode existing status: %s" % exc)

print("  before: clusterState=%r wizardControllerName=%r" % (
    current.get("clusterState"), current.get("wizardControllerName")))
step = ((current.get("localdb") or {}).get("HighAvailabilityWizard") or {}).get("currentStep")
if step:
    print("  before: HighAvailabilityWizard.currentStep=%r" % step)

new_value = {
    "clusterName": current.get("clusterName") or cluster_name,
    "clusterState": "CLUSTER_INSTALLED_4",
}
compressed = lzstring.LZString().compressToBase64(
    json.dumps(new_value, separators=(",", ":"))
)
# Ambari persist.post sends {"<key>": "<json-encoded string>"}.
body = {persist_key: json.dumps(compressed)}
with open(body_path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(body))
print("  new:    clusterState='CLUSTER_INSTALLED_4' wizardControllerName=None")
PY

echo "POST $AMBARI_URL/api/v1/persist"
curl -sS -o "$tmp/post.txt" -w '  HTTP %{http_code}\n' \
  -u "$AMBARI_USER:$AMBARI_PASS" \
  -H 'X-Requested-By: ambari' \
  -H 'Content-Type: application/json' \
  -X POST --data-binary @"$tmp/body.json" \
  "$AMBARI_URL/api/v1/persist"

echo "POST $AMBARI_URL/api/v1/persist (wizard-data)"
curl -sS -o "$tmp/post_wizard.txt" -w '  HTTP %{http_code}\n' \
  -u "$AMBARI_USER:$AMBARI_PASS" \
  -H 'X-Requested-By: ambari' \
  -H 'Content-Type: application/json' \
  -X POST -d '{"wizard-data":"null"}' \
  "$AMBARI_URL/api/v1/persist"

echo "VERIFY"
curl -sS -o "$tmp/after.txt" \
  -u "$AMBARI_USER:$AMBARI_PASS" \
  -H 'X-Requested-By: ambari' \
  "$AMBARI_URL/api/v1/persist/$PERSIST_KEY"

wizard_data="$(curl -sS \
  -u "$AMBARI_USER:$AMBARI_PASS" \
  -H 'X-Requested-By: ambari' \
  "$AMBARI_URL/api/v1/persist/wizard-data")"
if [ "$wizard_data" = "null" ] || [ -z "$wizard_data" ]; then
  echo "  wizard-data: cleared"
else
  echo "  WARNING: wizard-data still present: $wizard_data" >&2
fi

python3 - "$tmp/after.txt" <<'PY'
import json
import sys

import lzstring

raw = open(sys.argv[1], encoding="utf-8").read().strip()
if raw.startswith('"') and raw.endswith('"'):
    raw = json.loads(raw)
d = json.loads(lzstring.LZString().decompressFromBase64(raw))
print("  after:  clusterName=%r clusterState=%r wizardControllerName=%r" % (
    d.get("clusterName"), d.get("clusterState"), d.get("wizardControllerName")))
if d.get("clusterState") != "CLUSTER_INSTALLED_4" or d.get("wizardControllerName"):
    print("  ERROR: reset did not take effect", file=sys.stderr)
    sys.exit(1)
print("  OK: login should now land on Dashboard/Services, not HA wizard step9")
PY
