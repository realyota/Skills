# Mutations (ALTER UPDATE/DELETE) tracking

Use when: mutations stuck, ALTER UPDATE/DELETE slow, background backlog, “parts are not getting cleaned up”.

## Primary sources
- Current status: `system.mutations`
- Downstream bottlenecks: `merges.md`, `errors.md`, `text_log.md`

## Quick triage queries

### 1) Pending mutations (oldest first)
```sql
select
    database,
    table,
    mutation_id,
    create_time,
    parts_to_do,
    is_done,
    substring(command, 1, 120) as command,
    latest_fail_time,
    substring(latest_fail_reason, 1, 200) as latest_fail_reason
from system.mutations
where not is_done
order by create_time
limit 100
```

### 2) “Stuck” heuristic (age-based)
```sql
with
    dateDiff('minute', create_time, now()) as age_minutes
select
    database,
    table,
    mutation_id,
    age_minutes,
    parts_to_do,
    multiIf(age_minutes > 1440, 'Critical', age_minutes > 360, 'Major', age_minutes > 60, 'Moderate', 'OK') as severity,
    substring(latest_fail_reason, 1, 200) as latest_fail_reason
from system.mutations
where not is_done
  and age_minutes > 30
order by age_minutes desc
limit 100
```

## How to interpret quickly
- If mutations are old and `parts_to_do` isn’t moving → merges/backpressure → chain to `merges.md` and `storage.md`.
- If `latest_fail_reason` is present → treat as error-first → chain to `errors.md` / `text_log.md`.

