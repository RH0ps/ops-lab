#!/bin/bash

ops_shell(){
  local CID
  CID=$(ops_check) || return 1
  docker exec -it "$CID" bash
}

back(){
  ops_shell
}

ops_force_shell(){
  local CID
  CID=$(ops_container_id) || return 1

  if [[ -t 0 ]]; then
    docker exec -it "$CID" bash || docker exec -it "$CID" sh
  else
    docker exec "$CID" bash || docker exec "$CID" sh
  fi
}
