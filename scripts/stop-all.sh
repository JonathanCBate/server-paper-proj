#!/usr/bin/env bash
# Stop every kit, kill all mc-* tmux sessions, and free Minecraft ports.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/console.sh"

GRACEFUL=false

usage() {
  cat <<EOF
Usage: ./stop-all.sh [options]

Stop all Minecraft servers, kill mc-* tmux sessions, and free every port.

Options:
  --graceful   Send 'stop' to each server first (slower, saves worlds cleanly)
  -h, --help   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --graceful) GRACEFUL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

stop_all_servers() {
  log_info "Stopping all Minecraft servers..."

  if $GRACEFUL; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/stop-kit.sh"
    local kit kit_dir
    if [[ -d "$SERVERS_DIR" ]]; then
      for kit_dir in "${SERVERS_DIR}"/*/; do
        [[ -d "$kit_dir" ]] || continue
        kit="$(basename "$kit_dir")"
        [[ "$kit" == .* ]] && continue
        [[ -f "${KITS_DIR}/${kit}/kit.yml" ]] || continue
        stop_kit "$kit" || true
      done
    fi
  else
    stop_all_mc_tmux_sessions
    stop_all_port_listeners
    stop_orphan_server_java
    clear_server_pid_files
  fi

  # Final sweep in case anything is still listening
  stop_all_port_listeners
  stop_orphan_server_java

  local port still_busy=0
  while IFS= read -r port; do
    [[ -n "$port" ]] || continue
    if port_is_listening "$port"; then
      log_warn "Port ${port} is still in use:"
      describe_port_listeners "$port" | sed 's/^/  /'
      still_busy=1
    fi
  done < <(all_server_ports | sort -u)

  if (( still_busy )); then
    log_warn "Some ports are still busy — check the processes above"
    exit 1
  fi

  log_ok "All servers stopped and ports cleared"
}

stop_all_servers
