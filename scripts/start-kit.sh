#!/usr/bin/env bash
# Start all servers for a kit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/console.sh"

start_server_background() {
  local kit_id="$1"
  local server_json="$2"
  local sid stype sdir pid_file log_file

  sid="$(echo "$server_json" | jq -r '.id')"
  stype="$(echo "$server_json" | jq -r '.type')"
  sdir="$(server_dir "$kit_id" "$sid")"
  pid_file="${PID_DIR}/${kit_id}-${sid}.pid"
  log_file="${sdir}/logs/latest.log"

  ensure_dir "${sdir}/logs"
  ensure_dir "$PID_DIR"

  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    log_warn "${sid} is already running (pid $(cat "$pid_file"))"
    return 0
  fi

  log_info "Starting ${sid}..."
  (
    cd "$sdir"
    nohup java -Xms"${MEMORY}" -Xmx"${MEMORY}" -jar server.jar --nogui \
      >> "${sdir}/console.log" 2>&1 &
    echo $! > "$pid_file"
  )

  if [[ "$stype" == "paper" ]]; then
    wait_for_server_ready "$log_file" 240 || true
  else
    sleep 5
  fi

  log_ok "${sid} started (pid $(cat "$pid_file"))"
}

start_kit() {
  local kit_id="$1"
  local memory="${MEMORY:-2G}"
  MEMORY="$memory"

  local mode
  mode="$(resolve_console_mode)"

  local paper_servers=()
  local velocity_servers=()

  local server_json
  while IFS= read -r server_json; do
    local stype
    stype="$(echo "$server_json" | jq -r '.type')"
    case "$stype" in
      paper) paper_servers+=("$server_json") ;;
      velocity) velocity_servers+=("$server_json") ;;
    esac
  done < <(kit_servers "$kit_id")

  local entry
  for entry in "${paper_servers[@]}"; do
    if [[ "$mode" == "tmux" ]]; then
      start_server_tmux "$kit_id" "$entry"
      local sid log_file
      sid="$(echo "$entry" | jq -r '.id')"
      log_file="$(server_dir "$kit_id" "$sid")/logs/latest.log"
      wait_for_server_ready "$log_file" 240 || true
    else
      start_server_background "$kit_id" "$entry"
    fi
  done

  for entry in "${velocity_servers[@]}"; do
    if [[ "$mode" == "tmux" ]]; then
      start_server_tmux "$kit_id" "$entry"
      sleep 5
    else
      start_server_background "$kit_id" "$entry"
    fi
  done

  echo ""
  log_ok "Kit '${kit_id}' is running!"
  local connect_port
  connect_port="$(kit_manifest_json "$kit_id" | jq -r '[.servers[] | select(.type=="velocity" or .type=="paper")][0].port')"
  echo ""
  echo "  Connect: localhost:${connect_port}"
  if [[ "$mode" == "tmux" ]]; then
    print_console_help "$kit_id"
  else
    echo "  Logs:    ${SERVERS_DIR}/${kit_id}/<server>/console.log"
  fi
  echo "  Stop:    ./scripts/stop-kit.sh ${kit_id}"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  load_env
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tmux) CONSOLE_MODE=tmux; shift ;;
      --background) CONSOLE_MODE=background; shift ;;
      -h|--help)
        echo "Usage: ./scripts/start-kit.sh <kit> [--tmux|--background]"
        exit 0
        ;;
      -*) die "Unknown option: $1" ;;
      *) break ;;
    esac
  done
  start_kit "${1:?kit_id}"
fi
