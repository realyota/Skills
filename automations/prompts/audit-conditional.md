You are running a conditional, read-only ClickHouse audit using the modular skills under:
`altinity-expert-clickhouse/skills/`

Mode: conditional
Host hash: ${AUDIT_HOST_HASH}

Rules:
- Read-only analysis only (no writes, no settings changes, no STOP/START MERGES).
- Use clickhouse-client with CLICKHOUSE_* env vars.
- Use helper functions from `altinity-expert-clickhouse/tests/runner/lib/common.sh` (run_query).
- If AUDIT_REDACT=1, do not include hostnames, IPs, database/table names, user names, query texts, or filesystem paths. Use generic labels (e.g., db_1, table_1).

Start with `altinity-expert-clickhouse-overview`. Based on findings, decide which additional skills to load next.
Only run skills that are relevant to current findings.

Final report structure:
- Executive Summary (top 5 risks)
- Module Findings (one section per module used, include severity)
- Recommendations (prioritized)
- Appendix: Skills Run (list)
