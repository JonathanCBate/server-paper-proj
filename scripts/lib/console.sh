#!/usr/bin/env bash
# Tmux-based attachable consoles — one session per unique server name.

set -euo pipefail

CONSOLE_MODE="${CONSOLE_MODE:-tmux}"

has_tmux() {
  command -v tmux >/dev/null 2>&1
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

server_session_running() {
  local unique_name="$1"
  local session
  session="$(server_session "$unique_name")"
  tmux has-session -t "$session" 2>/dev/null
}

start_server_tmux() {
  local kit_id="$1"
  local server_json="$2"
  local sid sdir unique_name session java_cmd sport stype

  sid="$(echo "$server_json" | jq -r '.id')"
  stype="$(echo "$server_json" | jq -r '.type')"
  unique_name="$(server_unique_name "$kit_id" "$server_json")"
  sdir="$(server_dir "$kit_id" "$sid")"
  session="$(server_session "$unique_name")"

  ensure_dir "${sdir}/logs"

  if server_session_running "$unique_name"; then
    log_warn "${unique_name} tmux session already exists — stopping it before restart"
    stop_server_tmux "$unique_name"
    sleep 2
  fi

  sport="$(echo "$server_json" | jq -r '.port')"
  if port_is_listening "$sport"; then
    log_warn "Port ${sport} in use — freeing it for ${unique_name}"
    kill_port_listeners "$sport"
    sleep 2
  fi

  ensure_port_available "$sport" "$unique_name"

  java_cmd="$(server_java_cmd "$stype")"

  log_info "Starting '${unique_name}' in tmux session '${session}'..."
  tmux new-session -d -s "$session" -n "$unique_name" -c "$sdir"
  tmux send-keys -t "$session" "$java_cmd" Enter
}

stop_server_tmux() {
  local unique_name="$1"
  local session
  session="$(server_session "$unique_name")"

  if ! server_session_running "$unique_name"; then
    log_warn "No tmux session for '${unique_name}', skipping"
    return 0
  fi

  log_info "Stopping ${unique_name} (sending 'stop' to console)..."
  tmux send-keys -t "$session" "stop" Enter

  local elapsed=0
  while server_session_running "$unique_name" && [[ $elapsed -lt 60 ]]; do
    sleep 2
    elapsed=$((elapsed + 2))
  done

  if server_session_running "$unique_name"; then
    log_warn "Force killing tmux session for ${unique_name}"
    tmux kill-session -t "$session" 2>/dev/null || true
  else
    log_ok "Stopped ${unique_name}"
  fi
}

print_console_help() {
  local kit_id="$1"
  local server_json unique_name session

  echo ""
  echo "  Live consoles (one tmux session per server):"
  echo ""
  while IFS= read -r server_json; do
    unique_name="$(server_unique_name "$kit_id" "$server_json")"
    session="$(server_session "$unique_name")"
    echo "    ${unique_name}"
    echo "      attach:  ./scripts/attach-server.sh ${unique_name}"
    echo "      or:      tmux attach -t ${session}"
    echo ""
  done < <(kit_servers "$kit_id")
  echo "  Detach from any console: Ctrl-b d"
  echo ""
}

attach_server_console() {
  local unique_name="$1"
  local session
  session="$(server_session "$unique_name")"

  if ! has_tmux; then
    die "tmux is not installed. Install with: brew install tmux"
  fi

  if ! server_session_running "$unique_name"; then
    die "No tmux session '${session}'. Is '${unique_name}' running?"
  fi

  echo "Attaching to ${unique_name} (Ctrl-b d to detach)..."
  exec tmux attach -t "$session"
}
