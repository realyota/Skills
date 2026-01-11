# Mode: incident response

Goal: stabilize service first, then narrow to the smallest set of likely causes with minimal, safe queries.

## Defaults
- Timebox: start with last 1 hour; expand only if needed.
- Prefer current-state tables (`system.processes`, replication queue, disk/memory async metrics) before deep log mining.
- Stop early if you have a safe mitigation and a clear “next evidence to collect”.

## Triage order (typical)
1) “What is happening right now?”
   - active queries / memory usage / write pressure
2) “Is the node saturated?”
   - memory resident vs total, load vs cpu, disk space, connections, background queues
3) “Is it one query pattern / one table?”
   - top normalized queries, hot tables, too many parts / merge backlog
4) “Is there an error pattern?”
   - query_log exceptions, text_log errors

## When to chain modules
- Slow queries → `reporting.md` then `memory.md` / `caches.md`
- Slow inserts / too many parts → `ingestion.md` then `merges.md` / `storage.md`
- Replication lag / readonly → `replication.md` then `merges.md` / `storage.md`
- OOM → `memory.md` then `reporting.md` / `merges.md`

## Incident output (short)
- Current impact + since when
- Top 1–3 suspected contributors (query/table/resource)
- Immediate mitigation options + risk
- Next evidence to confirm root cause

