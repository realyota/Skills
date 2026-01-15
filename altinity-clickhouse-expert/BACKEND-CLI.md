# Backend: CLI (`scripts/` + `clickhouse-client`)

Use this backend when you can spawn processes and have `clickhouse-client` available.

## Where the runnable scripts live

All runnable scripts live in the skill root, next to `SKILL.md`, under `scripts/`.
Invoke them from the skill root (recommended) or via an absolute path, regardless of your current directory.

## Quick start

```bash
# Test connection (shows hostname, version, uptime)
scripts/run-agent.sh --test-connection

# Run one agent (SQL -> LLM -> JSON)
scripts/run-agent.sh overview "health check"

# Dry-run (SQL only, no LLM)
scripts/run-agent.sh reporting "p95 spike" --dry-run
```

## Connection configuration

Preferred: environment variables (keeps passwords out of shell history):

```bash
export CLICKHOUSE_HOST=<hostname>
export CLICKHOUSE_USER=<username>
export CLICKHOUSE_PASSWORD=<password>
export CLICKHOUSE_SECURE=1          # if TLS required
export CLICKHOUSE_PORT=9440         # optional, default 9000
export CLICKHOUSE_DATABASE=default  # optional
```

Override env vars by passing explicit clickhouse-client args after `--`:

```bash
scripts/run-agent.sh reporting "p95 spike" -- --host=<host> --user=<user> --password=<pass>
```

## Running agents

- List available agents: `scripts/run-agent.sh --list-agents`
- Run an agent: `scripts/run-agent.sh <agent> "<context>"`
- Select LLM provider: `--llm-provider claude|codex|gemini`
- Select model (if provider supports it): `--llm-model <name>`

## Cluster wrappers (`clusterAllReplicas`)

Some agent `queries.sql` use `clusterAllReplicas('{cluster}', system.<table>)` for per-node system tables (especially `*_log` tables).

Runner behavior:
- Default: keep wrappers only if `system.zookeeper_connection` is active.
- If `{cluster}` macro is missing and no `--cluster-name` is provided: unwrap wrappers to local `system.<table>`.
- `--single-node`: always unwrap.
- `--cluster-name <name>`: replace `{cluster}` with `<name>` before running (still unwraps if zookeeper is inactive or `--single-node`).

## Artifacts + timeouts

```bash
export CH_ANALYST_KEEP_ARTIFACTS=1
export CH_ANALYST_QUERY_TIMEOUT_SEC=60  # set to 0 to disable
```

Artifacts are saved under `runs/<timestamp>-<agent>/` (final SQL, prompt, query results/errors, raw/validated model output).

