# Automations

Batch and focus automation scripts for ClickHouse audits.

## Files
- `prompts/` — LLM prompts for audit modes.
- `scripts/audit.sh` — batch audit runner (all/conditional).
- `scripts/focus.sh` — focused audit runner (conditional with a focus skill).
- `scripts/redact-report.sh` — optional post‑processing redaction.
- `reports/` — generated reports (gitignored).

## Usage

From repo root:

```sh
# Conditional audit (default)
make audit

# Full audit (run all modules)
make audit-all

# Focused audit
make audit-focus FOCUS_SKILL=altinity-expert-clickhouse-memory
```

## Redaction

Set `AUDIT_REDACT=1` to suppress sensitive data in reports.
The prompt also instructs the LLM to avoid sensitive content when redaction is enabled.

```sh
AUDIT_REDACT=1 make audit
```
