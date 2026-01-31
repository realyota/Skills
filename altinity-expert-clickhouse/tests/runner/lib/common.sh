#!/bin/bash
# Common functions for skill tests

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_DIR="$(dirname "$LIB_DIR")"
TESTS_DIR="$(dirname "$RUNNER_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

compose_client_available() {
    [[ -f "$TESTS_DIR/docker-compose.yml" ]] || return 1
    command -v docker >/dev/null 2>&1 || return 1
    docker compose version >/dev/null 2>&1 || return 1
    return 0
}

build_client_cmd() {
    # Prefer dockerized clickhouse-client when the test suite is configured to use Docker,
    # even if a host clickhouse-client exists (host client version skew can cause
    # connection resets against newer servers).
    case "${USE_DOCKER:-0}" in
        1|true|yes|on)
            if compose_client_available; then
                CLIENT_CMD=(docker compose -f "$TESTS_DIR/docker-compose.yml" exec -T clickhouse clickhouse-client)
                return 0
            fi
            ;;
    esac

    if command -v clickhouse-client >/dev/null 2>&1; then
        CLIENT_CMD=(clickhouse-client)
        return 0
    fi

    if compose_client_available; then
        CLIENT_CMD=(docker compose -f "$TESTS_DIR/docker-compose.yml" exec -T clickhouse clickhouse-client)
        return 0
    fi

    return 1
}

# Build clickhouse-client arguments from environment variables
build_client_args() {
    CLIENT_ARGS=(
        --host "${CLICKHOUSE_HOST:-arm}"
        --port "${CLICKHOUSE_PORT:-9000}"
        --user "${CLICKHOUSE_USER:-default}"
    )

    if [[ -n "${CLICKHOUSE_PASSWORD:-}" ]]; then
        CLIENT_ARGS+=(--password "${CLICKHOUSE_PASSWORD}")
    fi

    case "${CLICKHOUSE_SECURE:-false}" in
        true|1|yes|on)
            CLIENT_ARGS+=(--secure)
            ;;
    esac
}

# Run a single query
run_query() {
    local query="$1"
    build_client_cmd
    build_client_args
    "${CLIENT_CMD[@]}" "${CLIENT_ARGS[@]}" --query "$query"
}

# Run a SQL script file
run_script() {
    local script="$1"
    build_client_cmd
    build_client_args
    "${CLIENT_CMD[@]}" "${CLIENT_ARGS[@]}" --multiquery < "$script"
}

# Run a SQL script with database context
run_script_in_db() {
    local script="$1"
    local db="$2"
    build_client_cmd
    build_client_args
    "${CLIENT_CMD[@]}" "${CLIENT_ARGS[@]}" --database "$db" --multiquery < "$script"
}

# Run a SQL script with database context, but continue on errors
run_script_in_db_ignore_errors() {
    local script="$1"
    local db="$2"
    build_client_cmd
    build_client_args
    "${CLIENT_CMD[@]}" "${CLIENT_ARGS[@]}" --database "$db" --multiquery --ignore-error < "$script"
}

# Validate environment variables are set
validate_env() {
    if ! build_client_cmd; then
        log_error "No ClickHouse client available"
        log_error "Install clickhouse-client or run from tests/ with docker compose available (uses `docker compose exec` fallback)."
        return 1
    fi

    if [[ -z "${CLICKHOUSE_HOST:-}" ]]; then
        log_warn "CLICKHOUSE_HOST is not set; defaulting to '${CLICKHOUSE_HOST:-arm}'"
        log_warn "If this is not your ClickHouse, export CLICKHOUSE_HOST=<host> (and optionally CLICKHOUSE_PORT/USER/PASSWORD/SECURE)."
    fi

    if [[ -z "${CLICKHOUSE_USER:-}" ]]; then
        log_warn "CLICKHOUSE_USER is not set, using 'default'"
    fi
}

# Validate connection to ClickHouse
validate_connection() {
    log_info "Validating ClickHouse connection..."

    local result
    if result=$(run_query "SELECT hostName(), version()" 2>&1); then
        log_success "Connected to ClickHouse: $result"
        return 0
    else
        log_error "Failed to connect to ClickHouse"
        log_error "$result"
        return 1
    fi
}

# Create database if not exists
create_database() {
    local db="$1"
    log_info "Creating database: $db"
    run_query "CREATE DATABASE IF NOT EXISTS \`$db\`"
    log_success "Database ready: $db"
}

# Drop database if exists
drop_database() {
    local db="$1"
    log_info "Dropping database: $db"
    run_query "DROP DATABASE IF EXISTS \`$db\`"
    log_success "Database dropped: $db"
}

# Get database name from skill path
get_db_name() {
    local skill="$1"
    # Convert path to database name: chaining/memory-to-merges -> test-memory-to-merges
    if [[ "$skill" == chaining/* ]]; then
        echo "test-$(basename "$skill")"
    else
        basename "$skill"
    fi
}

# If script is run directly (not sourced), execute validate_env
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        validate_env)
            validate_env
            ;;
        validate_connection)
            validate_env
            validate_connection
            ;;
        *)
            echo "Usage: $0 {validate_env|validate_connection}"
            exit 1
            ;;
    esac
fi
