# Server logs via `system.text_log`

Use when: you need server-side evidence (Keeper issues, merge errors, disk errors, config reloads, crashes).

## Primary source
- `system.text_log` (time-bounded)

## Quick triage queries

### 1) Level distribution (last 1h)
```sql
select
    level,
    count() as messages,
    uniq(logger_name) as components
from system.text_log
where event_time > now() - interval 1 hour
group by level
order by
    multiIf(level = 'Fatal', 1, level = 'Critical', 2, level = 'Error', 3,
            level = 'Warning', 4, level = 'Notice', 5, level = 'Information', 6, 7)
```

### 2) Recent critical/error messages (last 1h)
```sql
select
    event_time,
    level,
    logger_name,
    query_id,
    substring(message, 1, 240) as message
from system.text_log
where event_time > now() - interval 1 hour
  and level in ('Fatal', 'Critical', 'Error')
order by event_time desc
limit 100
```

### 3) Top noisy error components (last 24h)
```sql
select
    logger_name,
    count() as errors,
    any(substring(message, 1, 160)) as sample
from system.text_log
where event_time > now() - interval 24 hour
  and level in ('Fatal', 'Critical', 'Error')
group by logger_name
order by errors desc
limit 30
```

## Notes
- `system.text_log` can be disabled or truncated; if it’s empty, confirm server log configuration and retention.
- For incident response, keep windows small first (1h/6h) and only widen if needed.

