#!/bin/bash
set -Eeuo pipefail

# ==============================================================================
# Disk Monitor (Production Stable Final)
# ==============================================================================

# ------------------------------------------------------------------------------
# globals
# ------------------------------------------------------------------------------
LOCK_FD=9
LOCK_FILE="/tmp/disk_monitor.lock"
STATE_TMP=""
METRIC_TMP=""

cleanup() {
    [[ -n "${STATE_TMP:-}" && -f "$STATE_TMP" ]] && rm -f "$STATE_TMP" 2>/dev/null || true
    [[ -n "${METRIC_TMP:-}" && -f "$METRIC_TMP" ]] && rm -f "$METRIC_TMP" 2>/dev/null || true
}
trap cleanup EXIT
trap 'echo "$(date "+%F %T") [ERROR] line $LINENO" >&2' ERR

# ------------------------------------------------------------------------------
# bootstrap
# ------------------------------------------------------------------------------

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd 2>/dev/null || pwd)"

ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
    set +u
    source "$ENV_FILE" 2>/dev/null || true
    set -u
fi

BASE_DIR="${BASE_DIR:-$PROJECT_ROOT}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
STATE_DIR="${STATE_DIR:-$BASE_DIR/state}"
METRIC_DIR="${METRIC_DIR:-$BASE_DIR/metrics}"

mkdir -p "$LOG_DIR" "$STATE_DIR" "$METRIC_DIR" 2>/dev/null || true

LOG_FILE="$LOG_DIR/monitor.log"
STATE_FILE="$STATE_DIR/disk_state.txt"
METRIC_FILE="$METRIC_DIR/disk.prom"

# log fallback
if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/monitor.log"
    touch "$LOG_FILE" 2>/dev/null || true
fi

# state init
[[ -f "$STATE_FILE" ]] || echo "UNKNOWN" > "$STATE_FILE" 2>/dev/null || true

# ------------------------------------------------------------------------------
# lock (multi-run protection)
# ------------------------------------------------------------------------------

exec 9>"$LOCK_FILE"
flock -n 9 || {
    echo "$(date "+%F %T") [WARN] already running" >> "$LOG_FILE"
    exit 0
}

# ------------------------------------------------------------------------------
# config
# ------------------------------------------------------------------------------

WEBHOOK_URL="${WEBHOOK_URL:-}"
SLACK_ENABLED=0
[[ -n "$WEBHOOK_URL" ]] && SLACK_ENABLED=1

CRIT_THRESHOLD="${1:-90}"
WARN_THRESHOLD="${2:-80}"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
export LC_ALL=C

# ------------------------------------------------------------------------------
# disk usage (safe)
# ------------------------------------------------------------------------------

if command -v timeout >/dev/null 2>&1; then
    DF_OUT="$(timeout 5 df -P / 2>/dev/null || true)"
else
    DF_OUT="$(df -P / 2>/dev/null || true)"
fi

USAGE="$(echo "$DF_OUT" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

if ! [[ "$USAGE" =~ ^[0-9]+$ ]]; then
    echo "$(date "+%F %T") [FATAL] invalid usage=$USAGE" >> "$LOG_FILE"
    exit 1
fi

# ------------------------------------------------------------------------------
# state decision
# ------------------------------------------------------------------------------

prev_state="$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")"

if (( USAGE >= CRIT_THRESHOLD )); then
    state="CRITICAL"
elif (( USAGE >= WARN_THRESHOLD )); then
    state="WARN"
else
    state="OK"
fi

echo "$(date "+%F %T") [INFO] usage=${USAGE}% state=${state}" >> "$LOG_FILE"

# ------------------------------------------------------------------------------
# metrics (atomic safe)
# ------------------------------------------------------------------------------

METRIC_TMP="$(mktemp 2>/dev/null || echo "/tmp/metric.$$")"

if [[ "$state" == "OK" ]]; then
    STATUS=0
elif [[ "$state" == "WARN" ]]; then
    STATUS=1
else
    STATUS=2
fi

echo "disk_usage_percent $USAGE" > "$METRIC_TMP"
echo "disk_status $STATUS" >> "$METRIC_TMP"

mv "$METRIC_TMP" "$METRIC_FILE" 2>/dev/null || true

# ------------------------------------------------------------------------------
# slack notify (state change only)
# ------------------------------------------------------------------------------

if [[ "$state" != "$prev_state" ]]; then

    HOSTNAME="$(hostname 2>/dev/null || echo "unknown")"

    case "$state" in
        CRITICAL) TEXT="🚨 CRITICAL [$HOSTNAME]: ${USAGE}% disk usage" ;;
        WARN)     TEXT="⚠️ WARNING [$HOSTNAME]: ${USAGE}% disk usage" ;;
        OK)       TEXT="✅ RECOVERY [$HOSTNAME]: ${USAGE}% disk usage" ;;
        *)        TEXT="ℹ️ UNKNOWN [$HOSTNAME]: ${USAGE}%" ;;
    esac

    if command -v jq >/dev/null 2>&1; then
        PAYLOAD="$(jq -n --arg text "$TEXT" '{text:$text}')"
    else
        TEXT_ESCAPED="$(printf '%s' "$TEXT" | sed 's/"/\\"/g')"
        PAYLOAD="{\"text\":\"$TEXT_ESCAPED\"}"
    fi

    SLACK_OK=0

    if [[ "$SLACK_ENABLED" -eq 1 ]]; then
        HTTP_CODE="$(curl -sS -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            --max-time 10 \
            --data "$PAYLOAD" \
            "$WEBHOOK_URL" || echo "000")"

        if [[ "$HTTP_CODE" == "200" ]]; then
            SLACK_OK=1
        else
            echo "$(date "+%F %T") [WARN] slack failed code=$HTTP_CODE" >> "$LOG_FILE"
        fi
    else
        SLACK_OK=1
        echo "$(date "+%F %T") [INFO] slack disabled" >> "$LOG_FILE"
    fi

    STATE_TMP="$(mktemp 2>/dev/null || echo "/tmp/state.$$")"
    echo "$state" > "$STATE_TMP"
    mv "$STATE_TMP" "$STATE_FILE" 2>/dev/null || true

    echo "$(date "+%F %T") [INFO] state: $prev_state -> $state (slack=$SLACK_OK)" >> "$LOG_FILE"
fi

# ------------------------------------------------------------------------------
# log rotation
# ------------------------------------------------------------------------------

SIZE="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"

if (( SIZE > 10485760 )); then
    cp "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
    : > "$LOG_FILE" 2>/dev/null || true
    echo "$(date "+%F %T") [INFO] log rotated" >> "$LOG_FILE"
fi

exit 0
