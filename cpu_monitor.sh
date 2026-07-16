#!/bin/bash
set -Eeuo pipefail

# ==============================================================================
# CPU Monitor (Production Stable Final)
# ==============================================================================

# ------------------------------------------------------------------------------
# globals
# ------------------------------------------------------------------------------
LOCK_FD=9
LOCK_FILE="/tmp/cpu_monitor.lock"
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

LOG_FILE="$LOG_DIR/cpu.log"
STATE_FILE="$STATE_DIR/cpu_state.txt"
METRIC_FILE="$METRIC_DIR/cpu.prom"

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

CRIT_THRESHOLD="${1:-90}"
WARN_THRESHOLD="${2:-80}"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
export LC_ALL=C

# ------------------------------------------------------------------------------
# cpu usage (safe)
# ------------------------------------------------------------------------------

get_cpu_usage() {

    if [[ "$(uname)" == "Darwin" ]]; then

        CPU_LINE="$(top -l 1 | grep "CPU usage" || true)"
        IDLE="$(echo "$CPU_LINE" | sed -E 's/.* ([0-9.]+)% idle.*/\1/')"

        awk -v idle="$IDLE" 'BEGIN {
            printf "%.0f", 100 - idle
        }'

    else

        IDLE="$(top -bn1 | awk '/Cpu\(s\)/ {
            for(i=1;i<=NF;i++){
                if($i ~ /id,/){
                    gsub(/id,/,"",$i)
                    print $i
                } 
            }
        }')"
        
        awk -v idle="$IDLE" 'BEGIN {
            printf "%.0f", 100 - idle
        }'

    fi
}

USAGE="$(get_cpu_usage)"

if ! [[ "$USAGE" =~ ^[0-9]+$ ]] || (( USAGE < 0 || USAGE > 100 )); then
    log_error "invalid cpu usage=$USAGE"
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

log_info "usage=${USAGE}% state=${state}"

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

echo "cpu_usage_percent $USAGE" > "$METRIC_TMP"
echo "cpu_status $STATUS" >> "$METRIC_TMP"

mv "$METRIC_TMP" "$METRIC_FILE" 2>/dev/null || true

# ------------------------------------------------------------------------------
# slack notify (state change only)
# ------------------------------------------------------------------------------

if [[ "$state" != "$prev_state" ]]; then

    HOSTNAME="$(hostname 2>/dev/null || echo "unknown")"

    case "$state" in
        CRITICAL) TEXT="🚨 CRITICAL [$HOSTNAME]: CPU usage ${USAGE}%" ;;
        WARN)     TEXT="⚠️ WARNING [$HOSTNAME]: CPU usage ${USAGE}%" ;;
        OK)       TEXT="✅ RECOVERY [$HOSTNAME]: CPU usage ${USAGE}%" ;;
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
