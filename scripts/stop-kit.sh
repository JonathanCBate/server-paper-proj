#!/usr/bin/env bash
# Stop all servers for a kit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/console.sh"

stop_server_background() {
  local kit_id="$1"
  local sid="$2"
  local pid_file="${PID_DIR}/${kit_id}-${sid}.pid"

  if [[ ! -f "$pid_file" ]]; then
    log_warn "No PID file for ${sid}, skipping"
    return 0
  fi

  local pid
  pid="$(cat "$pid_file")"
  if kill -0 "$pid" 2>/dev/null; then
    log_info "Stopping ${sid} (pid ${pid})..."
    kill "$pid" 2>/dev/null || true
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null && [[ $elapsed -lt 30 ]]; do
      sleep 1
      elapsed=$((elapsed + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      log_warn "Force killing ${sid}"
      kill -9 "$pid" 2>/dev/null || true
    fi
    log_ok "Stopped ${sid}"
  else
    log_warn "${sid} was not running"
  fi
  rm -f "$pid_file"
}

stop_kit() {
  local kit_id="$1"
  local session
  session="$(kit_session "$kit_id")"

  local velocity_servers=()
  local paper_servers=()
  local server_json

  while IFS= read -r server_json; do
    local stype sid
    stype="$(echo "$server_json" | jq -r '.type')"
    sid="$(echo "$server_json" | jq -r '.id')"
    case "$stype" in
      velocity) velocity_servers+=("$sid") ;;
      paper) paper_servers+=("$sid") ;;
    esac
  done < <(kit_servers "$kit_id")

  if tmux has-session -t "$session" 2>/dev/null; then
    local sid
    for sid in "${velocity_servers[@]}"; do
      stop_server_tmux "$kit_id" "$sid"
    done
    for sid in "${paper_servers[@]}"; do
      stop_server_tmux "$kit_id" "$sid"
    done
    tmux kill-session -t "$session" 2>/dev/null || true
  else
    local sid
    for sid in "${velocity_servers[@]}"; do
      stop_server_background "$kit_id" "$sid"
    done
    for sid in "${paper_servers[@]}"; do
      stop_server_background "$kit_id" "$sid"
    done
  fi

  log_ok "Kit '${kit_id}' stopped"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  stop_kit "${1:?kit_id}"
fi
