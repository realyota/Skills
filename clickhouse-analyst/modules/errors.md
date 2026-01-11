# Errors / exceptions

Use when: failed queries, repeated exceptions, crashes, mysterious client errors, “readonly” surprises.

## Primary sources
- Query failures: `system.query_log` (time-bounded)
- Server errors: `system.text_log` (time-bounded)
- Part/merge failures: `system.part_log` (time-bounded; schema varies by version)

## Quick triage queries

### 1) Top exceptions by code (last 24h)
```sql
select
    exception_code,
    count() as failures,
    any(substring(exception, 1, 160)) as example_exception,
    any(substring(query, 1, 160)) as example_query
from system.query_log
where event_time > now() - interval 24 hour
  and type like 'Exception%'
group by exception_code
order by failures desc
limit 20
```

### 2) Recent exceptions (last 1h)
```sql
select
    event_time,
    user,
    exception_code,
    substring(exception, 1, 200) as exception,
    substring(query, 1, 160) as query_preview
from system.query_log
where event_time > now() - interval 1 hour
  and type like 'Exception%'
order by event_time desc
limit 50
```

### 3) Server error log (last 1h)
```sql
select
    event_time,
    level,
    logger_name,
    query_id,
    substring(message, 1, 220) as message
from system.text_log
where event_time > now() - interval 1 hour
  and level in ('Fatal', 'Critical', 'Error')
order by event_time desc
limit 50
```

### 4) Part-log failure signal (last 24h)
This is intentionally schema-light; it’s a “do we have failures?” detector.
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

## What to do next
- If failures map to one query pattern → chain to `reporting.md` (and maybe `schema.md`).
- If error suggests memory/disk/parts/replication → chain to the corresponding module (`memory.md`, `storage.md`, `merges.md`, `replication.md`).
- If server-side errors dominate without query_ids → keep drilling in `text_log.md` (component-level breakdown).
 - If failures are view-related → use `query_views_log.md` to summarize by view, then validate view DDL (`schema.md`).
