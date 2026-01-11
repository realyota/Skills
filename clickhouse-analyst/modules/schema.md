# Schema / table design review

Use when: persistent slowness, high read amplification, poor compression, too many parts, skewed partitions, MV problems.

## Primary sources
- Table DDL: `show create table db.table` (best) or `system.tables.create_table_query`
- Columns: `system.columns`
- Parts/partitions: `system.parts`
- Materialized views: `system.tables` where engine = 'MaterializedView'

## Partition sizing rules of thumb
- MergeTree-family: aim for partitions up to ~100–200 GiB.
- “Heavier merge” engines (Replacing/Aggregating/Collapsing/VersionedCollapsing/Summing): aim for partitions up to ~50 GiB.
- Minimum healthy partition size is roughly 1/50 of the target max (e.g., ~2–4 GiB for 100–200 GiB max; ~1 GiB for 50 GiB max).

## Quick triage queries

### 1) Spot tables with structural risk (parts + tiny parts)
```sql
select
    database,
    table,
    count() as parts,
    countIf(bytes_on_disk < 16 * 1024 * 1024) as tiny_parts,
    round(100.0 * tiny_parts / nullIf(parts, 0), 1) as tiny_pct,
    formatReadableSize(sum(bytes_on_disk)) as bytes_on_disk
from system.parts
where active
group by database, table
having parts >= 50
order by parts desc
limit 30
```

### 2) Wrong partitioning heuristic: too many tiny partitions
This flags tables where *partitions* are small (not just parts). For large deployments, run the table-specific version (filter by `database`+`table`).
```sql
select
    database,
    table,
    countDistinct(partition_id) as partitions,
    countIf(partition_bytes < 16 * 1024 * 1024) as tiny_partitions,
    round(100.0 * tiny_partitions / nullIf(partitions, 0), 1) as tiny_partitions_pct,
    formatReadableSize(quantile(0.5)(partition_bytes)) as p50_partition_bytes,
    formatReadableSize(quantile(0.9)(partition_bytes)) as p90_partition_bytes
from
(
    select
        database,
        table,
        partition_id,
        sum(bytes_on_disk) as partition_bytes
    from system.parts
    where active
    group by database, table, partition_id
)
group by database, table
having partitions >= 20
order by tiny_partitions_pct desc, partitions desc
limit 30
```

### 2b) Partition size summary with engine-aware thresholds
This flags “too small” and “too big” partitions using the rules above. Tune thresholds to your workload.
```sql
with
    200 * 1024 * 1024 * 1024 as max_bytes_mergetree,
    50 * 1024 * 1024 * 1024 as max_bytes_heavy,
    max_bytes_mergetree / 50 as min_bytes_mergetree,
    max_bytes_heavy / 50 as min_bytes_heavy
select
    t.database,
    t.name as table,
    t.engine,
    countDistinct(p.partition_id) as partitions,
    formatReadableSize(quantile(0.5)(p.partition_bytes)) as p50_partition_bytes,
    formatReadableSize(quantile(0.9)(p.partition_bytes)) as p90_partition_bytes,
    formatReadableSize(max(p.partition_bytes)) as max_partition_bytes,
    countIf(p.partition_bytes < multiIf(t.engine like '%ReplacingMergeTree%', min_bytes_heavy,
                                       t.engine like '%AggregatingMergeTree%', min_bytes_heavy,
                                       t.engine like '%CollapsingMergeTree%', min_bytes_heavy,
                                       t.engine like '%VersionedCollapsingMergeTree%', min_bytes_heavy,
                                       t.engine like '%SummingMergeTree%', min_bytes_heavy,
                                       min_bytes_mergetree)) as too_small_partitions,
    countIf(p.partition_bytes > multiIf(t.engine like '%ReplacingMergeTree%', max_bytes_heavy,
                                       t.engine like '%AggregatingMergeTree%', max_bytes_heavy,
                                       t.engine like '%CollapsingMergeTree%', max_bytes_heavy,
                                       t.engine like '%VersionedCollapsingMergeTree%', max_bytes_heavy,
                                       t.engine like '%SummingMergeTree%', max_bytes_heavy,
                                       max_bytes_mergetree)) as too_big_partitions
from
(
    select
        database,
        table,
        partition_id,
        sum(bytes_on_disk) as partition_bytes
    from system.parts
    where active
    group by database, table, partition_id
) as p
inner join system.tables as t
    on t.database = p.database and t.name = p.table
where t.engine like '%MergeTree%'
group by t.database, t.name, t.engine
having partitions >= 20
order by too_big_partitions desc, too_small_partitions desc, partitions desc
limit 50
```

### 3) Nullable-heavy tables (heuristic)
```sql
select
    database,
    table,
    count() as columns,
    countIf(type like 'Nullable%') as nullable_columns,
    round(100.0 * nullable_columns / nullIf(columns, 0), 1) as nullable_pct
from system.columns
group by database, table
having columns >= 10
order by nullable_pct desc, columns desc
limit 30
```

### 4) Materialized views overview
```sql
select
    database,
    name as view,
    engine,
    positionCaseInsensitive(create_table_query, ' to ') > 0 as has_to_clause,
    positionCaseInsensitive(create_table_query, ' join ') > 0 as mentions_join
from system.tables
where engine = 'MaterializedView'
order by database, view
limit 200
```

## What to look for (guidance for on-demand SQL generation)
- ORDER BY vs query predicates: mismatch drives scans and low cache effectiveness.
- Partitioning: too granular creates tiny parts; too coarse creates huge merges and long retention drops.
- MV design: prefer explicit `TO target_table`; avoid complex joins inside MV when possible.
- Column types/codecs: avoid excessive Nullables and wide strings on primary key.

## Next steps (on demand)
Ask the model to generate table-specific queries with safeguards:
- Partition skew: group `system.parts` by `partition_id` for a single table (bounded, top-N).
- “Why many parts?”: correlate `system.part_log` NewPart rates with that table (`ingestion.md`).
- Query alignment: use `system.query_log.tables` to see which queries hit the table (`reporting.md`).
 - MV execution issues: use `query_views_log.md` to attribute cost/errors to views.
