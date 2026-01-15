#!/bin/bash
# Run a single ClickHouse analyst sub-agent
# 1. Execute SQL queries directly via clickhouse-client
# 2. Pass results to selected LLM for analysis (default: Codex)
#
# Dynamic fallback mode (enabled by default):
# - If static agent SQL fails due to schema/version drift, run-agent can fall back to a 2-pass dynamic mode:
#   Pass A: discover system table schemas (system.columns) + ask LLM to generate safe SQL (cluster-aware)
#   Execute: run generated SQL with caps (max_execution_time, max_result_rows)
#   Pass B: ask LLM to analyze results and emit JSON findings
#
# Usage:
#   ./run-agent.sh <agent-name> <context> [--llm-provider <claude|codex|gemini>] [--llm-model <name>] [--dry-run] [--single-node] [--cluster-name <name>] [-- <clickhouse-client args...>]
#   ./run-agent.sh --list-agents
#   ./run-agent.sh --test-connection [-- <clickhouse-client args...>]
#
# Environment variables for ClickHouse connection (used if no explicit args after --):
#   CLICKHOUSE_HOST     - ClickHouse server hostname (default: localhost)
#   CLICKHOUSE_PORT     - ClickHouse native port (default: 9000)
#   CLICKHOUSE_USER     - Username for authentication
#   CLICKHOUSE_PASSWORD - Password for authentication
#   CLICKHOUSE_SECURE   - Set to 1 for TLS connection (--secure flag)
#   CLICKHOUSE_DATABASE - Default database
#
# Examples:
#   ./run-agent.sh memory "OOM at 14:30" -- --host=prod-ch --user=admin
#   ./run-agent.sh reporting "p95 spike" --llm-provider gemini -- --host=prod-ch
#   ./run-agent.sh reporting "p95 spike" --dry-run -- --host=prod-ch
#   ./run-agent.sh --list-agents
#
#   # Using environment variables (no -- needed):
#   CLICKHOUSE_HOST=prod-ch CLICKHOUSE_USER=admin ./run-agent.sh memory "OOM"

set -euo pipefail

# Resolve paths relative to the skill root so the script works from any CWD.
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$SKILL_ROOT/agents"

usage() {
    echo "Usage: $0 <agent-name> <context> [--llm-provider <claude|codex|gemini>] [--llm-model <name>] [--dry-run] [--single-node] [--cluster-name <name>] [-- <clickhouse-client args...>]" >&2
    echo "       $0 --list-agents" >&2
    echo "       $0 --test-connection [-- <clickhouse-client args...>]" >&2
    echo "" >&2
    echo "Connection can be configured via CLICKHOUSE_HOST, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD," >&2
    echo "CLICKHOUSE_PORT, CLICKHOUSE_DATABASE, CLICKHOUSE_SECURE environment variables." >&2
}

list_agents() {
    for d in "$AGENTS_DIR"/*/; do
        if [[ -f "$d/queries.sql" && -f "$d/prompt.md" ]]; then
            basename "$d"
        fi
    done | sort | tr '\n' ' '
    echo
}

# Build clickhouse-client args from environment variables
build_ch_args_from_env() {
    local -a args=()
    [[ -n "${CLICKHOUSE_HOST:-}" ]] && args+=("--host=${CLICKHOUSE_HOST}")
    [[ -n "${CLICKHOUSE_PORT:-}" ]] && args+=("--port=${CLICKHOUSE_PORT}")
    [[ -n "${CLICKHOUSE_USER:-}" ]] && args+=("--user=${CLICKHOUSE_USER}")
    [[ -n "${CLICKHOUSE_PASSWORD:-}" ]] && args+=("--password=${CLICKHOUSE_PASSWORD}")
    [[ -n "${CLICKHOUSE_DATABASE:-}" ]] && args+=("--database=${CLICKHOUSE_DATABASE}")
    [[ "${CLICKHOUSE_SECURE:-0}" == "1" ]] && args+=("--secure")
    echo "${args[@]+"${args[@]}"}"
}

# Handle --list-agents before other argument parsing
if [[ "${1:-}" == "--list-agents" ]]; then
    list_agents
    exit 0
fi

# Handle --test-connection
if [[ "${1:-}" == "--test-connection" ]]; then
    shift
    # Parse optional -- <ch-args>
    TEST_CH_ARGS=()
    if [[ "${1:-}" == "--" ]]; then
        shift
        TEST_CH_ARGS=("$@")
    else
        # Use env vars
        CH_ARGS_FROM_ENV="$(build_ch_args_from_env)"
        [[ -n "$CH_ARGS_FROM_ENV" ]] && read -r -a TEST_CH_ARGS <<<"$CH_ARGS_FROM_ENV"
    fi

    TEST_QUERY="SELECT hostName() AS host, version() AS version, uptime() AS uptime_sec, formatReadableTimeDelta(uptime()) AS uptime"
    if OUTPUT=$(clickhouse-client ${TEST_CH_ARGS[@]+"${TEST_CH_ARGS[@]}"} --format=PrettyCompactNoEscapes --query "$TEST_QUERY" 2>&1); then
        echo "Connection OK"
        echo "$OUTPUT"
        exit 0
    else
        echo "Connection FAILED" >&2
        echo "$OUTPUT" >&2
        echo "" >&2
        echo "Configure connection via environment variables:" >&2
        echo "  export CLICKHOUSE_HOST=<hostname>" >&2
        echo "  export CLICKHOUSE_USER=<username>" >&2
        echo "  export CLICKHOUSE_PASSWORD=<password>" >&2
        echo "  export CLICKHOUSE_SECURE=1  # for TLS" >&2
        echo "" >&2
        echo "Or provide explicit args:" >&2
        echo "  $0 --test-connection -- --host=<host> --user=<user> --password=<pass>" >&2
        exit 1
    fi
fi

AGENT_NAME="${1:-}"
CONTEXT="${2:-}"
if [[ -z "${AGENT_NAME}" ]]; then usage; exit 1; fi
shift 2 || true

LLM_PROVIDER="${CH_ANALYST_LLM_PROVIDER:-codex}"
LLM_MODEL="${CH_ANALYST_LLM_MODEL:-}"
DRY_RUN=0
SINGLE_NODE=0
CLUSTER_NAME=""
MAX_RETRIES="${CH_ANALYST_LLM_RETRIES:-1}"
PROMPT_SIZE_WARN="${CH_ANALYST_PROMPT_SIZE_WARN:-100000}"
DYNAMIC_FALLBACK="${CH_ANALYST_DYNAMIC_FALLBACK:-1}"

# Initialize CH_ARGS from environment variables (can be overridden by explicit args after --)
CH_ARGS_FROM_ENV="$(build_ch_args_from_env)"
CH_ARGS=()
[[ -n "$CH_ARGS_FROM_ENV" ]] && read -r -a CH_ARGS <<<"$CH_ARGS_FROM_ENV"
CH_ARGS_EXPLICIT=0

# Create temp dir early (needed by run_llm for codex)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

	while [[ $# -gt 0 ]]; do
	    case "$1" in
	        --llm-provider)
	            LLM_PROVIDER="${2:-}"; shift 2 || true ;;
	        --llm-model)
	            LLM_MODEL="${2:-}"; shift 2 || true ;;
	        --dry-run)
	            DRY_RUN=1; shift ;;
	        --single-node)
	            SINGLE_NODE=1; shift ;;
	        --cluster-name)
	            CLUSTER_NAME="${2:-}"; shift 2 || true ;;
	        --)
	            shift
	            if [[ $# -gt 0 ]]; then
	                # Explicit args override env-based defaults
                CH_ARGS=("$@")
                CH_ARGS_EXPLICIT=1
            fi
            break
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

AGENT_DIR="$AGENTS_DIR/${AGENT_NAME}"
SQL_FILE="$AGENT_DIR/queries.sql"
PROMPT_FILE="$AGENT_DIR/prompt.md"

# Validate files exist
if [[ ! -f "$SQL_FILE" ]]; then
    echo "Error: SQL file not found: $SQL_FILE" >&2
    exit 1
fi
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: Prompt file not found: $PROMPT_FILE" >&2
    exit 1
fi

run_llm_once() {
    local provider="$1"
    local model="$2"
    local prompt="$3"

    case "$provider" in
        claude)
            # Keep current invocation (known-good).
            claude --print --dangerously-skip-permissions -p "$prompt" 2>/dev/null
            ;;
        codex)
            if ! command -v codex >/dev/null 2>&1; then
                echo "Error: codex CLI not found in PATH" >&2
                return 127
            fi

            local tmp_out
            tmp_out="$TMP_DIR/codex_last_message.txt"
            rm -f "$tmp_out"
            local tmp_err
            tmp_err="$TMP_DIR/codex.stderr.txt"
            rm -f "$tmp_err"

            # Run Codex non-interactively and capture the final assistant message.
            # Use read-only sandbox to reduce surprises; the prompt should already contain all needed context.
            if [[ -n "$model" ]]; then
                if ! printf '%s' "$prompt" | codex -a never -s read-only exec --skip-git-repo-check -m "$model" --output-last-message "$tmp_out" - >/dev/null 2>"$tmp_err"; then
                    echo "Error: codex exec failed" >&2
                    [[ -s "$tmp_err" ]] && sed -n '1,80p' "$tmp_err" >&2
                    return 3
                fi
            else
                if ! printf '%s' "$prompt" | codex -a never -s read-only exec --skip-git-repo-check --output-last-message "$tmp_out" - >/dev/null 2>"$tmp_err"; then
                    echo "Error: codex exec failed" >&2
                    [[ -s "$tmp_err" ]] && sed -n '1,80p' "$tmp_err" >&2
                    return 3
                fi
            fi

            if [[ -s "$tmp_out" ]]; then
                cat "$tmp_out"
                return 0
            fi
            echo "Error: codex exec did not produce an output message" >&2
            return 3
            ;;
        gemini)
            # Stub: call `gemini` with prompt on stdin and no parameters.
            if ! command -v gemini >/dev/null 2>&1; then
                echo "Error: gemini CLI not found in PATH" >&2
                return 127
            fi
            printf '%s' "$prompt" | gemini
            ;;
        *)
            echo "Error: unknown --llm-provider '$provider' (expected: claude|codex|gemini)" >&2
            return 2
            ;;
    esac
}

run_llm() {
    local provider="$1"
    local model="$2"
    local prompt="$3"
    local retries="${4:-$MAX_RETRIES}"
    local attempt=1
    local output=""
    local rc=0

    while [[ $attempt -le $retries ]]; do
        output="$(run_llm_once "$provider" "$model" "$prompt")" && rc=0 || rc=$?
        if [[ $rc -eq 0 && -n "$output" ]]; then
            echo "$output"
            return 0
        fi
        if [[ $attempt -lt $retries ]]; then
            local delay=$((attempt * 2))
            echo "LLM attempt $attempt failed, retrying in ${delay}s..." >&2
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    echo "$output"
    return $rc
}

call_llm() {
    # Capture stdout while preserving non-zero exit status (works under set -e).
    local provider="$1"
    local model="$2"
    local prompt="$3"
    local out
    set +e
    out="$(run_llm "$provider" "$model" "$prompt")"
    local rc=$?
    set -e
    printf '%s' "$out"
    return $rc
}

validate_json() {
    local json="$1"
    command -v jq >/dev/null 2>&1 && echo "$json" | jq -e . >/dev/null 2>&1
}

normalize_llm_output() {
    # Many models wrap JSON in ```json fences; strip those and trim whitespace.
    # This keeps the "JSON-only" contract while being tolerant of common formatting.
    local s="$1"
    s="$(printf '%s\n' "$s" | sed '/^[[:space:]]*```/d')"
    s="$(printf '%s' "$s" | awk 'BEGIN{RS=""; ORS="";} {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0}')"
    printf '%s' "$s"
}

is_cluster_mode_hint() {
    [[ "${CLUSTER_MODE:-0}" == "1" ]]
}

validate_agent_output() {
    local expected_agent="$1"
    local json="$2"

    echo "$json" | jq -e --arg agent "$expected_agent" '
      type == "object"
      and (.agent? == $agent)
      and (.status? | type == "string" and IN("critical","major","moderate","ok"))
      and (.findings? | type == "array")
      and (all(.findings[]?;
            (type == "object")
            and (.severity? | type == "string" and IN("critical","major","moderate","minor"))
            and (.title? | type == "string")
            and (.evidence? | type == "string")
            and (.recommendation? | type == "string")
            and ((.values? | type == "object") or (.values? == null) or (has("values") | not))
          ))
    ' >/dev/null 2>&1
}

detect_cluster_mode() {
    # Heuristic: if system.zookeeper_connection query succeeds and returns any rows, treat as cluster mode.
    # (We do NOT rewrite system.zookeeper_connection itself.)
    local out
    out=$(clickhouse-client ${CH_ARGS[@]+"${CH_ARGS[@]}"} --format=TabSeparated --query "SELECT count() FROM system.zookeeper_connection" 2>/dev/null) || return 1
    [[ "${out:-0}" != "0" ]]
}

detect_cluster_macro_supported() {
    # Returns 0 if clusterAllReplicas('{cluster}', ...) works (macro expands), else non-zero.
    # Keep probe tiny and deterministic.
    clickhouse-client ${CH_ARGS[@]+"${CH_ARGS[@]}"} --format=TabSeparated --query "SELECT count() FROM clusterAllReplicas('{cluster}', system.one)" >/dev/null 2>&1
}

escape_sed_replacement() {
    # Escape replacement string for sed when using '|' delimiter.
    # Escapes: backslash, ampersand, and delimiter.
    printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

substitute_cluster_name() {
    local in_file="$1"
    local out_file="$2"
    local name="$3"

    local escaped
    escaped="$(escape_sed_replacement "$name")"
    sed "s|{cluster}|$escaped|g" "$in_file" >"$out_file"
}

unwrap_cluster_wrappers() {
    local in_file="$1"
    local out_file="$2"

    # Unwrap clusterAllReplicas('<anything>', system.<table>) -> system.<table>
    # This supports both '{cluster}' macro and explicit names (after substitution).
    sed -E "s/clusterAllReplicas\\('[^']*',[[:space:]]*(system\\.[A-Za-z0-9_]+)\\)/\\1/g" "$in_file" >"$out_file"
}

emit_error_json() {
    local error_type="$1"
    local message="$2"
    local raw_chars="${3:-0}"
    cat <<EOF
{"error": "$error_type", "agent": "$AGENT_NAME", "provider": "$LLM_PROVIDER", "message": "$message", "raw_output_chars": $raw_chars}
EOF
}

extract_tables_from_prompt() {
    # Parse a strict line-list under a "## Tables" header in prompt.md.
    # Expected format:
    #   ## Tables
    #   system.query_log
    #   system.part_log
    # Stops at the next "## " header or EOF.
    local prompt_file="$1"
    awk '
      BEGIN { in_tables=0; }
      /^##[[:space:]]+Tables[[:space:]]*$/ { in_tables=1; next; }
      /^##[[:space:]]+/ { if (in_tables==1) exit; }
      {
        if (in_tables==1) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
          if ($0 == "") next;
          if ($0 ~ /^system\.[A-Za-z0-9_]+$/) print $0;
        }
      }
    ' "$prompt_file" | sort -u
}

split_sql_to_files() {
    # Split semicolon-delimited SQL into one statement per file in out_dir.
    # This avoids bash-4+ features like namerefs/readarray and works on macOS bash 3.2.
    local in_file="$1"
    local out_dir="$2"

    mkdir -p "$out_dir"

    awk -v outdir="$out_dir" '
      BEGIN { n=0; buf=""; }
      /^[[:space:]]*--/ { next; }                # drop full-line comments
      /^[[:space:]]*$/  { if (buf == "") next; } # skip leading empty lines
      {
        buf = buf $0 "\n";
        if (index($0, ";") > 0) {
          n++;
          fname = sprintf("%s/%04d.sql", outdir, n);
          printf "%s", buf > fname;
          close(fname);
          buf = "";
        }
      }
      END {
        # flush trailing statement if file does not end with semicolon
        if (buf ~ /[^[:space:]]/) {
          n++;
          fname = sprintf("%s/%04d.sql", outdir, n);
          printf "%s", buf > fname;
          close(fname);
        }
      }
    ' "$in_file"
}

validate_dynamic_sql_file() {
    # Validate LLM-generated SQL for safety and boundedness.
    # Prints a human-readable list of violations to stdout on failure.
    local sql_file="$1"

    local stmts_dir="$TMP_DIR/validate_statements"
    rm -rf "$stmts_dir"
    split_sql_to_files "$sql_file" "$stmts_dir"

    shopt -s nullglob
    local stmt_files=( "$stmts_dir"/*.sql )
    shopt -u nullglob

    if [[ ${#stmt_files[@]} -eq 0 ]]; then
        echo "No SQL statements found."
        return 1
    fi

    local violations=0
    local idx=0
    local stmt
    local first_token
    for f in "${stmt_files[@]}"; do
        idx=$((idx + 1))
        stmt="$(cat "$f")"

        # Forbid dangerous keywords (best-effort string match).
        if printf '%s' "$stmt" | grep -Eqi '\b(INSERT|ALTER|DROP|TRUNCATE|DELETE|UPDATE|CREATE|ATTACH|DETACH|SYSTEM|KILL)\b'; then
            echo "Query $idx: contains forbidden keyword (DDL/DML/system operation)."
            violations=$((violations + 1))
        fi

        # Must start with allowed statement type.
        first_token="$(printf '%s' "$stmt" | awk '{for(i=1;i<=NF;i++){if($i!=""){print tolower($i); exit}}}')"
        case "$first_token" in
            select|with|show|describe|exists) ;;
            *)
                echo "Query $idx: unsupported statement start '$first_token' (allowed: SELECT/WITH/SHOW/DESCRIBE/EXISTS)."
                violations=$((violations + 1))
                ;;
        esac

        # If querying *_log tables, require a time bound.
        if printf '%s' "$stmt" | grep -Eqi '\bsystem\.[A-Za-z0-9_]*_log\b'; then
            if ! printf '%s' "$stmt" | grep -Eqi '\bevent_time\b|\bevent_date\b|now\(\)[[:space:]]*-[[:space:]]*interval'; then
                echo "Query $idx: references *_log but has no obvious time bound (event_time/event_date/now()-interval)."
                violations=$((violations + 1))
            fi
        fi

        # Require LIMIT unless it looks like a pure aggregate.
        if ! printf '%s' "$stmt" | grep -Eqi '\blimit[[:space:]]+[0-9]+'; then
            if ! printf '%s' "$stmt" | grep -Eqi '\b(count|sum|avg|min|max|quantile|median|uniq|uniqexact)\s*\(' ; then
                echo "Query $idx: missing LIMIT (required unless aggregate-only)."
                violations=$((violations + 1))
            fi
        fi
    done

    [[ $violations -eq 0 ]]
}

build_schema_discovery_sql() {
    local tables_text="$1"   # newline-delimited system.<table>
    local out_file="$2"

    : >"$out_file"
    while IFS= read -r t; do
        [[ -z "${t}" ]] && continue
        tbl="${t#system.}"
        {
            echo "-- Schema for $t"
            echo "SELECT name, type FROM system.columns WHERE database = 'system' AND table = '$tbl' ORDER BY name LIMIT 1000;"
            echo
        } >>"$out_file"
    done <<<"$tables_text"
}

run_dynamic_fallback() {
    # Dynamic fallback is a separate pipeline from the static path:
    # - Validation failures: repair loop (re-emit SQL)
    # - Execution failures: proceed with partial results to analysis (no extra generation pass)
    local agent="$1"
    local context="$2"
    local prompt_file="$3"

    local dyn_max_time="60"
    local dyn_max_rows="1000"

    local tables
    tables="$(extract_tables_from_prompt "$prompt_file")"
    if [[ -z "${tables}" ]]; then
        echo "Dynamic fallback skipped: no tables declared under ## Tables in $prompt_file" >&2
        return 1
    fi

    local schema_sql="$TMP_DIR/dynamic.${agent}.schema.sql"
    build_schema_discovery_sql "$tables" "$schema_sql"

    local schema_out
    schema_out="$(run_queries_sequentially "$schema_sql" "$dyn_max_rows" "$dyn_max_time" || true)"

    if [[ -n "$ARTIFACTS_DIR" ]]; then
        cp "$schema_sql" "$ARTIFACTS_DIR/dynamic.${agent}.schema.sql" 2>/dev/null || true
        printf '%s' "$schema_out" >"$ARTIFACTS_DIR/dynamic.${agent}.schema.out" 2>/dev/null || true
    fi

    local cluster_hint
    if [[ "${CLUSTER_MODE:-0}" == "1" ]]; then
        cluster_hint="cluster_mode=1 (use clusterAllReplicas('{cluster}', system.<table>) for system tables)"
    else
        cluster_hint="cluster_mode=0 (query local system.<table>)"
    fi

    local gen_prompt
    gen_prompt="You are generating ClickHouse SQL for the '$agent' diagnostic agent.

Constraints (MUST follow):
- Output ONLY semicolon-delimited SQL (no markdown, no prose).
- Allowed statements: SELECT, WITH ... SELECT, SHOW, DESCRIBE, EXISTS.
- Forbidden: INSERT/ALTER/DELETE/UPDATE/DROP/TRUNCATE/CREATE/ATTACH/DETACH/SYSTEM/KILL.
- Any query that touches system.*_log must include a time bound (event_time/event_date/now()-interval).
- Any non-aggregate query must include LIMIT.
- Avoid SELECT * (schema discovery is already done below).
- Keep output small and efficient.

Topology: $cluster_hint

Tables declared by this agent:
$tables

Discovered schemas (system.columns):
$schema_out

Agent instructions:
$(cat "$prompt_file")
"

    if [[ -n "$ARTIFACTS_DIR" ]]; then
        printf '%s' "$gen_prompt" >"$ARTIFACTS_DIR/dynamic.${agent}.queries.prompt.txt" 2>/dev/null || true
    fi

    local gen_sql_raw gen_sql
    if ! gen_sql_raw="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$gen_prompt")"; then
        echo "Dynamic fallback failed: LLM provider '$LLM_PROVIDER' could not generate SQL." >&2
        return 4
    fi
    gen_sql="$(normalize_llm_output "$gen_sql_raw")"

    local gen_sql_file="$TMP_DIR/dynamic.${agent}.queries.sql"
    printf '%s\n' "$gen_sql" >"$gen_sql_file"

    if [[ -n "$ARTIFACTS_DIR" ]]; then
        printf '%s' "$gen_sql_raw" >"$ARTIFACTS_DIR/dynamic.${agent}.queries.raw.txt" 2>/dev/null || true
        printf '%s\n' "$gen_sql" >"$ARTIFACTS_DIR/dynamic.${agent}.queries.sql" 2>/dev/null || true
    fi

    violations="$(validate_dynamic_sql_file "$gen_sql_file" || true)"
    if [[ -n "$violations" ]]; then
        local repair_prompt
        repair_prompt="Your SQL did not meet the constraints. Fix it and re-emit ONLY semicolon-delimited SQL (no markdown, no prose).

Violations:
$violations

Topology: $cluster_hint

Schemas:
$schema_out
"
        local repaired_raw repaired
        if ! repaired_raw="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$repair_prompt")"; then
            echo "Dynamic fallback failed: LLM provider '$LLM_PROVIDER' could not repair SQL." >&2
            return 4
        fi
        repaired="$(normalize_llm_output "$repaired_raw")"
        printf '%s\n' "$repaired" >"$gen_sql_file"
        if [[ -n "$ARTIFACTS_DIR" ]]; then
            printf '%s' "$repair_prompt" >"$ARTIFACTS_DIR/dynamic.${agent}.queries.repair.prompt.txt" 2>/dev/null || true
            printf '%s' "$repaired_raw" >"$ARTIFACTS_DIR/dynamic.${agent}.queries.repair.raw.txt" 2>/dev/null || true
            printf '%s\n' "$repaired" >"$ARTIFACTS_DIR/dynamic.${agent}.queries.repair.sql" 2>/dev/null || true
        fi
        if ! validate_dynamic_sql_file "$gen_sql_file" >/dev/null 2>&1; then
            echo "Dynamic fallback failed: generated SQL still invalid after repair." >&2
            return 2
        fi
    fi

    local dyn_out
    dyn_out="$(run_queries_sequentially "$gen_sql_file" "$dyn_max_rows" "$dyn_max_time" || true)"
    if [[ -n "$ARTIFACTS_DIR" ]]; then
        printf '%s' "$dyn_out" >"$ARTIFACTS_DIR/dynamic.${agent}.queries.out" 2>/dev/null || true
    fi

    local analysis_prompt
    analysis_prompt="$(cat "$prompt_file")

---
## Runtime Context
- Problem: $context
- Agent: $agent
- Time: $(date -Iseconds)
- Dynamic fallback: enabled (static SQL had errors)
- Topology: $cluster_hint

## Discovered Schemas (system.columns)
$schema_out

## Query Results (dynamic SQL, JSONCompact)
$dyn_out

---
Return ONLY valid JSON findings for this agent."

    if [[ -n "$ARTIFACTS_DIR" ]]; then
        printf '%s' "$analysis_prompt" >"$ARTIFACTS_DIR/dynamic.${agent}.analysis.prompt.txt" 2>/dev/null || true
    fi

    if ! RAW_OUTPUT="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$analysis_prompt")"; then
        echo "Dynamic fallback failed: LLM provider '$LLM_PROVIDER' could not analyze results." >&2
        return 4
    fi
    RAW_OUTPUT_CLEAN="$(normalize_llm_output "$RAW_OUTPUT")"
    if [[ -n "$ARTIFACTS_DIR" ]]; then
        printf '%s' "$RAW_OUTPUT" >"$ARTIFACTS_DIR/dynamic.${agent}.analysis.raw.txt" 2>/dev/null || true
        printf '%s' "$RAW_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/dynamic.${agent}.analysis.cleaned.txt" 2>/dev/null || true
    fi
    if validate_json "$RAW_OUTPUT_CLEAN" && validate_agent_output "$agent" "$RAW_OUTPUT_CLEAN"; then
        echo "$RAW_OUTPUT_CLEAN"
        [[ -n "$ARTIFACTS_DIR" ]] && printf '%s' "$RAW_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/output.json" 2>/dev/null || true
        return 0
    fi

    local repair_json_prompt
    repair_json_prompt="You produced invalid JSON. Return ONLY valid JSON matching the required output format. No prose.

Agent: $agent
Problem: $context

Invalid output:
$RAW_OUTPUT"
    if ! REPAIRED_OUTPUT="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$repair_json_prompt")"; then
        echo "Dynamic fallback failed: LLM provider '$LLM_PROVIDER' could not repair JSON." >&2
        return 4
    fi
    REPAIRED_OUTPUT_CLEAN="$(normalize_llm_output "$REPAIRED_OUTPUT")"
    if [[ -n "$ARTIFACTS_DIR" ]]; then
        printf '%s' "$repair_json_prompt" >"$ARTIFACTS_DIR/dynamic.${agent}.analysis.repair.prompt.txt" 2>/dev/null || true
        printf '%s' "$REPAIRED_OUTPUT" >"$ARTIFACTS_DIR/dynamic.${agent}.analysis.repair.raw.txt" 2>/dev/null || true
        printf '%s' "$REPAIRED_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/dynamic.${agent}.analysis.repair.cleaned.txt" 2>/dev/null || true
    fi
    if validate_json "$REPAIRED_OUTPUT_CLEAN" && validate_agent_output "$agent" "$REPAIRED_OUTPUT_CLEAN"; then
        echo "$REPAIRED_OUTPUT_CLEAN"
        [[ -n "$ARTIFACTS_DIR" ]] && printf '%s' "$REPAIRED_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/output.json" 2>/dev/null || true
        return 0
    fi

    echo "Dynamic fallback failed: invalid JSON after repair attempt." >&2
    return 3
}

run_queries_sequentially() {
    local file="$1"
    local max_result_rows="${2:-}"
    local max_execution_time="${3:-}"
    local stmts_dir="$TMP_DIR/statements"
    split_sql_to_files "$file" "$stmts_dir"

    local results=""
    local i=0
    local errors=0

    shopt -s nullglob
    local stmt_files=( "$stmts_dir"/*.sql )
    shopt -u nullglob

    if [[ ${#stmt_files[@]} -eq 0 ]]; then
        RUN_QUERY_ERRORS=0
        echo ""
        return 0
    fi

    local stmt
    local stmt_file
    for stmt_file in "${stmt_files[@]}"; do
        i=$((i + 1))
        local out_file err_file
        out_file="$TMP_DIR/query_${i}.out"
        err_file="$TMP_DIR/query_${i}.err"

        local -a timeout_args=()
        if [[ -n "${max_execution_time}" ]] && [[ "${max_execution_time}" != "0" ]]; then
            timeout_args+=( "--max_execution_time=${max_execution_time}" )
        fi
        if [[ -n "${max_result_rows}" ]] && [[ "${max_result_rows}" != "0" ]]; then
            timeout_args+=( "--max_result_rows=${max_result_rows}" )
        fi

        stmt="$(cat "$stmt_file")"
        if clickhouse-client ${CH_ARGS[@]+"${CH_ARGS[@]}"} ${timeout_args[@]+"${timeout_args[@]}"} --format=JSONCompact --query "$stmt" >"$out_file" 2>"$err_file"; then
            results+=$'### Query '"$i"$'\n'
            results+="$(cat "$out_file")"$'\n\n'
        else
            errors=$((errors + 1))
            results+=$'### Query '"$i"$' (ERROR)\n'
            results+="$(cat "$err_file")"$'\n\n'
        fi
    done

    RUN_QUERY_ERRORS=$errors
    echo "$results"
    return $errors
}

# Step 1: Execute SQL queries (cluster-aware rewrite + sequential execution so late failures don't drop earlier results)
RUNS_ROOT="$SKILL_ROOT/runs"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-${AGENT_NAME}"
ARTIFACTS_DIR=""
if [[ "${CH_ANALYST_KEEP_ARTIFACTS:-0}" == "1" ]]; then
    ARTIFACTS_DIR="$RUNS_ROOT/$RUN_ID"
    mkdir -p "$ARTIFACTS_DIR"
fi

# Cluster behavior (default ON for queries that use clusterAllReplicas('{cluster}', ...)):
# - If SINGLE_NODE=1 -> unwrap clusterAllReplicas(...) to local system.<table>
# - Else if zookeeper inactive -> unwrap
# - Else if macro missing and no --cluster-name -> unwrap (choice B)
# - Else if --cluster-name provided -> substitute {cluster} with provided name (keep wrappers)
ZOOKEEPER_ACTIVE=0
if detect_cluster_mode; then
    ZOOKEEPER_ACTIVE=1
fi

MACRO_OK=0
if [[ "$ZOOKEEPER_ACTIVE" == "1" ]] && [[ "$SINGLE_NODE" == "0" ]] && [[ -z "$CLUSTER_NAME" ]]; then
    if detect_cluster_macro_supported; then
        MACRO_OK=1
    fi
fi

SQL_TO_RUN="$SQL_FILE"
SQL_FINAL="$TMP_DIR/queries.final.sql"
SQL_INTERMEDIATE="$TMP_DIR/queries.intermediate.sql"

if [[ -n "$CLUSTER_NAME" ]]; then
    substitute_cluster_name "$SQL_TO_RUN" "$SQL_INTERMEDIATE" "$CLUSTER_NAME"
    SQL_TO_RUN="$SQL_INTERMEDIATE"
fi

CLUSTER_MODE=0
if [[ "$SINGLE_NODE" == "1" ]] || [[ "$ZOOKEEPER_ACTIVE" == "0" ]]; then
    unwrap_cluster_wrappers "$SQL_TO_RUN" "$SQL_FINAL"
    SQL_TO_RUN="$SQL_FINAL"
elif [[ -z "$CLUSTER_NAME" ]] && [[ "$MACRO_OK" == "0" ]]; then
    # ZK is active but {cluster} macro isn't configured; run as single-node by unwrapping.
    unwrap_cluster_wrappers "$SQL_TO_RUN" "$SQL_FINAL"
    SQL_TO_RUN="$SQL_FINAL"
else
    # Cluster wrappers usable (either macro works, or an explicit cluster name was provided).
    CLUSTER_MODE=1
    cp "$SQL_TO_RUN" "$SQL_FINAL"
    SQL_TO_RUN="$SQL_FINAL"
fi

if [[ -n "$ARTIFACTS_DIR" ]]; then
    cp "$SQL_FILE" "$ARTIFACTS_DIR/queries.original.sql" 2>/dev/null || true
    cp "$SQL_TO_RUN" "$ARTIFACTS_DIR/queries.final.sql" 2>/dev/null || true
    {
        echo "agent=$AGENT_NAME"
        echo "llm_provider=$LLM_PROVIDER"
        echo "llm_model=${LLM_MODEL:-}"
        echo "cluster_mode=$CLUSTER_MODE"
        echo "single_node=$SINGLE_NODE"
        echo "zookeeper_active=$ZOOKEEPER_ACTIVE"
        echo "macro_ok=$MACRO_OK"
        echo "cluster_name=${CLUSTER_NAME:-}"
        echo "dry_run=$DRY_RUN"
        echo "query_timeout_sec=${CH_ANALYST_QUERY_TIMEOUT_SEC:-}"
        echo "clickhouse_args=${CH_ARGS[*]-}"
        echo "clickhouse_args_source=$( [[ $CH_ARGS_EXPLICIT -eq 1 ]] && echo "explicit" || echo "env" )"
        echo "time=$(date -Iseconds)"
    } >"$ARTIFACTS_DIR/meta.txt" 2>/dev/null || true
fi

STATIC_MAX_TIME="${CH_ANALYST_QUERY_TIMEOUT_SEC:-60}"
QUERY_RESULTS="$(run_queries_sequentially "$SQL_TO_RUN" "" "$STATIC_MAX_TIME" || true)"
STATIC_QUERY_ERRORS="${RUN_QUERY_ERRORS:-0}"
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$QUERY_RESULTS" >"$ARTIFACTS_DIR/query_results.txt" 2>/dev/null || true
fi

# Dry-run mode: output query results and exit
if [[ "$DRY_RUN" == "1" ]]; then
    echo "=== DRY RUN: Query Results (no LLM) ===" >&2
    echo "$QUERY_RESULTS"
    exit 0
fi

# Dynamic fallback (2-pass) on static SQL errors (enabled by default)
if [[ "$DYNAMIC_FALLBACK" == "1" ]] && [[ "${STATIC_QUERY_ERRORS}" != "0" ]]; then
    echo "Static SQL had ${STATIC_QUERY_ERRORS} error(s); attempting dynamic fallback for agent '$AGENT_NAME'." >&2
    if run_dynamic_fallback "$AGENT_NAME" "$CONTEXT" "$PROMPT_FILE"; then
        exit 0
    fi
    echo "Dynamic fallback did not succeed; continuing with static results." >&2
fi

# Step 2: Build prompt with query results
ANALYSIS_PROMPT="$(cat "$PROMPT_FILE")

---
## Runtime Context
- Problem: $CONTEXT
- Agent: $AGENT_NAME
- Time: $(date -Iseconds)

## Query Results (JSONCompact)
$QUERY_RESULTS

---
Analyze the query results above and return JSON findings."
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$ANALYSIS_PROMPT" >"$ARTIFACTS_DIR/prompt.txt" 2>/dev/null || true
fi

# Prompt size warning
PROMPT_SIZE=${#ANALYSIS_PROMPT}
if [[ $PROMPT_SIZE -gt $PROMPT_SIZE_WARN ]]; then
    echo "Warning: prompt size ($PROMPT_SIZE chars) may exceed LLM context limit" >&2
fi

# Step 3: Run LLM + validate/repair JSON once
if ! RAW_OUTPUT="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$ANALYSIS_PROMPT")"; then
    emit_error_json "llm_failed" "LLM provider '$LLM_PROVIDER' failed to run" "0" >&2
    exit 4
fi
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$RAW_OUTPUT" >"$ARTIFACTS_DIR/llm_output.raw.txt" 2>/dev/null || true
fi
RAW_OUTPUT_CLEAN="$(normalize_llm_output "$RAW_OUTPUT")"
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$RAW_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/llm_output.cleaned.txt" 2>/dev/null || true
fi
if validate_json "$RAW_OUTPUT_CLEAN" && validate_agent_output "$AGENT_NAME" "$RAW_OUTPUT_CLEAN"; then
    echo "$RAW_OUTPUT_CLEAN"
    [[ -n "$ARTIFACTS_DIR" ]] && printf '%s' "$RAW_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/output.json" 2>/dev/null || true
    exit 0
fi

REPAIR_PROMPT="You produced invalid JSON. Return ONLY valid JSON matching the required output format. No prose.

Agent: $AGENT_NAME
Problem: $CONTEXT

Invalid output:
$RAW_OUTPUT"

if ! REPAIRED_OUTPUT="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$REPAIR_PROMPT")"; then
    emit_error_json "llm_failed" "LLM provider '$LLM_PROVIDER' failed to run (repair pass)" "0" >&2
    exit 4
fi
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$REPAIRED_OUTPUT" >"$ARTIFACTS_DIR/llm_output.repaired.txt" 2>/dev/null || true
fi
REPAIRED_OUTPUT_CLEAN="$(normalize_llm_output "$REPAIRED_OUTPUT")"
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$REPAIRED_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/llm_output.repaired.cleaned.txt" 2>/dev/null || true
fi
if validate_json "$REPAIRED_OUTPUT_CLEAN" && validate_agent_output "$AGENT_NAME" "$REPAIRED_OUTPUT_CLEAN"; then
    echo "$REPAIRED_OUTPUT_CLEAN"
    [[ -n "$ARTIFACTS_DIR" ]] && printf '%s' "$REPAIRED_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/output.json" 2>/dev/null || true
    exit 0
fi

RAW_CHARS=${#RAW_OUTPUT}
emit_error_json "invalid_json" "LLM output failed validation after repair attempt" "$RAW_CHARS" >&2
echo "$RAW_OUTPUT" >&2
exit 3
