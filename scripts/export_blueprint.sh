#!/usr/bin/env bash
# Export the live Ambari cluster as a blueprint (rebuild baseline).
#
#   sudo bash scripts/export_blueprint.sh
#
# Credentials come from /etc/hodoopforge/ambari.env (root 0600) or AMBARI_PASS.
# The blueprint contains configs but no passwords (Ambari masks them).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -r /etc/hodoopforge/ambari.env ]; then
  # shellcheck disable=SC1091
  . /etc/hodoopforge/ambari.env
fi
: "${AMBARI_PASS:?set AMBARI_PASS or run as root with /etc/hodoopforge/ambari.env}"
AMBARI_URL="${AMBARI_URL:-http://localhost:20609}"
CLUSTER="${AMBARI_CLUSTER:-qixuandata}"
OUT="${1:-$ROOT/ambari3/blueprint.json}"

curl -sS --max-time 60 -u "${AMBARI_USER:-admin}:$AMBARI_PASS" \
  -H 'X-Requested-By: hodoopforge' \
  "$AMBARI_URL/api/v1/clusters/$CLUSTER?format=blueprint" -o "$OUT"

python3 - "$OUT" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
assert data.get("Blueprints"), "blueprint has no Blueprints section"
assert data.get("host_groups"), "blueprint has no host_groups"
print("blueprint: %d host groups, stack %s %s" % (
    len(data["host_groups"]),
    data["Blueprints"].get("stack_name"),
    data["Blueprints"].get("stack_version"),
))
PY
