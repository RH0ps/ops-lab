#!/bin/bash

ops_exec(){
  local CID
  CID=$(ops_check) || return 1

  if [[ -t 0 ]]; then
    docker exec -it "$CID" "$@"
  else
    docker exec "$CID" "$@"
  fi
}

ops_cat(){
  local CID
  CID=$(ops_check) || return 1
  [[ -z "$1" ]] && return 1
  docker exec "$CID" cat "$1"
}

ops_backup(){
  local CID
  CID=$(ops_check) || return 1
  docker exec "$CID" bash "$OPS_SCRIPT/backup.sh"
}

ops_disk(){
  local CID
  CID=$(ops_check) || return 1
  docker exec "$CID" bash "$OPS_SCRIPT/disk_monitor.sh"
}

ops_backup_ls(){
  ls -lh "$OPS_REPO/backup" 2>/dev/null || echo "no backup dir"
}

ops_check_all(){

  local PASS=0
  local FAIL=0
  
  echo "===== Container ====="
  ops_ps

  echo
  echo "===== Health ====="
  ops_health

  echo
  echo "===== Backup ====="
  ops_backup

  echo
  echo "===== Disk Monitor ====="
  ops_disk

  echo
  echo "===== Restore Script ====="

  local CID
  CID=$(ops_check) || return 1

  if docker exec "$CID" test -f "$OPS_SCRIPT/restore.sh"; then
    echo "OK - restore.sh exists"
    ((PASS++))
   else
    echo "NG - restore.sh not found"
    ((FAIL++))
fi

  echo
  echo "===== Backup Directory ====="

  if docker exec "$CID" test -d "$OPS_SCRIPT/backup"; then
    echo "OK - backup directory exists"
    ((PASS++))
  else
    echo "NG - backup directory not found"
    ((FAIL++))
  fi

  echo
  echo "===== Metrics Directory ====="

  if docker exec "$CID" test -d "$OPS_SCRIPT/metrics"; then
    echo "OK - metrics directory exists"
    ((PASS++))
  else
    echo "NG - metrics directory not found"
    ((FAIL++))
  fi

  echo
  echo "===== Logs Directory ====="

  if docker exec "$CID" test -d "$OPS_SCRIPT/logs"; then
    echo "OK - logs directory exists"
    ((PASS++))
  else
    echo "NG - logs directory not found"
    ((FAIL++))
  fi

echo
echo "===== Summary ====="

echo "PASS : $PASS"
echo "FAIL : $FAIL"

if (( FAIL == 0 )); then
    echo
    echo "System Status : HEALTHY"
else
    echo
    echo "System Status : FAILED"
fi
}
