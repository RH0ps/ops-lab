#!/usr/bin/env bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="$PROJECT_ROOT/logs/test.log"

source "$PROJECT_ROOT/lib/log.sh"

log_info "Application started"
log_warn "Disk usage is high"
log_error "Backup failed"
