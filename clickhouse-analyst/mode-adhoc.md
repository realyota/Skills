# Mode: ad-hoc debugging

Goal: answer a focused question by forming hypotheses, collecting minimal evidence, then iterating.

## Defaults
- Ask 1–3 clarifying questions before querying.
- Use `desc`/`show create` to adapt to environment differences.
- Prefer small, targeted queries; only expand time windows when needed.

## Good patterns
- Start with a “map” query (top tables by parts/size, top normalized queries by time/read)
- Drill down to one query/table/user
- Produce an answer + “how to keep measuring it” (a reusable query pattern)

