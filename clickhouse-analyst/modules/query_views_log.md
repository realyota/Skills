# `system.query_views_log` (materialized view execution)

Use when: materialized view execution is slow, view failures/exceptions, “why is MV behind”, or you need to attribute cost/errors to view processing.

## Primary sources
- View execution log: `system.query_views_log` (time-bounded)
- View DDL/structure: `system.tables` / `show create table`
- Downstream symptoms: `reporting.md`, `errors.md`, `text_log.md`, `replication.md`, `merges.md`

## First: verify schema (versions vary)
Avoid guessing columns; discover them first:
```sql
select
    name,
    type
from system.columns
where database = 'system'
  and table = 'query_views_log'
order by name
limit 200
```

## Quick health checks (usually safe)

### 1) Is the log populated recently?
```sql
select
    max(event_time) as last_event_time,
    countIf(event_time > now() - interval 1 hour) as rows_last_1h
from system.query_views_log
```

### 2) Volume trend (last 24h)
```sql
select
    toStartOfHour(event_time) as hour,
    count() as rows
from system.query_views_log
where event_time > now() - interval 24 hour
group by hour
order by hour desc
limit 24
```

## What to ask the model to generate next (on demand)
Once you’ve confirmed column names, generate a bounded summary like:
- “Top view names by total duration / max duration in last 24h”
- “Top view names by exceptions / error codes”
- “Correlate by source table / initial query id to see which inserts are driving view work”

Guardrails:
- Always keep a time bound on `event_time` / `event_date`.
- Prefer grouping by a view identifier (often `view_name`) rather than dumping raw rows.
- Show one example row for the top offenders (bounded).

