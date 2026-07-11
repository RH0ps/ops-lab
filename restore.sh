#!/bin/bash

set -euo pipefail

# =========================
# 設定
# =========================

TARGET_FILE="/home/r.h/docker/index.html"
BACKUP_DIR="/home/r.h/backup"
LOG_FILE="/home/r.h/docker/logs/restore.log"
ROLLBACK_FILE="/home/r.h/docker/index.html.rollback"
HISTORY_FILE="/home/r.h/docker/logs/restore_history.log"
COUNT_FILE="/home/r.h/docker/state/restore_count"

SNAPSHOT_DIR="/home/r.h/docker/backup_snapshots"
JSON_LOG="/home/r.h/docker/logs/restore_history.json"

LOCK_FILE="/tmp/restore.lock"
MAX_AGE_SEC=$((60*60*24*7))  # 7日

if [ -f "/home/r.h/docker/.env" ]; then
    source "/home/r.h/docker/.env"
fi

WEBHOOK_URL="${WEBHOOK_URL:?WEBHOOK_URL is required}"

FORCE="${FORCE:-false}"

# =========================
# ロック（多重実行防止）
# =========================

if [ -f "$LOCK_FILE" ]; then
    echo "Restore already running"
    exit 1
fi

touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

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

    curl -s -X POST \
        -H "Content-type: application/json" \
        --data "$(jq -n --arg text "$message" '{text:$text}')" \
        "$WEBHOOK_URL" >/dev/null
}

# =========================
# dry-run
# =========================

if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "[DRY RUN] restore disabled"
    exit 0
fi

# =========================
# 準備
# =========================

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$SNAPSHOT_DIR"

# =========================
# バックアップ一覧
# =========================

echo "===== backup list ====="
ls -1t "$BACKUP_DIR"/index_*.html 2>/dev/null || true
echo "======================="

# =========================
# 最新 or 指定バックアップ
# =========================

TARGET_BACKUP="${1:-}"

if [ -n "$TARGET_BACKUP" ]; then
    if [[ "$TARGET_BACKUP" == /* ]]; then
        LATEST="$TARGET_BACKUP"
    else
        LATEST="$BACKUP_DIR/$TARGET_BACKUP"
    fi
else
    LATEST=$(ls -1 "$BACKUP_DIR"/index_*.html 2>/dev/null | sort | tail -1)
fi

# =========================
# 古すぎるバックアップ拒否
# （ファイル名の日時で判定）
# =========================

if [ -f "$LATEST" ]; then
    FILE_NAME=$(basename "$LATEST")

    # index_20260706_092702.html → 20260706092702
    FILE_DATE=$(echo "$FILE_NAME" | sed -E 's/index_([0-9]{8})_([0-9]{6})\.html/\1\2/')

    BACKUP_TIME=$(date -d \
        "${FILE_DATE:0:4}-${FILE_DATE:4:2}-${FILE_DATE:6:2} ${FILE_DATE:8:2}:${FILE_DATE:10:2}:${FILE_DATE:12:2}" \
        +%s)

    AGE=$(( $(date +%s) - BACKUP_TIME ))

    if [ "$AGE" -gt "$MAX_AGE_SEC" ]; then
        log "Backup too old: $LATEST"
        notify "⚠️ Restore blocked: backup too old"
        exit 1
    fi
fi

# =========================
# スナップショット（復元前）
# =========================

if [ -f "$TARGET_FILE" ]; then
    SNAPSHOT_FILE="$SNAPSHOT_DIR/index_$(date +%Y%m%d_%H%M%S).html"
    cp -a "$TARGET_FILE" "$SNAPSHOT_FILE"
    log "Snapshot saved: $(basename "$SNAPSHOT_FILE")"
fi

# =========================
# 安全チェック
# =========================

if [[ "$LATEST" == *".."* ]] || [[ "$LATEST" == *"~"* ]]; then
    log "Invalid backup path detected: $LATEST"
    notify "❌ Restore blocked: invalid path"
    exit 1
fi

if [ -z "${LATEST:-}" ] || [ ! -f "$LATEST" ]; then
    log "No backup found"
    notify "❌ Restore failed: no backup"
    exit 1
fi

if [ ! -s "$LATEST" ]; then
    log "Invalid backup: $LATEST"
    notify "❌ Restore failed: invalid backup"
    exit 1
fi

# =========================
# SHA256チェック
# =========================

BACKUP_HASH=$(sha256sum "$LATEST" | awk '{print $1}')

# =========================
# diff確認
# =========================

if [ -f "$TARGET_FILE" ]; then
    echo "===== diff preview ====="
    diff "$TARGET_FILE" "$LATEST" || true
    echo "========================"
fi

# =========================
# 確認
# =========================

if [ "$FORCE" != "true" ]; then
    echo "Restore target: $(basename "$LATEST")"
    read -p "Are you sure? (y/N): " -r

    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        log "Restore cancelled"
        notify "⚠️ Restore cancelled"
        exit 0
    fi
fi

# =========================
# ロールバック保存
# =========================

if [ -f "$TARGET_FILE" ]; then
    cp -a "$TARGET_FILE" "$ROLLBACK_FILE"
    log "Rollback saved"
fi

ROLLBACK_HASH=$(sha256sum "$ROLLBACK_FILE" 2>/dev/null | awk '{print $1}')

# =========================
# 復元実行
# =========================

cp -a "$LATEST" "$TARGET_FILE"

# =========================
# 自動ロールバック検証
# =========================

RESTORED_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')

if [ "$RESTORED_HASH" != "$BACKUP_HASH" ]; then
    log "Hash mismatch detected, rollback triggered"
    cp -a "$ROLLBACK_FILE" "$TARGET_FILE"
    notify "❌ Restore failed: rollback executed"
    exit 1
fi

# =========================
# 履歴
# =========================

COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

echo "{\"time\":\"$(date +%s)\",\"file\":\"$(basename "$LATEST")\",\"count\":$COUNT}" >> "$JSON_LOG"

echo "[$COUNT] $(date '+%Y-%m-%d %H:%M:%S') restored: $(basename "$LATEST")" >> "$HISTORY_FILE"

# =========================
# diff通知
# =========================

if [ -f "$TARGET_FILE" ]; then
    DIFF_OUTPUT=$(diff "$ROLLBACK_FILE" "$TARGET_FILE" | head -20 || true)
    if [ -n "$DIFF_OUTPUT" ]; then
        notify "📊 Restore diff:\n$DIFF_OUTPUT"
    fi
fi

# =========================
# 完了
# =========================

log "Restore file size: $(stat -f%z "$TARGET_FILE" 2>/dev/null || stat -c%s "$TARGET_FILE") bytes"
log "Restore completed: $(basename "$LATEST")"
notify "♻️ Restore completed: $(basename "$LATEST")"

if [[ -f "/home/r.h/docker/.env" ]]; then
    source "/home/r.h/docker/.env"
fi

exit 0
