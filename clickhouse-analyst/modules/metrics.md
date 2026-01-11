# Metrics (real-time saturation signals)

Use when: overall slowness, spikes in concurrency, “server is overloaded”, capacity headroom questions.

## Primary sources
- Gauges: `system.metrics`
- Async gauges: `system.asynchronous_metrics`
- Current work: `system.processes`

## Quick snapshot

### 1) High-level “is it saturated?”
```sql
with
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as os_mem_total,
    (select value from system.asynchronous_metrics where metric = 'MemoryResident') as mem_resident,
    (select value from system.asynchronous_metrics where metric = 'LoadAverage1') as load1,
    (select count() from system.asynchronous_metrics where metric like 'CPUFrequencyMHz%') as cpu_cores,
    (select value from system.metrics where metric = 'Query') as running_queries,
    getSetting('max_concurrent_queries') as max_concurrent_queries
select
    running_queries,
    max_concurrent_queries,
    round(100.0 * running_queries / nullIf(max_concurrent_queries, 0), 1) as queries_util_pct,
    formatReadableSize(mem_resident) as mem_resident,
    formatReadableSize(os_mem_total) as os_mem_total,
    round(100.0 * mem_resident / nullIf(os_mem_total, 0), 1) as mem_util_pct,
    round(load1, 2) as load_avg_1m,
    cpu_cores,
    round(load1 / nullIf(cpu_cores, 0), 2) as load_per_core
```

### 2) What types of work are running right now?
```sql
select
    query_kind,
    count() as queries,
    formatReadableSize(sum(memory_usage)) as memory,
    formatReadableSize(sum(read_bytes)) as read_bytes,
    formatReadableSize(sum(written_bytes)) as written_bytes
from system.processes
where is_cancelled = 0
group by query_kind
order by queries desc
```

## How to interpret quickly
- High `queries_util_pct` → concurrency pressure; identify top query patterns (`reporting.md`) and consider queueing/limits.
- High `mem_util_pct` → memory pressure; isolate top memory queries (`memory.md`) and non-query consumers.
- High `load_per_core` with normal queries/memory → likely IO or background pressure; check `storage.md`, `merges.md`, `replication.md`.

## Generate variants safely (on demand)
- Expand snapshot with additional metrics you care about (search in `system.metrics` / `system.asynchronous_metrics` by `like '%Connection%'`, `like 'Background%'`, etc.).
- Always keep “discovery queries” bounded (filter `value > 0`, `limit`, or `like` patterns).

