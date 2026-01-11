# Query performance (SELECT)

Use when: timeouts, p95 latency spikes, “slow query”, “high read bytes”, “too many rows read”, CPU-heavy queries.

## Primary sources
- Current state: `system.processes`
- History: `system.query_log` (require time bounds)

## Quick triage queries (run in order)

### 1) What’s slow right now?
```sql
select
    query_id,
    user,
    round(elapsed, 1) as elapsed_sec,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(memory_usage) as memory,
    read_rows,
    substring(query, 1, 120) as query_preview
from system.processes
where is_cancelled = 0
order by elapsed desc
limit 20
```

### 2) Did latency/failures change recently?
```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    count() as queries,
    countIf(type like 'Exception%') as failed,
    round(avg(query_duration_ms)) as avg_ms,
    round(quantile(0.95)(query_duration_ms)) as p95_ms,
    round(max(query_duration_ms)) as max_ms,
    formatReadableSize(sum(read_bytes)) as read_bytes,
    formatReadableSize(sum(memory_usage)) as memory
from system.query_log
where event_time > now() - interval 1 hour
  and type in ('QueryFinish', 'ExceptionWhileProcessing')
group by ts
order by ts desc
```

### 3) Which query pattern is the top offender?
Use `normalized_query_hash` to group by “same shape” queries.
```sql
select
    normalized_query_hash,
    count() as executions,
    round(avg(query_duration_ms)) as avg_ms,
    round(quantile(0.95)(query_duration_ms)) as p95_ms,
    formatReadableSize(sum(read_bytes)) as total_read,
    formatReadableSize(sum(memory_usage)) as total_memory,
    any(substring(query, 1, 140)) as query_sample
from system.query_log
where event_time > now() - interval 24 hour
  and type = 'QueryFinish'
  and query_kind = 'Select'
group by normalized_query_hash
having executions > 5
order by total_read desc
limit 30
```

### 4) What’s failing?
```sql
select
    exception_code,
    count() as failures,
    any(substring(exception, 1, 140)) as example_exception,
    any(substring(query, 1, 140)) as example_query
from system.query_log
where event_time > now() - interval 24 hour
  and type like 'Exception%'
group by exception_code
order by failures desc
limit 20
```

## How to interpret quickly
- High `total_read` or `read_rows` → likely scan / poor ORDER BY alignment / too many parts → chain to `merges.md` and `schema.md`.
- High `memory_usage` or OOM codes → chain to `memory.md`.
- Frequent small queries with high p95 → check concurrency, caches, and IO saturation → chain to `metrics.md` and `caches.md`.

## Generate variants safely (on demand)
Ask the model to generate *bounded* variants of the above queries:
- Filter by `user`, `query_id`, `databases`, `tables`, `client_name`, `initial_query_id`.
- Change window (`now() - interval 1 hour` → `24 hour` / `7 day`) only when needed.
- For heavy clusters: add `cluster`-aware sampling or per-host grouping if available in your environment.

