# clickhouse-analyst

Compact ClickHouse incident response + audit + ad-hoc debugging skill.

## How to use
- Start in `SKILL.md`, choose a mode, then load exactly one primary module from `modules/`.
- Keep queries safe: no `select *`, use `limit`, and always time-bound `*_log` queries.

## Files
- `SKILL.md`: router, safety rules, and reporting template.
- `mode-incident.md` / `mode-audit.md` / `mode-adhoc.md`: mode-specific workflow.
- `audit-patterns.md`: optional threshold patterns and severity ideas.
- `modules/*.md`: query anchors + interpretation for specific domains (ingestion, partitions, merges, replication, errors, etc.).

