#!/bin/bash
set -e

echo "[BOOT] starting cron"

crontab /home/r.h/docker/cronjob.txt

cron -f

