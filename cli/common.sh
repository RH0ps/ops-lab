#!/bin/bash

# Common settings / helper functions

OPS_REPO="$HOME/study/github/ops-lab"
OPS_COMPOSE="$OPS_REPO/docker-compose.yml"
OPS_SERVICE="ops-lab"
OPS_SCRIPT="/home/r.h/docker"

ops_container_id(){
  docker compose -f "$OPS_COMPOSE" ps -q "$OPS_SERVICE" 2>/dev/null
}

ops_check(){
  local CID
  CID=$(ops_container_id)

  if [ -z "$CID" ]; then
    echo "container not found"
    return 1
  fi

  local STATUS
  STATUS=$(docker inspect -f '{{.State.Status}}' "$CID" 2>/dev/null)

  if [[ "$STATUS" != "running" ]]; then
    echo "container not running (status: $STATUS)"
    return 1
  fi

  echo "$CID"
}
