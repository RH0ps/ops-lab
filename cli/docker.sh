#!/bin/bash

ops_config(){
  docker compose -f "$OPS_COMPOSE" config
}

ops_prune(){
  echo "system prune"
  docker system prune -f

  echo "volume prune"
  docker volume prune -f
}

ops_clean(){
  ops_prune
}

ops_img(){
  docker images | grep "$OPS_SERVICE" || echo "no image"
}

ops_tree(){
  local CID
  CID=$(ops_check) || return 1
  docker exec "$CID" find /home/r.h/docker -type f | head -200
}

ops_stats(){
  docker stats --no-stream
}
