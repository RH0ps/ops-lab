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
