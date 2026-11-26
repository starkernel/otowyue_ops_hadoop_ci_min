#!/usr/bin/env bash
# Fix the Ambari "Enable NameNode HA Wizard / Finalize HA Setup" dialog that
# keeps coming back after HDFS HA has already been enabled.
#
# Root cause:
#   Ambari web stores the wizard state in browser localStorage under
#   `ambari.HighAvailabilityWizard`. If the finalize request was interrupted,
#   `currentStep` stays at "9" and the UI re-opens the wizard on every load.
#   The cluster itself is already HA (requests table has no running request).
#
# This script injects a tiny self-heal snippet into the Ambari web index.html:
#   * drops `HighAvailabilityWizard` when currentStep == 9
#   * rewrites the stale `.../highAvailability/NameNode/enable/stepN` hash
#     to `#/main/services`
#
# Safe and idempotent: it keeps a one-time backup as index.html.orig and does
# not touch Ambari services.
#
# Usage (on the host running Ambari Server, container bigtop_hostname0):
#   bash scripts/fix_ambari_ha_wizard.sh
#   bash scripts/fix_ambari_ha_wizard.sh --check
set -euo pipefail

CONTAINER="${CONTAINER:-bigtop_hostname0}"
INDEX="/usr/lib/ambari-server/web/index.html"
MARKER="HighAvailabilityWizard"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "ERROR: container $CONTAINER is not running" >&2
  exit 1
fi

if docker exec "$CONTAINER" grep -q "$MARKER" "$INDEX" 2>/dev/null; then
  echo "OK: HA wizard self-heal is already present in $INDEX"
  exit 0
fi

if [ "$check_only" = "1" ]; then
  echo "MISSING: HA wizard self-heal is not installed"
  exit 2
fi

cat > /tmp/patch_ambari_index.py <<'PY'
import io, os, shutil
p = '/usr/lib/ambari-server/web/index.html'
s = io.open(p, encoding='utf-8').read()
if 'HighAvailabilityWizard' in s:
    print('already patched')
    raise SystemExit(0)
marker = '  <script src="javascripts/vendor.js"></script>'
inject = '''  <script>
  /* Platform fix: clear stale Enable NameNode HA wizard state persisted in
     browser localStorage (stuck at Finalize step) and leave the wizard route. */
  (function () {
    try {
      var raw = localStorage.getItem('ambari');
      if (raw) {
        var o = JSON.parse(raw);
        var w = o && o.HighAvailabilityWizard;
        if (w && String(w.currentStep) === '9') {
          o.HighAvailabilityWizard = {};
          localStorage.setItem('ambari', JSON.stringify(o));
        }
      }
      if (location.hash.indexOf('/highAvailability/NameNode/enable/step') !== -1) {
        location.hash = '#/main/services';
      }
    } catch (e) {}
  })();
  </script>
'''
assert marker in s, 'unexpected index.html layout'
backup = p + '.orig'
if not os.path.exists(backup):
    shutil.copy2(p, backup)
s = s.replace(marker, inject + marker, 1)
io.open(p, 'w', encoding='utf-8').write(s)
print('patched', p)
PY

docker cp /tmp/patch_ambari_index.py "$CONTAINER":/tmp/patch_ambari_index.py >/dev/null
docker exec "$CONTAINER" bash -c "python3 /tmp/patch_ambari_index.py 2>/dev/null || python /tmp/patch_ambari_index.py"

echo
echo "Done. In the browser:"
echo "  1) open http://<ambari-host>:20609/  (or press Ctrl+Shift+R once)"
echo "  2) you should land on #/main/services; the wizard will not re-open"
echo "  3) never click YES in that dialog - YES means rollback HA"
