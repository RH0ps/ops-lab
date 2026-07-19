#!/bin/bash

# status / logs

ops_ps(){
  docker compose -f "$OPS_COMPOSE" ps "$OPS_SERVICE"
}

ops_logs(){
  local SERVICE="${1:-$OPS_SERVICE}"
  docker compose -f "$OPS_COMPOSE" logs -f --tail=200 "$SERVICE"
}

ops_logs_since(){
  docker compose -f "$OPS_COMPOSE" logs -f --since=10m "$OPS_SERVICE"
}

ops_status(){
  echo "===== PS ====="
  ops_ps

  echo
  echo "===== HEALTH ====="
  ops_health

  echo
  echo "===== IMAGE ====="
  ops_img

  echo
  echo "===== PORTS ====="
  ops_ports

  echo
  echo "===== UPTIME ====="
  ops_uptime
}

ops_health(){
  local CID
  CID=$(ops_container_id) || return 1

  docker inspect \
    --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' \
    "$CID"
}

ops_ports(){
  docker compose -f "$OPS_COMPOSE" ps "$OPS_SERVICE" --format "table {{.Name}}\t{{.Ports}}"
}

ops_top(){
  local CID
  CID=$(ops_container_id) || return 1
  docker stats "$CID" --no-stream
}

ops_uptime(){
  local CID
  CID=$(ops_container_id) || return 1
  docker inspect -f '{{.State.StartedAt}}' "$CID"
}

ops_cron(){
  local CID
  CID=$(ops_check) || return 1

  docker exec "$CID" crontab -l 2>/dev/null || echo "no crontab"
}

ops_monitor_status() {

    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    METRICS="$ROOT/metrics"

    echo "=============================="
    echo "      System Monitor"
    echo "=============================="

    if [[ -f "$METRICS/disk.prom" ]]; then

       USAGE=$(awk '/disk_usage_percent/ {print $2}' "$METRICS/disk.prom")
       STATUS=$(awk '/disk_status/ {print $2}' "$METRICS/disk.prom")

       case "$STATUS" in
           0) TEXT="OK" ;;
           1) TEXT="WARN" ;;
           2) TEXT="CRITICAL" ;;
       esac

       printf "Disk     : %-8s (%s%%)\n" "$TEXT" "$USAGE"
    fi

    if [[ -f "$METRICS/cpu.prom" ]]; then

        USAGE=$(awk '/cpu_usage_percent/ {print $2}' "$METRICS/cpu.prom")
        STATUS=$(awk '/cpu_status/ {print $2}' "$METRICS/cpu.prom")

        case "$STATUS" in
            0) TEXT="OK" ;;
            1) TEXT="WARN" ;;
            2) TEXT="CRITICAL" ;;
        esac

        printf "CPU      : %-8s (%s%%)\n" "$TEXT" "$USAGE"
    fi

    if [[ -f "$METRICS/memory.prom" ]]; then

        USAGE=$(awk '/memory_usage_percent/ {print $2}' "$METRICS/memory.prom")
        STATUS=$(awk '/memory_status/ {print $2}' "$METRICS/memory.prom")

        case "$STATUS" in
            0) TEXT="OK" ;;
            1) TEXT="WARN" ;;
            2) TEXT="CRITICAL" ;;
        esac

        printf "Memory   : %-8s (%s%%)\n" "$TEXT" "$USAGE"
    fi

    if [[ -f "$METRICS/process.prom" ]]; then

        RUNNING=$(awk '/process_running/ {print $2}' "$METRICS/process.prom")

        if [[ "$RUNNING" == "1" ]]; then
            TEXT="RUNNING"
        else
            TEXT="STOPPED"
        fi

        printf "Process  : %s\n" "$TEXT"

    fi

    echo
    echo "Updated : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================="
}
