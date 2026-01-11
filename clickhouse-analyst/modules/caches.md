# Caches (mark / uncompressed / query cache)

Use when: high read amplification, repeated cold reads, low cache hit ratios, “why is it reading so much”, memory tied up in caches.

## Primary sources
- Cache hit/miss counters: `system.events`
- Cache sizes: `system.asynchronous_metrics`
- Working-set proxies: `system.parts` (marks/PK bytes)

## Quick checks

### 1) Mark cache hit ratio + size
```sql
with
    (select value from system.events where event = 'MarkCacheHits') as hits,
    (select value from system.events where event = 'MarkCacheMisses') as misses,
    hits / nullIf(hits + misses, 0) as hit_ratio,
    (select value from system.asynchronous_metrics where metric = 'MarkCacheBytes') as cache_bytes,
    (select sum(marks_bytes) from system.parts where active) as total_marks_bytes,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram
select
    round(hit_ratio, 3) as mark_cache_hit_ratio,
    formatReadableSize(cache_bytes) as mark_cache_bytes,
    round(100.0 * cache_bytes / nullIf(total_ram, 0), 2) as mark_cache_pct_of_ram,
    round(100.0 * cache_bytes / nullIf(total_marks_bytes, 0), 2) as pct_of_marks_cached,
    hits,
    misses
settings system_events_show_zero_values = 1
```

### 2) Uncompressed cache hit ratio + size (often disabled)
```sql
with
    (select value from system.events where event = 'UncompressedCacheHits') as hits,
    (select value from system.events where event = 'UncompressedCacheMisses') as misses,
    hits / nullIf(hits + misses, 0) as hit_ratio,
    (select value from system.asynchronous_metrics where metric = 'UncompressedCacheBytes') as cache_bytes,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram
select
    round(hit_ratio, 3) as uncompressed_hit_ratio,
    formatReadableSize(cache_bytes) as uncompressed_cache_bytes,
    round(100.0 * cache_bytes / nullIf(total_ram, 0), 2) as uncompressed_pct_of_ram,
    hits,
    misses
settings system_events_show_zero_values = 1
```

### 3) What tables dominate marks / PK-in-memory?
```sql
select
    database,
    table,
    formatReadableSize(sum(marks_bytes)) as marks_bytes,
    formatReadableSize(sum(primary_key_bytes_in_memory)) as pk_in_memory,
    count() as parts
from system.parts
where active
group by database, table
order by sum(marks_bytes) desc
limit 20
```

## How to interpret quickly
- Low mark cache hit ratio can be “normal” for wide scans; it matters most for workloads with selective reads.
- High `marks_bytes` across many tables + low cache hit → likely working set > cache size; consider tuning + schema/query changes (`schema.md`, `reporting.md`).
- Cache sizes competing with query memory → consider the tradeoff; follow your environment’s memory policy (`memory.md`).

## Optional (version-dependent)
- Query cache lives in `system.query_cache` (if present). If you want it, run `desc system.query_cache` first and generate a bounded summary query.

