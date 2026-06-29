#!/bin/bash
set -e

crontab /home/r.h/docker/cronjob.txt

exec cron -f
