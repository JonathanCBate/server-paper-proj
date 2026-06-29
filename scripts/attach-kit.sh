#!/usr/bin/env bash
# Attach to a kit's tmux console session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/console.sh"

kit_id="${1:?Usage: ./scripts/attach-kit.sh <kit> [server-id]}"

if ! has_tmux; then
  die "tmux is not installed. Install with: brew install tmux"
fi

session="$(kit_session "$kit_id")"

if ! tmux has-session -t "$session" 2>/dev/null; then
  die "No tmux session '${session}'. Start servers first: ./scripts/start-kit.sh ${kit_id}"
fi

if [[ $# -ge 2 ]]; then
  local_sid="$2"
  if ! server_window_running "$kit_id" "$local_sid"; then
    die "Window '${local_sid}' not found in session '${session}'"
  fi
  echo "Attaching to ${local_sid} (Ctrl-b d to detach)..."
  exec tmux attach -t "${session}:${local_sid}"
fi

print_console_help "$kit_id"
echo "Attaching to session ${session} (Ctrl-b d to detach)..."
exec tmux attach -t "$session"
