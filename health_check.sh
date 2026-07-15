#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===== Health Check ====="

# Docker
if docker ps --format '{{.Names}}' | grep -q "^ops-lab$"; then
    echo "[OK] Docker container"
else
    echo "[ERROR] Docker container"
fi

# Scripts
for script in \
    disk_monitor.sh \
    cpu_monitor.sh \
    backup.sh \
    restore.sh \
    log_rotate.sh
do
    if [[ -x "$PROJECT_ROOT/$script" ]]; then
        echo "[OK] $script"
    else
        echo "[ERROR] $script"
    fi
done

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

# Metrics files
for metric in \
    cpu.prom \
    disk.prom \
    backup.prom
do
    if [[ -f "$PROJECT_ROOT/metrics/$metric" ]]; then
        echo "[OK] $metric"
    else
        echo "[WARN] $metric (not found)"
    fi
done

# State
if [[ -d "$PROJECT_ROOT/state" ]]; then
    echo "[OK] state/"
else
    echo "[ERROR] state/"
fi

# Log files
for log in \
    monitor.log \
    cpu.log \
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



