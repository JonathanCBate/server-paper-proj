#!/usr/bin/env bash
# Attach to a single server's tmux console by its unique name.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/console.sh"

attach_server_console "${1:?Usage: ./scripts/attach-server.sh <server-name>}"
