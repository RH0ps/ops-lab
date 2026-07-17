#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"

# shellcheck source=./lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"

LOG_FILE="$LOG_DIR/rotate.log"

KEEP_DAYS="${KEEP_DAYS:-7}"

log_info "Start log rotation"

deleted=0

TMP_FILE=$(mktemp) || {
    log_error "Failed to create temporary file"
    exit 1
}

trap 'rm -f "$TMP_FILE"' EXIT


find "$LOG_DIR" \
    -type f \
    -name "*.log" \
    ! -name "rotate.log" \
    ! -name "cron.log" \
    -mtime +"$KEEP_DAYS" \
    -print0 > "$TMP_FILE"


while IFS= read -r -d '' file; do

    if rm -f "$file"; then
        log_info "Deleted: $file"
        ((++deleted))
    else
        log_error "Failed to delete: $file"
    fi

done < "$TMP_FILE"


if [[ "$deleted" -eq 0 ]]; then
    log_info "No old log files found"
else
    log_info "Deleted $deleted old log file(s)"
fi


log_info "Finished log rotation"

exit 0
