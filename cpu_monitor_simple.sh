#!/usr/bin/env bash

set -Eeuo pipefail

idle=$(top -l 1 | grep "CPU usage" | sed -E 's/.* ([0-9.]+)% idle.*/\1/')

cpu=$(awk -v idle="$idle" 'BEGIN {
    printf "%.0f", 100 - idle
}')

echo "CPU Usage: ${cpu}%"

