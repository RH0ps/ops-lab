#!/usr/bin/env bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"

: "${LOG_FILE:?LOG_FILE is not set}"

log_info() {
    echo "[$(date '+%F %T')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%F %T')] [WARN] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%F %T')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

