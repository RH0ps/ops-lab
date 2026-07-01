#!/bin/bash

WEBHOOK_URL="${WEBHOOK_URL:?WEBHOOK_URL is required}"

if [ -f "$HOME/study/docker/.env" ]; then
    source "$HOME/study/docker/.env"
fi

THRESHOLD=${1:-80}

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

STATE_FILE="/tmp/disk_state.txt"
LOG_FILE="/home/r.h/docker/monitor.log"

prev_state="UNKNOWN"

if [ -f "$STATE_FILE" ]; then
    prev_state=$(cat "$STATE_FILE")
fi

if [ "$USAGE" -ge 90 ]; then
    state="CRITICAL"
elif [ "$USAGE" -ge 80 ]; then
    state="WARN"
else
    state="OK"
fi

echo "$(date) usage=${USAGE}% state=${state}" >> "$LOG_FILE"

if [ "$state" != "$prev_state" ]; then

    if [ "$state" = "CRITICAL" ]; then
        PAYLOAD="{\"text\":\"🚨 CRITICAL: ${USAGE}% (/)\"}"

    elif [ "$state" = "WARN" ]; then
        PAYLOAD="{\"text\":\"⚠️ WARNING: ${USAGE}% (/)\"}"

    elif [ "$state" = "OK" ]; then
        PAYLOAD="{\"text\":\"✅ RECOVERY: ${USAGE}% (/)\"}"
    fi

    echo "$state" > "$STATE_FILE"

    echo "Slack sent: $state" >> "$LOG_FILE"

    curl -s -X POST -H "Content-type: application/json" \
    --data "$PAYLOAD" "$WEBHOOK_URL" >> "$LOG_FILE" 2>&1
fi
