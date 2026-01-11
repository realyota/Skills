# Replication / Keeper (ZooKeeper) health

Use when: replication lag, readonly replicas, large replication queues, Keeper/ZooKeeper issues.

## Primary sources
- Replica status: `system.replicas`
- Queue backlog: `system.replication_queue`
- Recent errors: `system.text_log` / `system.query_log` (time-bounded)

## Quick triage queries

### 1) Are any replicas readonly / unhealthy?
```sql
select
    database,
    table,
    replica_name,
    is_readonly,
    is_session_expired,
    future_parts,
    parts_to_check,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    log_max_index - log_pointer as log_gap
from system.replicas
order by is_readonly desc, is_session_expired desc, queue_size desc
limit 50
```

### 2) What’s stuck in the replication queue?
```sql
select
    database,
    table,
    type,
    create_time,
    required_quorum,
    source_replica,
    new_part_name,
    last_exception
from system.replication_queue
where last_exception != ''
   or now() - create_time > interval 10 minute
order by create_time
limit 50
```

## How to interpret quickly
- `is_readonly=1` or session expiry signals → Keeper connectivity/health, disk full, or local errors. Check `storage.md` and `text_log.md`.
- Large `queue_size` + many `merges_in_queue` → merges/disk bottleneck → chain to `merges.md` and `storage.md`.
- Large `log_gap` → replica cannot catch up (IO, CPU, or network); inspect lagging hosts and queue content.

## Generate variants safely (on demand)
- Filter to one table; compare across hosts if `system.replicas` includes host identifiers in your setup.
- Summarize queue by `type` and by hour (`toStartOfHour(create_time)`) with bounded windows.

