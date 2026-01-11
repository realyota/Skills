# Merges / parts pressure

Use when: “too many parts”, high background merge load, long merges, slow queries due to many parts, slow inserts due to merge backlog.

## Primary sources
- Current merges: `system.merges` (if available)
- Historical merge timings/errors: `system.part_log` (time-bounded)
- Parts inventory: `system.parts`

## Quick triage queries

### 1) Are merges currently running?
```sql
select
    database,
    table,
    elapsed,
    progress,
    num_parts,
    formatReadableSize(total_size_bytes_compressed) as total_size
from system.merges
order by elapsed desc
limit 50
```

### 2) Merge activity trend (last 24h)
```sql
select
    toStartOfHour(event_time) as hour,
    countIf(event_type = 'MergeParts') as merges,
    countIf(event_type like 'MergePartsFailed%') as merge_failures
from system.part_log
where event_time > now() - interval 24 hour
group by hour
order by hour desc
limit 24
```

### 3) “Hot” tables: merge volume and failures (last 24h)
```sql
select
    database,
    table,
    countIf(event_type = 'MergeParts') as merges,
    countIf(event_type like 'MergePartsFailed%') as merge_failures
from system.part_log
where event_time > now() - interval 24 hour
  and (event_type = 'MergeParts' or event_type like 'MergePartsFailed%')
group by database, table
having merges > 0
order by merge_failures desc, merges desc
limit 30
```

Note: `system.part_log` schemas vary; if this query fails, run `desc system.part_log` and regenerate a version-compatible summary.

## How to interpret quickly
- High parts count + frequent `NewPart` events → ingestion batching/partitioning issue → chain to `ingestion.md` and `schema.md`.
- Long merges + high disk utilization → storage bottleneck → chain to `storage.md`.
- Merge failures / errors → chain to `errors.md` and `text_log.md`.

## Generate variants safely (on demand)
- Summarize by `partition_id` for a single table to spot partition skew.
- Correlate merge times with insert/part rates to separate “bad batching” vs “slow IO”.
- If `system.merges` is missing, rely on `system.part_log` merge events + `system.parts` counts.
