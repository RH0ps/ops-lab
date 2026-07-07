#!/bin/bash

ops_diagnose(){
  echo "===== PS ====="
  ops_ps

  echo
  echo "===== HEALTH ====="
  ops_health

  echo
  echo "===== DISK ====="
  ops_disk

  echo
  echo "===== BACKUP ====="
  ops_backup_ls

  echo
  echo "===== LOG ERRORS ====="
  docker compose -f "$OPS_COMPOSE" logs --tail=300 "$OPS_SERVICE" | grep -i error || true
  echo
  echo "===== UPTIME ====="
  ops_uptime

  echo
  echo "===== PORTS ====="
  ops_ports
}

ops_test(){
  echo "=== backup ==="
  ops_backup

  echo
  echo "=== disk ==="
  ops_disk

  echo
  echo "done"
}

ops_info(){
  echo "===== STATUS ====="
  ops_status

  echo
  echo "===== CRON ====="
  ops_cron

  echo
  echo "===== TOP ====="
  local CID
  CID=$(ops_container_id) || return 1
  docker stats "$CID" --no-stream
}

ops_errors(){
  docker compose -f "$OPS_COMPOSE" logs --tail=300 "$OPS_SERVICE" | grep -i error || true
}

ops_fix(){
  ops_prune
  ops_rebuild
  ops_restart
}
