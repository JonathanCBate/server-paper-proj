#!/usr/bin/env bash
# Tmux-based attachable consoles for server processes.

set -euo pipefail

CONSOLE_MODE="${CONSOLE_MODE:-tmux}"

has_tmux() {
  command -v tmux >/dev/null 2>&1
}

kit_session() {
  echo "mc-${1}"
}

resolve_console_mode() {
  case "${CONSOLE_MODE}" in
    tmux)
      if has_tmux; then
        echo tmux
      else
        log_warn "tmux not found — falling back to background mode (logs in console.log)"
        echo background
      fi
      ;;
    background) echo background ;;
    *) die "Unknown CONSOLE_MODE: ${CONSOLE_MODE} (use 'tmux' or 'background')" ;;
  esac
}

server_window_running() {
  local kit_id="$1"
  local sid="$2"
  local session
  session="$(kit_session "$kit_id")"
  tmux has-session -t "$session" 2>/dev/null || return 1
  tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -qx "$sid"
}

start_server_tmux() {
  local kit_id="$1"
  local server_json="$2"
  local sid sdir session java_cmd

  sid="$(echo "$server_json" | jq -r '.id')"
  sdir="$(server_dir "$kit_id" "$sid")"
  session="$(kit_session "$kit_id")"

  ensure_dir "${sdir}/logs"

  if server_window_running "$kit_id" "$sid"; then
    log_warn "${sid} is already running in tmux window '${sid}'"
    return 0
  fi

  java_cmd="java -Xms${MEMORY} -Xmx${MEMORY} -jar server.jar --nogui 2>&1 | tee -a console.log"

  log_info "Starting ${sid} in tmux window '${sid}'..."

  if tmux has-session -t "$session" 2>/dev/null; then
    tmux new-window -t "$session" -n "$sid" -c "$sdir"
    tmux send-keys -t "${session}:${sid}" "$java_cmd" Enter
  else
    tmux new-session -d -s "$session" -n "$sid" -c "$sdir"
    tmux send-keys -t "${session}:${sid}" "$java_cmd" Enter
  fi

  log_ok "${sid} started in tmux"
}

stop_server_tmux() {
  local kit_id="$1"
  local sid="$2"
  local session
  session="$(kit_session "$kit_id")"

  if ! server_window_running "$kit_id" "$sid"; then
    log_warn "${sid} tmux window not found, skipping"
    return 0
  fi

  log_info "Stopping ${sid} (sending 'stop' to console)..."
  tmux send-keys -t "${session}:${sid}" "stop" Enter

  local elapsed=0
  while server_window_running "$kit_id" "$sid" && [[ $elapsed -lt 60 ]]; do
    sleep 2
    elapsed=$((elapsed + 2))
  done

  if server_window_running "$kit_id" "$sid"; then
    log_warn "Force closing tmux window for ${sid}"
    tmux kill-window -t "${session}:${sid}" 2>/dev/null || true
  else
    log_ok "Stopped ${sid}"
  fi
}

cleanup_kit_session() {
  local kit_id="$1"
  local session
  session="$(kit_session "$kit_id")"
  if tmux has-session -t "$session" 2>/dev/null; then
    local count
    count="$(tmux list-windows -t "$session" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$count" -eq 0 ]]; then
      tmux kill-session -t "$session" 2>/dev/null || true
    fi
  fi
}

print_console_help() {
  local kit_id="$1"
  local session
  session="$(kit_session "$kit_id")"

  echo ""
  echo "  Live consoles (tmux):"
  echo "    Attach all:     ./scripts/attach-kit.sh ${kit_id}"
  echo "    Or:             tmux attach -t ${session}"
  echo ""
  echo "  Inside tmux:"
  echo "    Switch server:  Ctrl-b then window number (0, 1, 2...)"
  echo "    Next window:    Ctrl-b n"
  echo "    Previous:       Ctrl-b p"
  echo "    Detach:         Ctrl-b d   (servers keep running)"
  echo ""
  local sid
  while IFS= read -r sid; do
    echo "    ${sid}:  tmux attach -t ${session}:${sid}"
  done < <(kit_servers "$kit_id" | jq -r '.id')
  echo ""
}
