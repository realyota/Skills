# Skills

This repository contains skills used for ClickHouse DB performance and schema analysis and helper workflows.

## Core Skills
- `altinity-expert-clickhouse/`: Modular ClickHouse diagnostic skill set. Each module is a standalone skill under `altinity-expert-clickhouse/skills/` (e.g., memory, merges, replication).

## Experimental Skills 
- `experimental/codex-summarize-pipeline/`: Chunk→reduce pipeline for summarizing large articles/files into `summaries/*.md`.
- `experimental/github-triage/`: Search and summarize relevant GitHub issues/PRs using `gh`.
- `experimental/sub-agent/`: Prototype sub-agent workflow (multi-agent attempt by exec of next codex/claude inside skill processing).

## Conventions
- Each skill lives in its own directory and includes a `SKILL.md`.
- Supporting content is stored next to `SKILL.md` (e.g., `modules/`, scripts, prompts).
