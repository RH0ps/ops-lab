#!/bin/bash

ops_git(){
  (cd "$OPS_REPO" && git status) || return 1
}

ops_pull(){
  (cd "$OPS_REPO" && git pull) || return 1
}

ops_repo(){
  (cd "$OPS_REPO" && git status && echo && git log --oneline -5) || return 1
}
