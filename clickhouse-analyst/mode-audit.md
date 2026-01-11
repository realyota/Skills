# Mode: periodic audit

Goal: produce a repeatable, comparable health report with prioritized fixes (not incident firefighting).

## Defaults
- Window: last 7 days for trends + last 24 hours for recency.
- Prefer severity-rated checks and ratio-based thresholds.
- Output should be stable across runs (same headings, top-N tables).

## Recommended baseline modules
1) `overview.md` (object counts, high-level health)
2) `logs.md` (system log TTL/disk safety)
3) `metrics.md` (capacity headroom and saturation signals)
4) `storage.md` (disk usage + biggest tables/parts)
5) `schema.md` (structural risks: partitioning/ORDER BY, MVs)

## Audit output template
- Summary: top 5 findings (Critical/Major/Moderate)
- Evidence: key queries/metrics (with time window)
- Fix backlog: actions grouped by “now / this week / later”
- Follow-ups: what to monitor to validate improvements

