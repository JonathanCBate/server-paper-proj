#!/usr/bin/env bash
# One-command Paper server setup — interactive wizard or direct kit selection.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/prompt.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/apply-kit.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/start-kit.sh"

SETUP_ONLY=false
SKIP_EULA=false
SELECTED_KIT=""

usage() {
  cat <<EOF
Usage: ./setup.sh [kit] [options]

Interactive (no arguments):
  ./setup.sh                  Run the setup wizard

Non-interactive:
  ./setup.sh paper-basic
  ./setup.sh fabric-basic
  ./setup.sh velocity-multi --setup-only
  ./setup.sh fabric-basic --memory 4G --mc-version 26.1.2

Options:
  --setup-only       Download and configure without starting servers
  --mc-version VER   Minecraft version or 'latest' (default: latest)
  --memory MEM       JVM heap per server (default: 2G)
  --tmux             Start servers in tmux windows (default)
  --background       Start servers in background without tmux
  --no-eula          Skip writing eula=true (not recommended)
  -h, --help         Show this help

Kits:
$(discover_kits | sed 's/^/  /')
EOF
}

parse_args() {
  local positional=()
  load_env
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --setup-only) SETUP_ONLY=true; shift ;;
      --no-eula) SKIP_EULA=true; shift ;;
      --mc-version) MC_VERSION="$2"; shift 2 ;;
      --memory) MEMORY="$2"; shift 2 ;;
      --tmux) CONSOLE_MODE=tmux; shift ;;
      --background) CONSOLE_MODE=background; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) die "Unknown option: $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  if ((${#positional[@]} > 0)); then
    SELECTED_KIT="${positional[0]}"
    require_cmd curl
    require_cmd jq
    [[ -f "${KITS_DIR}/${SELECTED_KIT}/kit.yml" ]] || die "Unknown kit: ${SELECTED_KIT}"
  fi
}

main() {
  parse_args "$@"

  if [[ -z "$SELECTED_KIT" ]]; then
    run_interactive_wizard
  fi

  resolve_mc_version
  resolve_velocity_version
  require_java_for_mc "$MC_VERSION"
  save_env_file
  export MC_VERSION MEMORY VELOCITY_VERSION CONSOLE_MODE
  log_info "Setting up kit: ${SELECTED_KIT} (MC ${MC_VERSION}, ${MEMORY}/server)"
  apply_kit "$SELECTED_KIT"

  if $SETUP_ONLY; then
    log_ok "Setup complete. Start with: ./scripts/start-kit.sh ${SELECTED_KIT}"
    exit 0
  fi

  start_kit "$SELECTED_KIT"
}

main "$@"
