#!/usr/bin/env bash
# Stop all servers and free Minecraft ports.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/stop-all.sh" "$@"
