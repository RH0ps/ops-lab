#!/bin/bash

# =========================
# ops-lab management CLI (ULTIMATE FINAL PRO)
# =========================

OPS_REPO="$HOME/study/github/ops-lab"
OPS_COMPOSE="$OPS_REPO/docker-compose.yml"
OPS_SERVICE="ops-lab"
OPS_SCRIPT="/home/r.h/docker"

# =========================
# internal helpers
# =========================

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

# =========================
# ENTRY
# =========================

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

# =========================
# lifecycle
# =========================

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

# =========================
# status / logs
# =========================

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

# =========================
# health / runtime
# =========================

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

# =========================
# exec tools
# =========================

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

# =========================
# scripts
# =========================

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

# =========================
# config / maintenance
# =========================

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

# =========================
# git
# =========================

ops_git(){
  (cd "$OPS_REPO" && git status) || return 1
}

ops_pull(){
  (cd "$OPS_REPO" && git pull) || return 1
}

ops_repo(){
  (cd "$OPS_REPO" && git status && echo && git log --oneline -5) || return 1
}

# =========================
# docker image
# =========================

ops_img(){
  docker images | grep "$OPS_SERVICE" || echo "no image"
}

ops_tree(){
  local CID
  CID=$(ops_check) || return 1
  docker exec "$CID" find /home/r.h/docker -type f | head -200
}

# =========================
# diagnostics
# =========================

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

# =========================
# quick test
# =========================

ops_test(){
  echo "=== backup ==="
  ops_backup

  echo
  echo "=== disk ==="
  ops_disk

  echo
  echo "done"
}

# =========================
# full info
# =========================

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

# =========================
# extra (useful add-ons)
# =========================

ops_errors(){
  docker compose -f "$OPS_COMPOSE" logs --tail=300 "$OPS_SERVICE" | grep -i error || true
}

ops_fix(){
  ops_prune
  ops_rebuild
  ops_restart
}

ops_stats(){
  docker stats --no-stream
}

# =========================
# help
# =========================

ops_help(){
  echo "ops-lab CLI"
  echo "back / ops_shell        : コンテナに入る"
  echo "ops_force_shell         : shell強制起動"
  echo "ops_up / ops_down       : 起動 / 停止"
  echo "ops_restart             : 再起動"
  echo "ops_rebuild             : 再構築"
  echo "ops_update              : git pull + restart"
  echo "ops_logs [service]      : ログ"
  echo "ops_status              : 状態一覧"
  echo "ops_health              : health"
  echo "ops_cron                : cron"
  echo "ops_exec [cmd]          : 実行"
  echo "ops_cat [path]          : ファイル閲覧"
  echo "ops_backup / ops_disk   : scripts"
  echo "ops_prune / ops_clean   : docker掃除"
  echo "ops_top                 : リソース監視"
  echo "ops_stats               : 全体stats"
  echo "ops_errors              : error抽出"
  echo "ops_fix                 : 自動復旧"
  echo "ops_diagnose            : 総合診断"
  echo "ops_info                : サマリー"
}

