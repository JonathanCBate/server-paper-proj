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
  local server_json unique_name

  log_info "Stopping kit '${kit_id}'..."

  while IFS= read -r server_json || [[ -n "${server_json}" ]]; do
    [[ -z "$server_json" ]] && continue
    unique_name="$(server_unique_name "$kit_id" "$server_json")"
    if server_session_running "$unique_name"; then
      stop_server_tmux "$unique_name"
    fi
  done < <(kit_servers "$kit_id")

  # Kill any leftover Java listeners on this kit's ports (e.g. old folder names)
  stop_kit_port_listeners "$kit_id"

  local velocity_servers=()
  local backend_servers=()
  local sid stype

  while IFS= read -r server_json || [[ -n "${server_json}" ]]; do
    [[ -z "$server_json" ]] && continue
    stype="$(echo "$server_json" | jq -r '.type')"
    sid="$(echo "$server_json" | jq -r '.id')"
    case "$stype" in
      velocity) velocity_servers+=("$sid") ;;
      paper|fabric) backend_servers+=("$sid") ;;
    esac
  done < <(kit_servers "$kit_id")

  for sid in ${velocity_servers[@]+"${velocity_servers[@]}"} ${backend_servers[@]+"${backend_servers[@]}"}; do
    stop_server_background "$kit_id" "$sid"
  done

  log_ok "Kit '${kit_id}' stopped"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  stop_kit "${1:?kit_id}"
fi
