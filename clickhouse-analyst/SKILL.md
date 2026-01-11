---
name: clickhouse-analyst
description: ClickHouse incident response, periodic audits, and ad-hoc debugging via system tables (query_log, part_log, query_views_log, text_log, metrics, asynchronous_metrics, replicas, replication_queue). Use for slow queries/inserts, too many parts/merge backlog, wrong partitioning (tiny partitions), log-table errors, replication/Keeper lag, memory/disk pressure, and RCA.
---

# ClickHouse Analyst (compact)

Goal: quickly narrow a ClickHouse issue to a small set of likely causes using system tables, then produce an actionable RCA-style report.

## Choose a mode (first)
Pick one mode explicitly; if the user didn’t specify, infer from context:
- Incident response: “outage”, “timeouts”, “suddenly slow”, “OOM”, “disk full”, “replication lag now”
- Periodic audit: “weekly/monthly check”, “baseline”, “health report”, “what should we fix”, “capacity planning”
- Ad-hoc debugging: “why does X happen”, “how do I measure”, “investigate this query/table”

Mode playbooks:
- Incident: `mode-incident.md`
- Audit: `mode-audit.md`
- Ad-hoc: `mode-adhoc.md`

## Start (always)
1) Clarify scope: single node vs cluster, timeframe, and the concrete symptom(s).
2) Confirm access method (SQL via MCP, clickhouse-client, HTTP). If no direct access, ask the user to export relevant `system.*` query results.
3) Identify the server:

```sql
select
    hostName() as host,
    version() as version,
    uptime() as uptime_sec
```

## Safety rules for queries (always)
- Never `select *`; default `limit 100`.
- For `*_log` tables require a time bound (default last 1 hour / 24 hours):
  - `where event_time > now() - interval 1 hour`
  - `where event_date >= today() - 1`
- Prefer aggregating in SQL (top-N, percentiles) over dumping raw logs.
- If results are large (> ~50 rows), summarize and show the most relevant rows only.

## Route to the right module
Load exactly one primary module first (from `modules/`), then chain based on findings:

- General health / unclear issue → `modules/overview.md`
- Slow SELECT / timeouts / latency → `modules/reporting.md`
- Slow INSERT / too many new parts → `modules/ingestion.md`
- Merge backlog / “too many parts” / compaction pain → `modules/merges.md`
- OOM / high RAM / MemoryTracker → `modules/memory.md`
- Disk full / slow IO / storage sizing → `modules/storage.md`
- Low cache hit ratios / cache tuning → `modules/caches.md`
- Replication lag / readonly replica / Keeper/ZooKeeper → `modules/replication.md`
- Mutations stuck (ALTER UPDATE/DELETE) → `modules/mutations.md`
- Exceptions / crashes / failed queries (query_log, part_log) → `modules/errors.md`
- Materialized view execution / query_views_log issues → `modules/query_views_log.md`
- Need server log evidence → `modules/text_log.md`
- Dictionary failures/pressure → `modules/dictionaries.md`
- System log TTL / log table bloat → `modules/logs.md`
- Real-time saturation (connections/queues/load) → `modules/metrics.md`
- Table design review (ORDER BY/partition/index/MV) → `modules/schema.md`

## Common chains (only when indicated by data)
- Inserts slow → ingestion → merges → storage
- Queries slow → reporting → memory → caches → schema
- Replication lag → replication → merges → storage
- OOM during merges/queries → memory → merges/reporting → schema
- Mutations stuck → mutations → merges → errors

## Output format (keep it short)
- Finding: what is wrong (metric + timeframe)
- Evidence: 1–3 query outputs + key numbers
- Likely cause: 1–2 hypotheses with confidence
- Next steps: concrete actions + what to measure after

## Optional: audit patterns and thresholds
For notes on severity thresholds, ratio-based checks, and cross-table correlation, see `audit-patterns.md`.
