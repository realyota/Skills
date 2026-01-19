#!/bin/bash
set -euo pipefail

REPORT_FILE="$1"
HOSTNAME_RAW="${2:-}"
HOST_HASH="${3:-}"

if [[ -z "$REPORT_FILE" || ! -f "$REPORT_FILE" ]]; then
    echo "Usage: $0 <report_file> [hostname] [host_hash]" >&2
    exit 1
fi

if [[ "${AUDIT_REDACT:-0}" != "1" ]]; then
    exit 0
fi

TMP_FILE="${REPORT_FILE}.redacted.tmp"
cp "$REPORT_FILE" "$TMP_FILE"

if [[ -n "$HOSTNAME_RAW" && -n "$HOST_HASH" ]]; then
    perl -pi -e "s/\Q${HOSTNAME_RAW}\E/host-${HOST_HASH}/g" "$TMP_FILE"
fi

# Redact IPv4 addresses
perl -pi -e 's/\b(?:\d{1,3}\.){3}\d{1,3}\b/<ip-redacted>/g' "$TMP_FILE"

# Redact likely filesystem paths
perl -pi -e 's#/(?:[^\s`"]+/)+[^\s`"]+#<path-redacted>#g' "$TMP_FILE"

mv "$TMP_FILE" "$REPORT_FILE"
