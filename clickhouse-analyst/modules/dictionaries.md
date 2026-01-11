# External dictionaries

Use when: dictionary load failures, slow reloads, unexpected RAM usage from dictionaries.

## Primary source
- `system.dictionaries`

## Quick triage queries

### 1) Biggest dictionaries by memory
```sql
select
    database,
    name,
    status,
    origin,
    type,
    formatReadableSize(bytes_allocated) as memory,
    element_count as elements,
    loading_duration,
    last_successful_update_time,
    substring(last_exception, 1, 200) as last_exception
from system.dictionaries
order by bytes_allocated desc
limit 50
```

### 2) Health summary
```sql
select
    database,
    name,
    status,
    multiIf(
        status = 'FAILED', 'Critical',
        status = 'LOADING', 'Moderate',
        last_exception != '', 'Major',
        dateDiff('hour', last_successful_update_time, now()) > 24, 'Moderate',
        'OK'
    ) as severity,
    last_successful_update_time,
    substring(last_exception, 1, 200) as last_exception
from system.dictionaries
order by
    multiIf(severity = 'Critical', 1, severity = 'Major', 2, severity = 'Moderate', 3, 4),
    bytes_allocated desc
limit 100
```

## What to do next
- If dictionaries dominate RAM → treat as memory policy issue (`memory.md`) and validate dictionary lifetimes/update strategy.
- If dictionaries fail to load → look for source connectivity/auth errors in `text_log.md`.

