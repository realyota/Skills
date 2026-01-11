# Overview: system health entry point

Use when: “health check”, “cluster slow”, “audit”, “what’s wrong”, unclear symptom.

## Primary sources
- Current activity: `system.processes`
- Object/parts: `system.tables`, `system.parts`
- Real-time pressure: `system.metrics`, `system.asynchronous_metrics`
- Recent failures: `system.query_log` / `system.text_log` (time-bounded)

## Quick entry queries

### 1) Identify node + basic headroom
```sql
select
    hostName() as host,
    version() as version,
    uptime() as uptime_sec,
    formatReadableTimeDelta(uptime()) as uptime,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as os_mem_total,
    (select value from system.asynchronous_metrics where metric = 'MemoryResident') as mem_resident
```

### 2) What’s running right now?
```sql
select
    count() as active_queries,
    formatReadableSize(sum(memory_usage)) as total_query_memory,
    formatReadableSize(sum(read_bytes)) as total_read_bytes,
    formatReadableSize(sum(written_bytes)) as total_written_bytes
from system.processes
where is_cancelled = 0
```

### 3) “Too many parts” hotspot tables
```sql
select
    database,
    table,
    count() as parts,
    formatReadableSize(sum(bytes_on_disk)) as bytes_on_disk,
    max(modification_time) as last_part_time
from system.parts
where active
group by database, table
order by parts desc
limit 20
```

### 4) Errors trend (last 24h)
```sql
select
    toStartOfHour(event_time) as hour,
    countIf(type like 'Exception%') as exceptions,
    countIf(type = 'QueryFinish') as finished
from system.query_log
where event_time > now() - interval 24 hour
group by hour
order by hour desc
limit 24
```

## What to do with the results (routing)
- Many active queries / large reads → `reporting.md` (then maybe `caches.md` / `memory.md`).
- High parts count / recent part creation → `ingestion.md` and `merges.md`.
- High resident memory vs total → `memory.md`.
- Errors dominated by a code / message → `errors.md` (and optionally `text_log.md`).
- Replication symptoms → `replication.md`.
- Disk/IO symptoms → `storage.md`.

## Audit mode note
If you need severity thresholds and ratio-based checks, also read `audit-patterns.md` and generate a small “findings table” query using `multiIf(...)` with your local baselines.

