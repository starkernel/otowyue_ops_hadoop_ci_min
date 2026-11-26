# HodoopForge CI mirror

Sanitized snapshot of `starkernel/otowyue_ops_hadoop` for the Qixuan
CloudBuild runner at <https://as.long.kim:12131>.

- Source commit: `4bef880`
- Excluded: real screenshots/videos, PowerPoint, RPM/jar repositories, bulk
  data, handbook package (placeholder files keep doc links valid).
- Regenerate with `scripts/sync_ci_mirror.sh` in the main repository.

Run: `python3 -m pytest -q tests/unit`

Do not commit credentials, keytabs or cluster data here.
