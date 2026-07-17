#!/bin/bash
set -euo pipefail

# =========================
# 設定
# =========================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_FILE="$PROJECT_ROOT/index.html"
BACKUP_DIR="$PROJECT_ROOT/backup"
LOG_FILE="$PROJECT_ROOT/logs/backup.log"

# shellcheck source=./lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"

METRIC_FILE="$PROJECT_ROOT/metrics/backup.prom"
SUCCESS_FILE="$PROJECT_ROOT/state/backup_success_count"
FAILURE_FILE="$PROJECT_ROOT/state/backup_failure_count"

if [ -f "$PROJECT_ROOT/.env" ]; then
    # shellcheck source=./.env
    source "$PROJECT_ROOT/.env"
fi

WEBHOOK_URL="${WEBHOOK_URL:-}"
SLACK_ENABLED=0
[[ -n "$WEBHOOK_URL" ]] && SLACK_ENABLED=1

DRY_RUN="${DRY_RUN:-false}"

# 世代管理数
KEEP_BACKUPS=10

# =========================
# 通知関数
# =========================

notify() {
    local message="$1"

    [[ "$SLACK_ENABLED" -eq 0 ]] && return 0

    if ! curl -s -X POST \
        -H "Content-type: application/json" \
        --data "$(jq -n --arg text "$message" '{text:$text}')" \
        "$WEBHOOK_URL" >/dev/null 2>>"$LOG_FILE"; then
        log_warn "Slack notification failed"
    fi
}

# =========================
# trap（エラー検知）
# =========================

trap '
EXIT_CODE=$?

FAILURE_COUNT=$(cat "$FAILURE_FILE")
FAILURE_COUNT=$((FAILURE_COUNT + 1))
echo "$FAILURE_COUNT" > "$FAILURE_FILE"

log_error "Script failed (exit code=$EXIT_CODE, line=$LINENO)"
notify "❌ Backup failed"
' ERR

# =========================
# DRY RUN
# =========================

if [ "$DRY_RUN" = "true" ]; then
    log_info "DRY_RUN enabled: no changes will be made"
    exit 0
fi

# =========================
# 準備
# =========================

mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$METRIC_FILE")"
mkdir -p "$(dirname "$SUCCESS_FILE")"

[ -f "$SUCCESS_FILE" ] || echo 0 > "$SUCCESS_FILE"
[ -f "$FAILURE_FILE" ] || echo 0 > "$FAILURE_FILE"

DATE=$(date "+%Y%m%d_%H%M%S")
BACKUP_FILE="index_${DATE}.html"

# =========================
# チェック
# =========================

if [ ! -f "$TARGET_FILE" ]; then
    log_error "Target file not found: $TARGET_FILE"
    notify "❌ Backup failed: file not found"
    exit 1
fi

if [ ! -s "$TARGET_FILE" ]; then
    log_error "Target file is empty"
    notify "❌ Backup failed: empty file"
    exit 1
fi

# =========================
# バックアップ実行
# =========================

cp -a "$TARGET_FILE" "$BACKUP_DIR/$BACKUP_FILE"
log_info "Backup created: $BACKUP_FILE"

if [ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
    log_error "Backup file was not created"
    notify "❌ Backup failed: file creation error"
    exit 1
fi

# =========================
# 世代管理
# =========================

mapfile -t files < <(ls -1t "$BACKUP_DIR"/index_*.html 2>/dev/null)

if [ "${#files[@]}" -gt "$KEEP_BACKUPS" ]; then
    for ((i=KEEP_BACKUPS; i<${#files[@]}; i++)); do
        rm -f "${files[$i]}"
    done
    log_info "Rotation completed (kept $KEEP_BACKUPS backups)"
else
    log_info "Rotation skipped (not enough files)"
fi

# =========================
# 成功通知
# =========================

SUCCESS_COUNT=$(cat "$SUCCESS_FILE")
SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
echo "$SUCCESS_COUNT" > "$SUCCESS_FILE"

FAILURE_COUNT=$(cat "$FAILURE_FILE")

{
    echo "backup_success_total $SUCCESS_COUNT"
    echo "backup_failure_total $FAILURE_COUNT"
    echo "backup_last_timestamp $(date +%s)"
} > "$METRIC_FILE"

log_info "Backup success: $BACKUP_FILE"
notify "📦 Backup success: $BACKUP_FILE ($(date '+%Y-%m-%d %H:%M:%S'))"

exit 0

