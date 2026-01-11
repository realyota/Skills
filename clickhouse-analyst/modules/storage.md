# Storage / disk / IO pressure

Use when: disk full, slow merges/inserts due to IO, large tables/parts, log tables consuming disk.

## Primary sources
- Disk inventory: `system.disks`
- Biggest consumers: `system.parts`
- Log table bloat/TTL: `logs.md`

## Quick triage queries

### 1) Disk free space
```sql
select
    name,
    path,
    formatReadableSize(total_space) as total,
    formatReadableSize(free_space) as free,
    round(100.0 * free_space / nullIf(total_space, 0), 1) as free_pct
from system.disks
order by free_space asc
```

### 2) Biggest tables by bytes on disk
```sql
select
    database,
    table,
    formatReadableSize(sum(bytes_on_disk)) as bytes_on_disk,
    count() as parts,
    formatReadableSize(avg(bytes_on_disk)) as avg_part_size
from system.parts
where active
group by database, table
order by sum(bytes_on_disk) desc
limit 30
```

### 3) Tiny parts hotlist (IO amplification risk)
```sql
select
    database,
    table,
    countIf(bytes_on_disk < 16 * 1024 * 1024) as tiny_parts,
    count() as total_parts,
    round(100.0 * tiny_parts / nullIf(total_parts, 0), 1) as tiny_pct
from system.parts
where active
group by database, table
having total_parts >= 50
order by tiny_pct desc, total_parts desc
limit 30
```

## How to interpret quickly
- Low `free_pct` → immediate risk; investigate biggest tables and log tables (`logs.md`), then cleanup/TTL or add capacity.
- High `tiny_pct` → ingestion batching/partitioning issue; drives merges and query overhead → chain to `ingestion.md`, `merges.md`, `schema.md`.

## Generate variants safely (on demand)
- Drill down per partition (`partition_id`) for one table to detect skew.
- Split by disk volume if using multiple disks (match `system.parts.disk_name` if available).

