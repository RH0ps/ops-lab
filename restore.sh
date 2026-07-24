#!/bin/bash

set -euo pipefail

# =========================
# 設定
# =========================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGETS=(
    "index.html"
    "docker-compose.yml"
)

LOG_FILE="$PROJECT_ROOT/logs/restore.log"

mkdir -p "$PROJECT_ROOT/logs"

# shellcheck source=./lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"

echo "Restore target"

select TARGET in "${TARGETS[@]}"; do
    [ -n "$TARGET" ] && break
done

TARGET_FILE="$PROJECT_ROOT/$TARGET"

NAME="${TARGET%.*}"
EXT="${TARGET##*.}"

METRIC_FILE="$PROJECT_ROOT/metrics/restore.prom"
SUCCESS_FILE="$PROJECT_ROOT/state/restore_success_count"
FAILURE_FILE="$PROJECT_ROOT/state/restore_failure_count"
ROLLBACK_FILE="$PROJECT_ROOT/${NAME}.rollback.${EXT}"
BACKUP_DIR="$PROJECT_ROOT/backup"
HISTORY_FILE="$PROJECT_ROOT/logs/${NAME}_restore_history.log"
COUNT_FILE="$PROJECT_ROOT/state/${NAME}_restore_count"

SNAPSHOT_DIR="$PROJECT_ROOT/backup_snapshots"
JSON_LOG="$PROJECT_ROOT/logs/${NAME}_restore_history.jsonl"

LOCK_FILE="/tmp/restore.lock"
MAX_AGE_SEC=$((60*60*24*7))  # 7日

if [ -f "$PROJECT_ROOT/.env" ]; then
    # shellcheck source=./.env
    source "$PROJECT_ROOT/.env"
fi

WEBHOOK_URL="${WEBHOOK_URL:-}"
SLACK_ENABLED=0
[[ -n "$WEBHOOK_URL" ]] && SLACK_ENABLED=1

FORCE="${FORCE:-false}"

# =========================
# ロック対応確認（macOS / Linux）
# =========================

if command -v flock >/dev/null 2>&1; then
    LOCK_SUPPORTED=true
else
    LOCK_SUPPORTED=false
fi

if [ "$LOCK_SUPPORTED" = true ]; then
    exec 9>"$LOCK_FILE"

    flock -n 9 || {
        log_warn "Restore already running"
        exit 0
    }
fi

# =========================
# 互換関数定義
# =========================

# macOS / Linux 共通のハッシュ計算関数
hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# =========================
# 準備（ディレクトリ作成）
# =========================

mkdir -p "$SNAPSHOT_DIR"
mkdir -p "$(dirname "$COUNT_FILE")"
mkdir -p "$(dirname "$JSON_LOG")"

mkdir -p "$(dirname "$METRIC_FILE")"

[ -f "$SUCCESS_FILE" ] || echo 0 > "$SUCCESS_FILE"
[ -f "$FAILURE_FILE" ] || echo 0 > "$FAILURE_FILE"

# =========================
# 通知関数
# =========================

notify() {

    [[ "$SLACK_ENABLED" -eq 0 ]] && return 0

    local message="$1"

    if ! curl -sS \
        --max-time 5 \
        -X POST \
        -H "Content-type: application/json" \
        --data "$(jq -n --arg text "$message" '{text:$text}')" \
        "$WEBHOOK_URL" >/dev/null 2>&1
    then
        log_warn "Slack notification failed"
        return 1
    fi
}

# =========================
# エラー検知
# =========================

trap '
EXIT_CODE=$?
echo "ERR trap called"

FAILURE_COUNT=$(cat "$FAILURE_FILE")
FAILURE_COUNT=$((FAILURE_COUNT + 1))
echo "$FAILURE_COUNT" > "$FAILURE_FILE"

{
    echo "restore_success_total $(cat "$SUCCESS_FILE")"
    echo "restore_failure_total $FAILURE_COUNT"
    echo "restore_last_timestamp $(date +%s)"
} > "$METRIC_FILE"

log_error "Restore failed (exit code=$EXIT_CODE)"
notify "❌ Restore failed"
exit "$EXIT_CODE"
' ERR

# =========================
# dry-run
# =========================

if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "[DRY RUN] restore disabled"
    exit 0
fi

# =========================
# バックアップ一覧
# =========================

echo "===== backup list ====="

find "$BACKUP_DIR" \
    -maxdepth 1 \
    -name "${NAME}_*.${EXT}" \
    -type f \
    | sort -r || true
echo "======================="

# =========================
# 最新 or 指定バックアップ
# =========================

TARGET_BACKUP="${1:-}"

if [ -n "$TARGET_BACKUP" ]; then

    if [[ "$TARGET_BACKUP" == */* ]]; then
        log_error "Invalid backup name"
        false
    fi

    LATEST="$BACKUP_DIR/$TARGET_BACKUP"

else
    LATEST=$(
    find "$BACKUP_DIR" \
        -maxdepth 1 \
        -name "${NAME}_*.${EXT}" \
        -type f \
        | sort | tail -1
)
fi

# =========================
# 安全チェック
# =========================

if [ -z "${LATEST:-}" ] || [ ! -f "$LATEST" ]; then
    log_error "No backup found"
    false
fi

if [[ ! "$LATEST" == "$BACKUP_DIR"/* ]]; then
    log_error "ERROR: Path outside backup directory"
    false
fi

if [ ! -s "$LATEST" ]; then
    log_error "Invalid backup: $LATEST"
    false
fi

# =========================
# 古すぎるバックアップ拒否
# （ファイル名の日時で判定）
# =========================

FILE_NAME=$(basename "$LATEST")

REGEX="^${NAME}_[0-9]{8}_[0-9]{6}\\.${EXT}$"

if [[ "$FILE_NAME" =~ $REGEX ]]; then
    FILE_DATE=$(echo "$FILE_NAME" | sed -E "s/${NAME}_([0-9]{8})_([0-9]{6})\\.${EXT}/\\1\\2/")

    if date -d "2020-01-01" +%s >/dev/null 2>&1; then
        BACKUP_TIME=$(date -d \
            "${FILE_DATE:0:4}-${FILE_DATE:4:2}-${FILE_DATE:6:2} ${FILE_DATE:8:2}:${FILE_DATE:10:2}:${FILE_DATE:12:2}" \
            +%s)
    else
        BACKUP_TIME=$(date -j -f "%Y%m%d%H%M%S" "$FILE_DATE" +%s)
    fi

    AGE=$(( $(date +%s) - BACKUP_TIME ))

    if [ "$AGE" -gt "$MAX_AGE_SEC" ]; then
        log_warn "Backup too old: $LATEST"
        false
    fi
else
    log_error "Invalid backup filename format: $FILE_NAME"
    false
fi

# =========================
# スナップショット（復元前）
# =========================

if [ -f "$TARGET_FILE" ]; then
    SNAPSHOT_FILE="$SNAPSHOT_DIR/${NAME}_$(date +%Y%m%d_%H%M%S).${EXT}"
    cp -a "$TARGET_FILE" "$SNAPSHOT_FILE"
    log_info "Snapshot saved: $(basename "$SNAPSHOT_FILE")"
fi

# =========================
# SHA256チェック
# =========================

BACKUP_HASH=$(hash_file "$LATEST")

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
        log_info "Restore cancelled"
        notify "⚠️ Restore cancelled"
        false
    fi
fi

# =========================
# ロールバック保存
# =========================

if [ -f "$TARGET_FILE" ]; then
    cp -a "$TARGET_FILE" "$ROLLBACK_FILE"
    log_info "Rollback saved"
fi

# =========================
# 復元実行
# =========================

cp -a "$LATEST" "$TARGET_FILE"

# =========================
# 自動ロールバック検証
# =========================

RESTORED_HASH=$(hash_file "$TARGET_FILE")

if [ "$RESTORED_HASH" != "$BACKUP_HASH" ]; then
    log_error "Hash mismatch detected, rollback triggered"
    # 【修正②】ロールバックファイルが存在する場合のみ安全に cp を実行する
    if [ -f "$ROLLBACK_FILE" ]; then
        cp -a "$ROLLBACK_FILE" "$TARGET_FILE"
    else
        log_warn "Rollback skipped: rollback file does not exist"
    fi
    notify "❌ Restore failed: rollback executed"
    false
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

if [ -f "$ROLLBACK_FILE" ] && [ -f "$TARGET_FILE" ]; then
    DIFF_OUTPUT=$(diff "$ROLLBACK_FILE" "$TARGET_FILE" | head -20 || true)
    if [ -n "$DIFF_OUTPUT" ]; then
        notify "📊 Restore diff:\n$DIFF_OUTPUT"
    fi
fi

# =========================
# 完了
# =========================

FILE_SIZE=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    FILE_SIZE=$(stat -f%z "$TARGET_FILE" 2>/dev/null || echo 0)
else
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo 0)
fi
log_info "Restore file size: $FILE_SIZE bytes"
log_info "Restore completed: $(basename "$LATEST")"
SUCCESS_COUNT=$(cat "$SUCCESS_FILE")
SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
echo "$SUCCESS_COUNT" > "$SUCCESS_FILE"

FAILURE_COUNT=$(cat "$FAILURE_FILE")

{
    echo "restore_success_total $SUCCESS_COUNT"
    echo "restore_failure_total $FAILURE_COUNT"
    echo "restore_last_timestamp $(date +%s)"
} > "$METRIC_FILE"

notify "♻️ Restore completed: $(basename "$LATEST")"

exit 0
