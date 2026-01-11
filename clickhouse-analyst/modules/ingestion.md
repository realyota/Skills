# Ingestion (INSERT) performance

Use when: slow inserts, spikes in part count, “too many parts”, merge backlog driven by micro-batches.

## Primary sources
- Current inserts: `system.processes`
- Insert history: `system.query_log` (time-bounded)
- Part creation & merge triggers: `system.part_log` (time-bounded)

## Quick triage queries

### 1) What inserts are running right now?
```sql
select
    query_id,
    user,
    round(elapsed, 1) as elapsed_sec,
    written_rows,
    formatReadableSize(written_bytes) as written_bytes,
    formatReadableSize(memory_usage) as memory,
    substring(query, 1, 120) as query_preview
from system.processes
where is_cancelled = 0
  and query_kind = 'Insert'
order by elapsed desc
limit 20
```

### 2) Insert throughput/latency trend (last 1h)
```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    count() as inserts,
    round(avg(query_duration_ms)) as avg_ms,
    round(quantile(0.95)(query_duration_ms)) as p95_ms,
    sum(written_rows) as rows,
    formatReadableSize(sum(written_bytes)) as bytes
from system.query_log
where event_time > now() - interval 1 hour
  and type = 'QueryFinish'
  and query_kind = 'Insert'
group by ts
order by ts desc
```

### 3) Are we generating too many parts too fast?
Rule of thumb: sustained > 1 new part/sec per table is a red flag (micro-batches).
```sql
select
    database,
    table,
    count() as new_parts,
    round(new_parts / 3600.0, 3) as new_parts_per_sec,
    formatReadableSize(avg(part_size)) as avg_part_size
from system.part_log
where event_time > now() - interval 1 hour
  and event_type = 'NewPart'
group by database, table
having new_parts > 10
order by new_parts desc
limit 30
```

### 3b) Same check, but severity-labeled (last 1h)
```sql
select
    database,
    table,
    count() as new_parts,
    round(new_parts / 3600.0, 3) as new_parts_per_sec,
    formatReadableSize(quantile(0.5)(part_size)) as p50_part_size,
    formatReadableSize(quantile(0.9)(part_size)) as p90_part_size,
    multiIf(new_parts_per_sec > 5, 'Critical', new_parts_per_sec > 1, 'Major', new_parts_per_sec > 0.5, 'Moderate', 'OK') as severity
from system.part_log
where event_time > now() - interval 1 hour
  and event_type = 'NewPart'
group by database, table
having new_parts > 10
order by
    multiIf(severity = 'Critical', 1, severity = 'Major', 2, severity = 'Moderate', 3, 4),
    new_parts desc
limit 50
```

### 4) What does “part size” look like for the hottest tables?
This helps separate “too many parts” from “reasonable rate but tiny parts”.
```sql
select
    database,
    table,
    count() as new_parts,
    formatReadableSize(quantile(0.5)(part_size)) as p50_part_size,
    formatReadableSize(quantile(0.9)(part_size)) as p90_part_size
from system.part_log
where event_time > now() - interval 24 hour
  and event_type = 'NewPart'
group by database, table
having new_parts > 50
order by new_parts desc
limit 30
```

### 5) Part-log error signal discovery (last 24h)
Look for failed event types first, then drill down.
```sql
select
    event_type,
    count() as rows
from system.part_log
where event_time > now() - interval 24 hour
group by event_type
order by rows desc
limit 50
```

## What it usually means
- High `new_parts_per_sec` + small `avg_part_size` → batching problem or overly granular partitions → chain to `merges.md` and `schema.md`.
- High insert latency with normal part rate → check disk/IO and background pools → chain to `storage.md` and `metrics.md`.
- High insert memory usage → chain to `memory.md`.

## Generate variants safely (on demand)
- Add filters for one table (`database`, `table`) or one pipeline user/client.
- For longer windows, move from 1h to 24h and group by 15m/1h.
- If `system.part_log` is disabled, approximate using `system.parts` (parts count delta over time) and/or monitoring data.
