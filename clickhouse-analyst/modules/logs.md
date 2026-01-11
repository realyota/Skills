# System log tables (retention / disk safety)

Use when: `system.*_log` tables consume disk, logs are missing/stale, or you need to ensure TTL/retention is configured.

## Primary sources
- Size/parts: `system.parts`
- Table definitions: `system.tables` (use `create_table_query` to verify TTL)

## Quick triage queries

### 1) Biggest `system.*_log` tables by bytes
```sql
select
    table,
    formatReadableSize(sum(bytes_on_disk)) as bytes_on_disk,
    count() as parts
from system.parts
where active
  and database = 'system'
  and table like '%\\_log%'
group by table
order by sum(bytes_on_disk) desc
limit 30
```

### 2) Do these log tables have TTL?
This is a lightweight heuristic: look for `ttl` in the CREATE TABLE query.
```sql
select
    name as table,
    positionCaseInsensitive(create_table_query, ' ttl ') > 0 as has_ttl,
    substring(create_table_query, 1, 220) as create_preview
from system.tables
where database = 'system'
  and name in ('query_log', 'part_log', 'text_log', 'asynchronous_metric_log', 'metric_log', 'trace_log')
order by table
```

## Notes
- If TTL exists but disk still grows, check whether TTL is executing (background pools / merges) and whether partitions are mergeable (`merges.md`, `metrics.md`).
- Log schema differs per table; to check freshness, query each table’s timestamp column (usually `event_time`) with a bounded `max(...)`.

