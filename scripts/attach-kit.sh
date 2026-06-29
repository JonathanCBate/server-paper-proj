#!/usr/bin/env bash
# Attach to a kit's server consoles (lists sessions or attaches to one server).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/console.sh"

kit_id="${1:?Usage: ./scripts/attach-kit.sh <kit> [server-id-or-name]}"

if [[ $# -ge 2 ]]; then
  local_query="$2"
  server_json="$(find_server_json "$kit_id" "$local_query")" || \
    die "Server '${local_query}' not found in kit '${kit_id}'"
  unique_name="$(server_unique_name "$kit_id" "$server_json")"
  attach_server_console "$unique_name"
fi

print_console_help "$kit_id"
