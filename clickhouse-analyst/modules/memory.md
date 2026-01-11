# Memory / OOM

Use when: OOM errors, MemoryTracker exceptions, resident memory near total RAM, heavy queries causing memory spikes.

## Primary sources
- Current query memory: `system.processes`
- Historical peaks: `system.query_log` (time-bounded)
- Node memory: `system.asynchronous_metrics` (`OSMemoryTotal`, `MemoryResident`)
- Large in-memory consumers: `system.dictionaries`, `system.tables` (Memory/Join/Set engines)

## Quick triage queries

### 1) Node memory headroom
```sql
select
    hostName() as host,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as os_mem_total,
    (select value from system.asynchronous_metrics where metric = 'MemoryResident') as mem_resident,
    round(100.0 * mem_resident / nullIf(os_mem_total, 0), 1) as resident_pct
```

### 2) Biggest consumers right now (queries)
```sql
select
    query_id,
    user,
    round(elapsed, 1) as elapsed_sec,
    formatReadableSize(memory_usage) as memory,
    formatReadableSize(read_bytes) as read_bytes,
    read_rows,
    substring(query, 1, 140) as query_preview
from system.processes
where is_cancelled = 0
order by memory_usage desc
limit 20
```

### 3) Top memory queries (last 24h)
```sql
select
    normalized_query_hash,
    count() as executions,
    formatReadableSize(max(memory_usage)) as max_memory,
    round(quantile(0.95)(memory_usage)) as p95_memory_bytes,
    any(substring(query, 1, 140)) as query_sample
from system.query_log
where event_time > now() - interval 24 hour
  and type in ('QueryFinish', 'ExceptionWhileProcessing')
group by normalized_query_hash
order by max(memory_usage) desc
limit 30
```

### 4) Memory not from queries: dictionaries + memory-ish engines
```sql
select
    formatReadableSize((select sum(bytes_allocated) from system.dictionaries)) as dictionaries_bytes,
    formatReadableSize((select sum(total_bytes) from system.tables where engine in ('Memory', 'Set', 'Join'))) as memory_engines_bytes
```

## How to interpret quickly
- High resident_pct + low query memory → look for external processes or server-level caches; check `system.asynchronous_metrics` and OS.
- A few queries dominate memory → isolate those hashes/queries and chain to `reporting.md` and `schema.md`.
- OOMs during merges/inserts → chain to `merges.md` / `ingestion.md`.

## Generate variants safely (on demand)
- Filter query_log by `exception_code` for memory limits (varies by version; inspect recent exceptions).
- For timelines, group by `toStartOfFiveMinutes(event_time)` and take `max(memory_usage)`; keep windows bounded.

