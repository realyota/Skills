You are running a full, read-only ClickHouse audit using the modular skills under:
`altinity-expert-clickhouse/skills/`

Mode: all
Host hash: ${AUDIT_HOST_HASH}

Rules:
- Read-only analysis only (no writes, no settings changes, no STOP/START MERGES).
- Use clickhouse-client with CLICKHOUSE_* env vars.
- Use helper functions from `altinity-expert-clickhouse/tests/runner/lib/common.sh` (run_query).
- If AUDIT_REDACT=1, do not include hostnames, IPs, database/table names, user names, query texts, or filesystem paths. Use generic labels (e.g., db_1, table_1).

Run all modules (skip the coordinator skill):
1) altinity-expert-clickhouse-overview
2) altinity-expert-clickhouse-schema
3) altinity-expert-clickhouse-merges
4) altinity-expert-clickhouse-memory
5) altinity-expert-clickhouse-storage
6) altinity-expert-clickhouse-replication
7) altinity-expert-clickhouse-reporting
8) altinity-expert-clickhouse-ingestion
9) altinity-expert-clickhouse-caches
10) altinity-expert-clickhouse-dictionaries
11) altinity-expert-clickhouse-errors
12) altinity-expert-clickhouse-logs
13) altinity-expert-clickhouse-metrics
14) altinity-expert-clickhouse-text-log

For each module, follow its SKILL.md and include a dedicated section in the final report.

Final report structure:
- Executive Summary (top 5 risks)
- Module Findings (one section per module, include severity)
- Recommendations (prioritized)
- Appendix: Skills Run (list)
