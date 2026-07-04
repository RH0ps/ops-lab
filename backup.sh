#!/bin/bash
set -euo pipefail

# =========================
# 設定
# =========================

TARGET_FILE="/home/r.h/docker/index.html"
BACKUP_DIR="/home/r.h/backup"
LOG_FILE="/home/r.h/docker/logs/backup.log"
METRIC_FILE="/home/r.h/docker/metrics/backup.prom"
SUCCESS_FILE="/home/r.h/docker/state/backup_success_count"
FAILURE_FILE="/home/r.h/docker/state/backup_failure_count"

if [ -f "/home/r.h/docker/.env" ]; then
    source "/home/r.h/docker/.env"
fi

WEBHOOK_URL="${WEBHOOK_URL:?WEBHOOK_URL is required}"

DRY_RUN="${DRY_RUN:-false}"

# 世代管理数
KEEP_BACKUPS=10

# =========================
# ログ関数
# =========================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# =========================
# 通知関数
# =========================

notify() {
    local message="$1"

    if ! curl -s -X POST \
        -H "Content-type: application/json" \
        --data "$(jq -n --arg text "$message" '{text:$text}')" \
        "$WEBHOOK_URL" >/dev/null 2>>"$LOG_FILE"; then
        log "WARN: Slack notification failed"
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

log "ERROR: script failed (exit code=$EXIT_CODE, line=$LINENO)"
notify "❌ Backup failed"
' ERR

# =========================
# DRY RUN
# =========================

if [ "$DRY_RUN" = "true" ]; then
    log "DRY_RUN enabled: no changes will be made"
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
    log "ERROR: target file not found: $TARGET_FILE"
    notify "❌ Backup failed: file not found"
    exit 1
fi

if [ ! -s "$TARGET_FILE" ]; then
    log "ERROR: target file is empty"
    notify "❌ Backup failed: empty file"
    exit 1
fi

# =========================
# バックアップ実行
# =========================

cp -a "$TARGET_FILE" "$BACKUP_DIR/$BACKUP_FILE"
log "Backup created: $BACKUP_FILE"

if [ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
    log "ERROR: backup file was not created"
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
    log "Rotation completed (kept $KEEP_BACKUPS backups)"
else
    log "Rotation skipped (not enough files)"
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

log "Backup success: $BACKUP_FILE"
notify "📦 Backup success: $BACKUP_FILE ($(date '+%Y-%m-%d %H:%M:%S'))"

exit 0

