# Testing: `altinity-expert-clickhouse` Skills

This test suite is scenario-driven:
- Each skill has a test directory under `tests/<skill>/` with `dbschema.sql`, optional `scenarios/*.sql`, `prompt.md`, and `expected.md`.
- `tests/runner/run-test.sh` sets up a dedicated DB, runs scenario SQL, generates a Markdown report via an LLM (optional), and optionally verifies the report against `expected.md` via an LLM.

## Prerequisites

- `clickhouse-client` installed and able to connect to your target ClickHouse using `CLICKHOUSE_*` env vars.
- `jq` (recommended) for parsing verification output.
- One of:
  - `codex` CLI (default `LLM_PROVIDER=codex`)
  - `claude` CLI (`LLM_PROVIDER=claude`)

## Quick Smoke Checks

```bash
cd altinity-expert-clickhouse/tests

# Start a test ClickHouse in Docker (default image tag is `CLICKHOUSE_VERSION=25.8`)
make up

# Syntax checks
bash -n runner/run-test.sh runner/verify-report.sh runner/lib/common.sh

# Connection check (uses CLICKHOUSE_* env vars; see below)
make validate

# SQL-only run (no LLM, no verification)
make test-overview RUNNER_FLAGS=--skip-llm

# Full suite (SQL-only)
make test RUNNER_FLAGS=--skip-llm
```

### Running different ClickHouse versions

```bash
cd altinity-expert-clickhouse/tests
make reset CLICKHOUSE_VERSION=24.12
make test-overview RUNNER_FLAGS=--skip-llm CLICKHOUSE_VERSION=24.12
```

### Connection environment variables

`tests/runner/lib/common.sh` uses:
- `CLICKHOUSE_HOST` (defaults to `arm` if unset)
- `CLICKHOUSE_PORT` (default `9000`)
- `CLICKHOUSE_USER` (default `default`)
- `CLICKHOUSE_PASSWORD` (optional)
- `CLICKHOUSE_SECURE` (`true|1|yes|on` enables `--secure`)

## LLM Provider Examples

```bash
cd altinity-expert-clickhouse/tests

# Run with Claude
make test-overview LLM_PROVIDER=claude

# Pick Codex models (optional)
make test-overview LLM_PROVIDER=codex CODEX_MODEL=gpt-5.2-codex-mini CODEX_VERIFY_MODEL=gpt-5.2-codex-mini
```

Note: `LLM_PROVIDER=gemini` is currently a stub in `runner/run-test.sh`.

## Scenario Error Handling (.ignore-errors)

The test runner defaults to fail-fast for scenario SQL. You can opt into error-tolerant
scenario execution for a specific skill by creating a `.ignore-errors` file in that
skill’s test directory (for example, `tests/altinity-expert-clickhouse-replication/.ignore-errors`).

Behavior:
- When `.ignore-errors` exists, `run-test.sh` executes scenario SQL via
  `run_script_in_db_ignore_errors`, which uses `clickhouse-client --ignore-error`.
- Without `.ignore-errors`, scenario SQL runs via `run_script_in_db`, and any
  ClickHouse error stops the test (due to `set -euo pipefail`).
- This only affects scenario SQL in `tests/<skill>/scenarios/*.sql`. It does not
  change schema creation, report generation, or verification.

Use `.ignore-errors` when:
- Errors are expected and are the signal under test (e.g., readonly replicas,
  Keeper issues, or intentionally failing queries).
- You want the test to continue so the skill can diagnose the failure state.

Do NOT use `.ignore-errors` when:
- Scenario SQL is meant to succeed (errors indicate a broken test setup).
- You need fail-fast to prevent misleading or incomplete reports.

Tradeoffs:
- Pros: simple opt-in per skill; preserves strict default; keeps tests running.
- Cons: coarse-grained; can mask unexpected failures within the scenario.

---

## Coordinator Tests (Adaptive Chaining)
This suite does not currently automate multi-skill chaining. If you want to manually validate routing behavior, run `overview` first, then select a specialist skill based on the report’s recommendations:

```bash
cd altinity-expert-clickhouse/tests
make test-overview
make test-memory
make test-merges
```

---

## Validation Checklist

For each test:
- [ ] Agent selection matches symptom
- [ ] Runner can reach ClickHouse (or fails with clear stderr)
- [ ] SQL runs in order; later query errors don't erase earlier results (e.g. `query_views_log` issues)
- [ ] JSON output is valid and structurally correct (required keys; `.agent` matches the agent)
- [ ] Severity ratings are reasonable
- [ ] `chain_to` suggestions are relevant
- [ ] Recommendations are actionable
- [ ] No sensitive data leaked in output
