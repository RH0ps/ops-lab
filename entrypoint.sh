#!/bin/bash
crontab -u r.h /tmp/cronjob.txt
exec cron -f

