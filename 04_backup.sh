#!/bin/bash
set -euo pipefail

# =========================
# 設定
# =========================

TARGET_FILE="/home/r.h/docker/index.html"
BACKUP_DIR="/home/r.h/docker/backup"
LOG_FILE="/home/r.h/docker/backup/backup.log"

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

trap 'log "ERROR: script failed (exit code=$?, line=$LINENO)"; notify "❌ Backup failed"' ERR

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

log "Backup success: $BACKUP_FILE"
notify "📦 Backup success: $BACKUP_FILE ($(date '+%Y-%m-%d %H:%M:%S'))"