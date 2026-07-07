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
