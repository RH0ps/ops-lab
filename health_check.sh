#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===== Health Check ====="

DOCKER_STATE="OK"

if command -v docker >/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' | grep -q "^ops-lab$"; then
        echo "[OK] Docker container"
    else
        echo "[ERROR] Docker container"
        DOCKER_STATE="CRITICAL"
    fi
else
    echo "[INFO] Docker command not available"
    DOCKER_STATE="UNKNOWN"
fi

# Logs
if [[ -d "$PROJECT_ROOT/logs" ]]; then
    echo "[OK] logs/"
else
    echo "[ERROR] logs/"
fi

# Metrics
if [[ -d "$PROJECT_ROOT/metrics" ]]; then
    echo "[OK] metrics/"
else
    echo "[ERROR] metrics/"
fi

# State
if [[ -d "$PROJECT_ROOT/state" ]]; then
    echo "[OK] state/"
else
    echo "[ERROR] state/"
fi

# Scripts
for script in \
    disk_monitor.sh \
    cpu_monitor.sh \
    memory_monitor.sh \
    process_monitor.sh \
    backup.sh \
    restore.sh \
    log_rotate.sh \
    health_check.sh
do
    if [[ -x "$PROJECT_ROOT/$script" ]]; then
        echo "[OK] $script"
    else
        echo "[ERROR] $script"
    fi
done

# Metrics files
for metric in \
    cpu.prom \
    disk.prom \
    memory.prom \
    process.prom \
    backup.prom
do
    if [[ -f "$PROJECT_ROOT/metrics/$metric" ]]; then
        echo "[OK] $metric"
    else
        echo "[WARN] $metric (not found)"
    fi
done

# Log files
for log in \
    monitor.log \
    cpu.log \
    memory.log \
    process.log \
    backup.log \
    restore.log \
    rotate.log
do
    if [[ -f "$PROJECT_ROOT/logs/$log" ]]; then
        echo "[OK] $log"
    else
        echo "[WARN] $log (not found)"
    fi
done

# =========================
# Overall Health
# =========================

CPU_STATE=$(cat "$PROJECT_ROOT/state/cpu_state.txt" 2>/dev/null || echo "UNKNOWN")
DISK_STATE=$(cat "$PROJECT_ROOT/state/disk_state.txt" 2>/dev/null || echo "UNKNOWN")
MEMORY_STATE=$(cat "$PROJECT_ROOT/state/memory_state.txt" 2>/dev/null || echo "UNKNOWN")
PROCESS_STATE=$(cat "$PROJECT_ROOT/state/process_state.txt" 2>/dev/null || echo "UNKNOWN")

echo
echo "===== Monitor Status ====="
printf "%-10s %s\n" "Docker:" "$DOCKER_STATE"
printf "%-10s %s\n" "CPU:" "$CPU_STATE"
printf "%-10s %s\n" "Disk:" "$DISK_STATE"
printf "%-10s %s\n" "Memory:" "$MEMORY_STATE"
printf "%-10s %s\n" "Process:" "$PROCESS_STATE"

OVERALL="OK"

for STATE in \
    "$DOCKER_STATE" \
    "$CPU_STATE" \
    "$DISK_STATE" \
    "$MEMORY_STATE" \
    "$PROCESS_STATE"
do
    if [[ "$STATE" == "CRITICAL" ]]; then
        OVERALL="CRITICAL"
        break
    elif [[ "$STATE" == "WARN" && "$OVERALL" != "CRITICAL" ]]; then
        OVERALL="WARN"
    elif [[ "$STATE" == "UNKNOWN" && "$OVERALL" == "OK" ]]; then
        OVERALL="UNKNOWN"
    fi
done

echo
echo "=============================="
echo "Overall Health : $OVERALL"

case "$OVERALL" in
    OK)
        EXIT_CODE=0
        ;;
    WARN)
        EXIT_CODE=1
        ;;
    CRITICAL)
        EXIT_CODE=2
        ;;
    *)
        EXIT_CODE=3
        ;;
esac

echo "Exit Code      : $EXIT_CODE"
echo "=============================="

exit "$EXIT_CODE"


