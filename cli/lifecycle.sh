#!/bin/bash

ops_up(){
  docker compose -f "$OPS_COMPOSE" up -d
}

ops_down(){
  read -p "本当に停止しますか？ (y/N): " -r
  [[ ! "$REPLY" =~ ^[Yy]$ ]] && { echo "cancel"; return 1; }
  docker compose -f "$OPS_COMPOSE" down
}

ops_build(){
  docker compose -f "$OPS_COMPOSE" build --no-cache
}

ops_restart(){
  docker compose -f "$OPS_COMPOSE" restart "$OPS_SERVICE"
}

ops_rebuild(){
  read -p "rebuildしますか？ (y/N): " -r
  [[ ! "$REPLY" =~ ^[Yy]$ ]] && { echo "cancel"; return 1; }

  docker compose -f "$OPS_COMPOSE" down
  ops_build
  ops_up
}

ops_redeploy(){
  ops_rebuild
}

ops_update(){
  (cd "$OPS_REPO" && git pull) || return 1
  ops_restart
}
