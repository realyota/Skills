#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS_DIR="$ROOT_DIR/altinity-expert-clickhouse/tests"
PROMPTS_DIR="$ROOT_DIR/automations/prompts"
REPORTS_DIR="$ROOT_DIR/automations/reports"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <focus-skill-name>" >&2
    exit 1
fi

FOCUS_SKILL="$1"
LLM_PROVIDER="${LLM_PROVIDER:-codex}"
CODEX_MODEL="${CODEX_MODEL:-}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
GEMINI_MODEL="${GEMINI_MODEL:-}"

# Source ClickHouse helpers
# shellcheck source=/dev/null
source "$TESTS_DIR/runner/lib/common.sh"

validate_env
validate_connection

HOSTNAME_RAW=$(run_query "select hostName()")
HOST_HASH=$(printf '%s' "$HOSTNAME_RAW" | shasum -a 256 | awk '{print substr($1,1,12)}')
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$REPORTS_DIR"
REPORT="$REPORTS_DIR/host-${HOST_HASH}-${TIMESTAMP}-${LLM_PROVIDER}.md"
LLM_LOG="$REPORTS_DIR/host-${HOST_HASH}-${TIMESTAMP}-${LLM_PROVIDER}.log"

export AUDIT_HOSTNAME="$HOSTNAME_RAW"
export AUDIT_HOST_HASH="$HOST_HASH"
export AUDIT_FOCUS_SKILL="$FOCUS_SKILL"

PROMPT_FILE="$PROMPTS_DIR/focus.md"

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Prompt file not found: $PROMPT_FILE" >&2
    exit 1
fi

PROMPT=$(cat "$PROMPT_FILE")
PROMPT=$(echo "$PROMPT" | envsubst)

case "$LLM_PROVIDER" in
    codex)
        CODEX_ARGS=(
            exec
            --dangerously-bypass-approvals-and-sandbox
            --skip-git-repo-check
            -C "$ROOT_DIR"
            -o "$REPORT"
        )
        if [[ -n "$CODEX_MODEL" ]]; then
            CODEX_ARGS+=( -m "$CODEX_MODEL" )
        fi
        if echo "$PROMPT" | codex "${CODEX_ARGS[@]}" > "$LLM_LOG" 2>&1; then
            :
        else
            echo "Codex focus audit failed" >&2
            cat "$LLM_LOG" >&2
            exit 1
        fi
        ;;
    claude)
        CLAUDE_ARGS=(
            -p
            --dangerously-skip-permissions
            --allowedTools "Bash,Read,Glob,Grep"
        )
        if [[ -n "$CLAUDE_MODEL" ]]; then
            CLAUDE_ARGS+=(--model "$CLAUDE_MODEL")
        fi
        if (cd "$ROOT_DIR" && echo "$PROMPT" | claude "${CLAUDE_ARGS[@]}" > "$REPORT" 2> "$LLM_LOG"); then
            :
        else
            echo "Claude focus audit failed" >&2
            cat "$LLM_LOG" >&2
            exit 1
        fi
        ;;
    gemini)
        echo "Gemini provider stub: not enabled yet" >&2
        exit 1
        ;;
    *)
        echo "Unknown LLM_PROVIDER: $LLM_PROVIDER" >&2
        exit 1
        ;;
esac

"$SCRIPT_DIR/redact-report.sh" "$REPORT" "$HOSTNAME_RAW" "$HOST_HASH"

echo "Focus report: $REPORT"
