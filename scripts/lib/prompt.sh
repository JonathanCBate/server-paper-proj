#!/usr/bin/env bash
# Interactive wizard for setup.sh

# Read user input from the terminal (not a pipe opened by while-read loops).
read_prompt() {
  local prompt="$1"
  local varname="$2"
  if [[ -r /dev/tty ]]; then
    # shellcheck disable=SC2162
    read -r -p "$prompt" "$varname" </dev/tty
  else
    # shellcheck disable=SC2162
    read -r -p "$prompt" "$varname"
  fi
}

prompt_banner() {
  echo ""
  echo "  Minecraft Server Setup"
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
    read_prompt "  Enter choice [1-${#kits[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#kits[@]} )); then
      SELECTED_KIT="${kits[$((choice - 1))]}"
      break
    fi
    echo "  Invalid choice. Enter a number between 1 and ${#kits[@]}."
  done
}

prompt_server_names() {
  local kit_id="$SELECTED_KIT"
  local server_json sid stype default_name input name
  local -a used_names=()
  local names_file
  names_file="$(server_names_file "$kit_id")"

  ensure_dir "${SERVERS_DIR}/${kit_id}"

  echo ""
  echo "  Name your servers"
  echo "  (used for tmux consoles, LuckPerms, and ./scripts/attach-server.sh)"
  echo ""

  while IFS= read -r server_json || [[ -n "${server_json}" ]]; do
    [[ -z "$server_json" ]] && continue
    sid="$(echo "$server_json" | jq -r '.id')"
    stype="$(echo "$server_json" | jq -r '.type')"
    default_name="$(kit_default_server_name "$kit_id" "$server_json")"

    local existing
    existing="$(server_name_override "$kit_id" "$sid")"
    [[ -n "$existing" ]] && default_name="$existing"

    while true; do
      read_prompt "  ${stype} (${sid}) name [${default_name}]: " input
      name="${input:-$default_name}"

      if ! validate_server_name "$name"; then
        echo "  Invalid name. Use 1–32 characters: letters, numbers, hyphens (must start with a letter or number)."
        continue
      fi

      local lower_name
      lower_name="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
      local used lower_used
      for used in ${used_names[@]+"${used_names[@]}"}; do
        lower_used="$(echo "$used" | tr '[:upper:]' '[:lower:]')"
        if [[ "$lower_used" == "$lower_name" ]]; then
          echo "  Name '${name}' is already used by another server in this kit."
          continue 2
        fi
      done

      break
    done

    used_names+=("$name")
    save_server_name "$kit_id" "$sid" "$name"
  done < <(kit_servers "$kit_id")
}

prompt_mc_version() {
  local latest versions=() version input i
  latest="$(latest_stable_paper_version 2>/dev/null || echo "latest")"

  versions=()
  while IFS= read -r version || [[ -n "$version" ]]; do
    [[ -z "$version" ]] && continue
    versions+=("$version")
  done < <(papermc_release_versions paper 2>/dev/null || true)
  ((${#versions[@]} > 0)) || versions=("$latest")

  echo ""
  echo "  Minecraft version (from PaperMC):"
  echo ""
  printf "    [1] latest (%s)\n" "$latest"
  for i in "${!versions[@]}"; do
    printf "    [%d] %s\n" "$((i + 2))" "${versions[$i]}"
  done
  echo ""
  echo "  Enter a number, 'latest', or type a version (e.g. 1.18.2, 26.1.2)."
  echo "  Drop releases (26.x) need Java 25; 1.18.x needs Java 17."
  echo ""

  local default="${MC_VERSION:-latest}"
  if [[ "$default" == "latest" ]]; then
    default="latest (${latest})"
  fi

  while true; do
    read_prompt "  Choice [${default}]: " input
    if [[ -z "$input" ]]; then
      MC_VERSION="${MC_VERSION:-latest}"
      break
    fi
    if [[ "$input" == "latest" ]]; then
      MC_VERSION="latest"
      break
    fi
    if [[ "$input" =~ ^[0-9]+$ ]]; then
      if (( input == 1 )); then
        MC_VERSION="latest"
        break
      fi
      if (( input >= 2 && input <= ${#versions[@]} + 1 )); then
        MC_VERSION="${versions[$((input - 2))]}"
        break
      fi
      echo "  Invalid choice. Enter 1-${#versions[@]} plus 1, a version string, or 'latest'."
      continue
    fi
    MC_VERSION="$input"
    break
  done
}

prompt_memory() {
  local default="${MEMORY:-2G}"
  read_prompt "  Memory per server [${default}]: " input
  MEMORY="${input:-$default}"
}

prompt_action() {
  echo ""
  echo "  [1] Setup and start"
  echo "  [2] Setup only"
  echo ""
  local choice
  read_prompt "  Choose action [1]: " choice
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
  local server_json sid unique_name stype
  while IFS= read -r server_json || [[ -n "${server_json}" ]]; do
    [[ -z "$server_json" ]] && continue
    sid="$(echo "$server_json" | jq -r '.id')"
    stype="$(echo "$server_json" | jq -r '.type')"
    unique_name="$(server_unique_name "$SELECTED_KIT" "$server_json")"
    echo "            ${stype} ${sid} → ${unique_name}"
  done < <(kit_servers "$SELECTED_KIT")
  local display_version="${MC_VERSION}"
  if [[ "$display_version" == "latest" || -z "$display_version" ]]; then
    display_version="latest ($(latest_stable_paper_version 2>/dev/null || echo "?"))"
  fi
  echo "  Version:  ${display_version} (Java $(required_java_for_mc "$(latest_stable_paper_version 2>/dev/null || echo 1.21.11)"))"
  echo "  Memory:   ${MEMORY} per server"
  if $SETUP_ONLY; then
    echo "  Action:   setup only"
  else
    echo "  Action:   setup and start"
  fi
  echo ""
  local answer
  read_prompt "  Proceed? [Y/n]: " answer
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
  prompt_server_names
  prompt_mc_version
  prompt_memory
  prompt_action
  prompt_confirm
}
