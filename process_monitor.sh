#!/bin/bash
set -Eeuo pipefail

# ==============================================================================
# Process Monitor (Production Stable Final)
# ==============================================================================

# ------------------------------------------------------------------------------
# globals
# ------------------------------------------------------------------------------

LOCK_FILE="/tmp/process_monitor.lock"
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
if PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd 2>/dev/null)"; then
    :
else
    PROJECT_ROOT="$(pwd)"
fi

ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
    set +u
    # shellcheck disable=SC1090
    source "$ENV_FILE" 2>/dev/null || true
    set -u
fi

BASE_DIR="${BASE_DIR:-$PROJECT_ROOT}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
STATE_DIR="${STATE_DIR:-$BASE_DIR/state}"
METRIC_DIR="${METRIC_DIR:-$BASE_DIR/metrics}"

mkdir -p "$LOG_DIR" "$STATE_DIR" "$METRIC_DIR" 2>/dev/null || true

LOG_FILE="$LOG_DIR/process.log"
STATE_FILE="$STATE_DIR/process_state.txt"
METRIC_FILE="$METRIC_DIR/process.prom"

# shellcheck source=./lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"

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
    log_warn "already running"
    exit 0
}

# ------------------------------------------------------------------------------
# config
# ------------------------------------------------------------------------------

WEBHOOK_URL="${WEBHOOK_URL:-}"
SLACK_ENABLED=0
[[ -n "$WEBHOOK_URL" ]] && SLACK_ENABLED=1

PROCESS_NAME="${PROCESS_NAME:-cron}"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
export LC_ALL=C

# ------------------------------------------------------------------------------
# process check
# ------------------------------------------------------------------------------

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    state="OK"
else
    state="CRITICAL"
fi

log_info "process=$PROCESS_NAME state=$state"

# ------------------------------------------------------------------------------
# state decision
# ------------------------------------------------------------------------------

prev_state="$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")"

# ------------------------------------------------------------------------------
# metrics (atomic safe)
# ------------------------------------------------------------------------------

METRIC_TMP="$(mktemp 2>/dev/null || echo "/tmp/metric.$$")"

if [[ "$state" == "OK" ]]; then
    RUNNING=1
else
    RUNNING=0
fi

echo "process_running $RUNNING" > "$METRIC_TMP"

mv "$METRIC_TMP" "$METRIC_FILE" 2>/dev/null || true

# ------------------------------------------------------------------------------
# slack notify (state change only)
# ------------------------------------------------------------------------------

if [[ "$state" != "$prev_state" ]]; then

    HOSTNAME="$(hostname 2>/dev/null || echo "unknown")"

    case "$state" in
    CRITICAL) TEXT="🚨 CRITICAL [$HOSTNAME]: process '$PROCESS_NAME' stopped" ;;
    OK)       TEXT="✅ RECOVERY [$HOSTNAME]: process '$PROCESS_NAME' running" ;;
    *)        TEXT="ℹ️ UNKNOWN [$HOSTNAME]" ;;
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
            log_warn "slack failed code=$HTTP_CODE"
        fi
    else
        SLACK_OK=1
        log_info "slack disabled"
    fi

    STATE_TMP="$(mktemp 2>/dev/null || echo "/tmp/state.$$")"
    echo "$state" > "$STATE_TMP"
    mv "$STATE_TMP" "$STATE_FILE" 2>/dev/null || true

    log_info "state: $prev_state -> $state (slack=$SLACK_OK)"
fi

# ------------------------------------------------------------------------------
# log rotation
# ------------------------------------------------------------------------------

SIZE="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"

if (( SIZE > 10485760 )); then
    cp "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
    : > "$LOG_FILE" 2>/dev/null || true
    log_info "log rotated"
fi

exit 0
