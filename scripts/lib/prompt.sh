#!/usr/bin/env bash
# Interactive wizard for setup.sh

prompt_banner() {
  echo ""
  echo "  Paper Server Setup"
  echo "  ──────────────────"
  echo ""
}

prompt_kit() {
  local kits=()
  local descriptions=()
  local kit

  while IFS= read -r kit; do
    kits+=("$kit")
    descriptions+=("$(kit_field "$kit" description)")
  done < <(discover_kits)

  ((${#kits[@]} > 0)) || die "No kits found in ${KITS_DIR}"

  echo "  Choose a starter kit:"
  echo ""
  local i
  for i in "${!kits[@]}"; do
    printf "    [%d] %-18s — %s\n" "$((i + 1))" "${kits[$i]}" "${descriptions[$i]}"
  done
  echo ""

  local choice
  while true; do
    read -r -p "  Enter choice [1-${#kits[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#kits[@]} )); then
      SELECTED_KIT="${kits[$((choice - 1))]}"
      break
    fi
    echo "  Invalid choice. Enter a number between 1 and ${#kits[@]}."
  done
}

prompt_mc_version() {
  local latest
  latest="$(latest_stable_paper_version 2>/dev/null || echo "latest")"
  local default="${MC_VERSION:-latest}"
  if [[ "$default" == "latest" ]]; then
    default="latest (${latest})"
  fi
  echo ""
  echo "  Version format: 1.21.11 (legacy) or 26.1.2 (2026 drop releases)"
  echo "  Use 'latest' for the newest Paper build."
  echo ""
  read -r -p "  Minecraft version [${default}]: " input
  if [[ -z "$input" ]]; then
    MC_VERSION="${MC_VERSION:-latest}"
  else
    MC_VERSION="$input"
  fi
}

prompt_memory() {
  local default="${MEMORY:-2G}"
  read -r -p "  Memory per server [${default}]: " input
  MEMORY="${input:-$default}"
}

prompt_action() {
  echo ""
  echo "  [1] Setup and start"
  echo "  [2] Setup only"
  echo ""
  local choice
  read -r -p "  Choose action [1]: " choice
  case "${choice:-1}" in
    1) SETUP_ONLY=false ;;
    2) SETUP_ONLY=true ;;
    *) SETUP_ONLY=false ;;
  esac
}

prompt_confirm() {
  echo ""
  echo "  ── Summary ──"
  echo "  Kit:      ${SELECTED_KIT}"
  echo "  Version:  ${MC_VERSION}"
  echo "  Memory:   ${MEMORY} per server"
  if $SETUP_ONLY; then
    echo "  Action:   setup only"
  else
    echo "  Action:   setup and start"
  fi
  echo ""
  local answer
  read -r -p "  Proceed? [Y/n]: " answer
  case "${answer:-Y}" in
    [Yy]|[Yy][Ee][Ss]|"") return 0 ;;
    *) die "Setup cancelled." ;;
  esac
}

run_interactive_wizard() {
  prompt_banner
  require_cmd curl
  require_cmd jq
  load_env
  prompt_kit
  prompt_mc_version
  prompt_memory
  prompt_action
  prompt_confirm
}
