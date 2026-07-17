#!/bin/bash
set -Eeuo pipefail

echo "[BOOT] starting cron"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

crontab "$PROJECT_ROOT/cronjob.txt"

cron -f

