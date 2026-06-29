#!/usr/bin/env bash
# Shared utilities for paper server setup scripts.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KITS_DIR="${ROOT_DIR}/kits"
SERVERS_DIR="${ROOT_DIR}/servers"
SHARED_DIR="${KITS_DIR}/_shared"
PID_DIR="${SERVERS_DIR}/.pids"

log_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
log_ok()    { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

die() {
  log_error "$@"
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

JAVA_BIN=""

java_major() {
  local bin="$1"
  local version_line major
  version_line="$("$bin" -version 2>&1 | head -n1)"
  major="$(echo "$version_line" | sed -n 's/.*version "\([0-9]*\).*/\1/p')"
  if [[ -z "$major" ]]; then
    major="$(echo "$version_line" | sed -n 's/.*version "1\.\([0-9]*\).*/\1/p')"
  fi
  echo "$major"
}

java_meets_requirement() {
  local bin="$1" min_major="$2" major
  major="$(java_major "$bin")"
  [[ -n "$major" && "$major" -ge "$min_major" ]]
}

brew_java_bin() {
  local major="$1"
  local prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
  local bin="${prefix}/opt/openjdk@${major}/bin/java"
  [[ -x "$bin" ]] && echo "$bin"
}

java_install_hint() {
  local min_major="$1"
  echo "Install Java ${min_major}+: brew install openjdk@${min_major}" >&2
  echo "Then re-run setup, or add to your shell profile:" >&2
  echo "  export PATH=\"\$(brew --prefix openjdk@${min_major})/bin:\$PATH\"" >&2
}

resolve_java_bin() {
  local min_major="$1"
  local candidates=() bin major_home prefix

  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    candidates+=("${JAVA_HOME}/bin/java")
  fi

  if command -v java >/dev/null 2>&1; then
    candidates+=("$(command -v java)")
  fi

  for bin in 25 21 17 11 8; do
    if (( bin >= min_major )); then
      brew_java_bin "$bin" && candidates+=("$(brew_java_bin "$bin")")
    fi
  done

  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    major_home="$(/usr/libexec/java_home -v "${min_major}" 2>/dev/null || true)"
    [[ -n "$major_home" && -x "${major_home}/bin/java" ]] && candidates+=("${major_home}/bin/java")
  fi

  prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
  [[ -x "${prefix}/opt/openjdk/bin/java" ]] && candidates+=("${prefix}/opt/openjdk/bin/java")

  local seen="" candidate
  for candidate in "${candidates[@]}"; do
    [[ -z "$candidate" || ! -x "$candidate" ]] && continue
    [[ " ${seen} " == *" ${candidate} "* ]] && continue
    seen="${seen} ${candidate}"
    if java_meets_requirement "$candidate" "$min_major"; then
      JAVA_BIN="$candidate"
      return 0
    fi
  done
  return 1
}

require_java() {
  local min_major="${1:-21}"
  local version_line="not found"

  if resolve_java_bin "$min_major"; then
    log_info "Using Java $(java_major "$JAVA_BIN") (${JAVA_BIN})"
    return 0
  fi

  if command -v java >/dev/null 2>&1; then
    version_line="$(java -version 2>&1 | head -n1)"
  fi
  log_error "Java ${min_major}+ required for this Minecraft version (found: ${version_line})"
  java_install_hint "$min_major"
  exit 1
}

server_java_bin() {
  echo "${JAVA_BIN:-java}"
}

# Minecraft 2026+ drop versioning: 26.1, 26.1.1, 26.1.2 (year.drop.patch)
# Legacy versioning: 1.21.11, 1.21.1, etc.
is_drop_version() {
  [[ "${1:-}" =~ ^[0-9]{2}\.[0-9] ]]
}

required_java_for_mc() {
  local mc_version="$1"
  if is_drop_version "$mc_version"; then
    echo 25
    return
  fi
  local minor patch
  minor="$(echo "$mc_version" | sed -n 's/^1\.\([0-9]*\)\..*/\1/p')"
  patch="$(echo "$mc_version" | sed -n 's/^1\.[0-9]*\.\([0-9]*\).*/\1/p')"
  if [[ -n "$minor" ]]; then
    if (( minor < 20 )); then
      echo 17
      return
    fi
    if (( minor == 20 && patch < 5 )); then
      echo 17
      return
    fi
  fi
  echo 21
}

PAPERMC_FILL_API="https://fill.papermc.io/v3"
FABRIC_META_API="https://meta.fabricmc.net/v2"

is_backend_server() {
  [[ "${1:-}" == "paper" || "${1:-}" == "fabric" ]]
}

papermc_fill_versions_json() {
  local project="${1:-paper}"
  curl -fsSL "${PAPERMC_FILL_API}/projects/${project}/versions"
}

papermc_fill_project_json() {
  local project="${1:-paper}"
  curl -fsSL "${PAPERMC_FILL_API}/projects/${project}"
}

# All release versions (no pre/rc/snapshot), newest first.
papermc_release_versions() {
  local project="${1:-paper}"
  papermc_fill_versions_json "$project" | \
    jq -r '[.versions[] | select(.version.id | test("pre|rc|snapshot"; "i") | not)] | .[].version.id'
}

latest_stable_paper_version() {
  local supported
  supported="$(papermc_fill_versions_json paper | \
    jq -r '[.versions[] | select(.version.support.status == "SUPPORTED" and (.version.id | test("pre|rc|snapshot"; "i") | not))] | .[0].version.id')"
  if [[ -n "$supported" && "$supported" != "null" ]]; then
    echo "$supported"
    return
  fi
  papermc_release_versions paper | head -1
}

latest_stable_velocity_version() {
  local supported
  supported="$(papermc_fill_versions_json velocity | \
    jq -r '[.versions[] | select(.version.support.status == "SUPPORTED" and (.version.id | test("pre|rc|snapshot"; "i") | not))] | .[0].version.id')"
  if [[ -n "$supported" && "$supported" != "null" ]]; then
    echo "$supported"
    return
  fi
  papermc_release_versions velocity | head -1
}

# Velocity 3.4.x only accepts clients through 1.21.11. Drop releases (26.x) need 3.5+.
velocity_version_for_mc() {
  local mc_version="$1"
  if is_drop_version "$mc_version"; then
    echo "3.5.0-SNAPSHOT"
    return
  fi
  latest_stable_velocity_version
}

velocity_supports_mc() {
  local velocity_ver="$1" mc_version="$2"
  if is_drop_version "$mc_version"; then
    [[ "$velocity_ver" == 3.5.* || "$velocity_ver" == *SNAPSHOT* ]]
    return
  fi
  return 0
}

resolve_velocity_version() {
  local required
  required="$(velocity_version_for_mc "${MC_VERSION:-latest}")"

  if [[ -n "${VELOCITY_VERSION:-}" ]]; then
    if velocity_supports_mc "$VELOCITY_VERSION" "${MC_VERSION:-latest}"; then
      return 0
    fi
    log_warn "VELOCITY_VERSION=${VELOCITY_VERSION} cannot accept MC ${MC_VERSION} clients — switching to ${required}"
  fi

  VELOCITY_VERSION="$required"
  if [[ "$VELOCITY_VERSION" == *SNAPSHOT* ]]; then
    log_info "Using Velocity ${VELOCITY_VERSION} (required for Minecraft ${MC_VERSION} clients)"
  fi
}

jar_paper_version() {
  local jar="$1"
  unzip -p "$jar" version.json 2>/dev/null | jq -r '.id // empty'
}

jar_velocity_version() {
  local jar="$1"
  unzip -p "$jar" META-INF/MANIFEST.MF 2>/dev/null | \
    sed -n 's/Implementation-Version: \(.*\)/\1/p' | head -1 | tr -d '\r'
}

verify_kit_versions() {
  local kit_id="$1"
  local server_json stype sdir jar paper_ver velocity_ver
  local errors=0

  resolve_mc_version
  resolve_velocity_version

  while IFS= read -r server_json || [[ -n "${server_json}" ]]; do
    [[ -z "$server_json" ]] && continue
    stype="$(echo "$server_json" | jq -r '.type')"
    sdir="$(server_dir_from_json "$kit_id" "$server_json")"
    jar="${sdir}/server.jar"
    local unique_name
    unique_name="$(server_unique_name "$kit_id" "$server_json")"

    [[ -f "$jar" ]] || { log_error "${unique_name}: missing server.jar — run ./setup.sh ${kit_id} --setup-only"; errors=$((errors + 1)); continue; }

    case "$stype" in
      paper)
        paper_ver="$(jar_paper_version "$jar")"
        if [[ "$paper_ver" != "$MC_VERSION" ]]; then
          log_error "${unique_name}: Paper is ${paper_ver}, expected ${MC_VERSION}"
          errors=$((errors + 1))
        else
          log_ok "${unique_name}: Paper ${paper_ver}"
        fi
        ;;
      fabric)
        [[ -f "$jar" ]] || { log_error "${unique_name}: missing server.jar"; errors=$((errors + 1)); continue; }
        if [[ ! -d "${sdir}/mods" ]] || ! ls "${sdir}"/mods/*.jar >/dev/null 2>&1; then
          log_error "${unique_name}: no Fabric mods installed"
          errors=$((errors + 1))
        else
          log_ok "${unique_name}: Fabric ${MC_VERSION} ($(ls "${sdir}"/mods/*.jar 2>/dev/null | wc -l | tr -d ' ') mods)"
        fi
        ;;
      velocity)
        velocity_ver="$(jar_velocity_version "$jar")"
        if ! velocity_supports_mc "${velocity_ver%% *}" "${MC_VERSION}"; then
          log_error "${unique_name}: Velocity ${velocity_ver} cannot accept MC ${MC_VERSION} clients (need 3.5.0-SNAPSHOT+)"
          errors=$((errors + 1))
        else
          log_ok "${unique_name}: Velocity ${velocity_ver}"
        fi
        local vtoml="${sdir}/velocity.toml"
        if [[ -f "$vtoml" ]] && grep -q 'ping-passthrough = "DISABLED"' "$vtoml"; then
          log_warn "${unique_name}: ping-passthrough is DISABLED — server list may show 1.21.11"
          errors=$((errors + 1))
        fi
        ;;
    esac
  done < <(kit_servers "$kit_id")

  if (( errors > 0 )); then
    die "Version check failed for kit '${kit_id}'. Re-run: ./setup.sh ${kit_id} --setup-only"
  fi
}

papermc_version_exists() {
  local project="$1" version="$2"
  papermc_fill_project_json "$project" | \
    jq -e --arg v "$version" '[.versions | to_entries[] | .value[]] | index($v)' >/dev/null
}

resolve_mc_version() {
  local requested="${MC_VERSION:-latest}"

  if [[ "$requested" == "latest" || -z "$requested" ]]; then
    MC_VERSION="$(latest_stable_paper_version)"
    log_info "Using latest Paper version: ${MC_VERSION}"
    return 0
  fi

  if papermc_version_exists paper "$requested"; then
    MC_VERSION="$requested"
    return 0
  fi

  local latest drop_versions legacy_versions
  latest="$(latest_stable_paper_version)"
  drop_versions="$(papermc_release_versions paper | grep -E '^[0-9]{2}\.' | tr '\n' ', ' | sed 's/, $//')"
  legacy_versions="$(papermc_release_versions paper | grep -E '^1\.' | head -5 | tr '\n' ', ' | sed 's/, $//')"

  log_error "Minecraft version '${requested}' is not available from PaperMC."
  echo "" >&2
  if is_drop_version "$requested"; then
    echo "  '${requested}' uses the new drop versioning scheme (YY.DROP.PATCH)." >&2
    echo "  Example: 26.1 = first 2026 drop, 26.1.2 = second hotfix." >&2
    echo "  Available drop versions: ${drop_versions:-none}" >&2
  else
    echo "  Recent legacy versions (1.x): ${legacy_versions}" >&2
  fi
  echo "" >&2
  echo "  Latest supported: ${latest}" >&2
  echo "  Set MC_VERSION=latest in .env or run: ./setup.sh <kit> --mc-version latest" >&2
  exit 1
}

require_java_for_mc() {
  require_java "$(required_java_for_mc "$1")"
}

ensure_env_file() {
  local env_file="${ROOT_DIR}/.env"
  local example="${ROOT_DIR}/.env.example"

  if [[ -f "$env_file" ]]; then
    return 0
  fi

  if [[ -f "$example" ]]; then
    grep -v '^#' "$example" | sed '/^[[:space:]]*$/d' > "$env_file"
  else
    cat > "$env_file" <<'EOF'
MC_VERSION=latest
VELOCITY_VERSION=
MEMORY=2G
CONSOLE_MODE=tmux
EOF
  fi
  log_info "Created ${env_file}"
}

save_env_file() {
  local env_file="${ROOT_DIR}/.env"
  cat > "$env_file" <<EOF
# Auto-generated by setup.sh — edit to change defaults for future runs
MC_VERSION=${MC_VERSION}
VELOCITY_VERSION=${VELOCITY_VERSION:-}
MEMORY=${MEMORY}
CONSOLE_MODE=${CONSOLE_MODE:-tmux}
EOF
}

load_env() {
  ensure_env_file
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source "${ROOT_DIR}/.env"
    set +a
  fi
  MC_VERSION="${MC_VERSION:-latest}"
  VELOCITY_VERSION="${VELOCITY_VERSION:-}"
  MEMORY="${MEMORY:-2G}"
  CONSOLE_MODE="${CONSOLE_MODE:-tmux}"
}

yaml_to_json() {
  local file="$1"
  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' "$file" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; import yaml' 2>/dev/null && \
      python3 -c 'import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$file" || \
      die "Install ruby or python3 with PyYAML to parse kit manifests"
  else
    die "Install ruby or python3 to parse kit manifests"
  fi
}

discover_kits() {
  local kit
  for kit_dir in "${KITS_DIR}"/*/; do
    kit="$(basename "$kit_dir")"
    [[ "$kit" == "_shared" ]] && continue
    [[ -f "${kit_dir}/kit.yml" ]] && echo "$kit"
  done | sort
}

kit_manifest_json() {
  local kit_id="$1"
  local manifest="${KITS_DIR}/${kit_id}/kit.yml"
  [[ -f "$manifest" ]] || die "Kit manifest not found: $manifest"
  yaml_to_json "$manifest"
}

kit_field() {
  local kit_id="$1"
  local field="$2"
  kit_manifest_json "$kit_id" | jq -r ".$field"
}

kit_servers() {
  local kit_id="$1"
  kit_manifest_json "$kit_id" | jq -c '.servers[]'
}

server_dir() {
  local kit_id="$1"
  local server_id="$2"
  local server_json
  server_json="$(find_server_json "$kit_id" "$server_id")" || \
    die "Unknown server '${server_id}' in kit '${kit_id}'"
  echo "${SERVERS_DIR}/${kit_id}/$(server_unique_name "$kit_id" "$server_json")"
}

server_dir_from_json() {
  local kit_id="$1"
  local server_json="$2"
  echo "${SERVERS_DIR}/${kit_id}/$(server_unique_name "$kit_id" "$server_json")"
}

# Unique name for a server instance (used for tmux sessions, LuckPerms, etc.)
server_unique_name() {
  local kit_id="$1"
  local server_json="$2"
  local name sid override
  sid="$(echo "$server_json" | jq -r '.id')"

  override="$(server_name_override "$kit_id" "$sid")"
  if [[ -n "$override" ]]; then
    echo "$override"
    return
  fi

  name="$(echo "$server_json" | jq -r '.name // empty')"
  if [[ -n "$name" ]]; then
    echo "$name"
  else
    echo "${kit_id}-${sid}"
  fi
}

server_names_file() {
  echo "${SERVERS_DIR}/${1}/.server-names.json"
}

server_name_override() {
  local kit_id="$1"
  local sid="$2"
  local file
  file="$(server_names_file "$kit_id")"
  [[ -f "$file" ]] || return 0
  jq -r --arg sid "$sid" '.[$sid] // empty' "$file"
}

save_server_name() {
  local kit_id="$1"
  local sid="$2"
  local name="$3"
  local file tmp
  file="$(server_names_file "$kit_id")"
  ensure_dir "$(dirname "$file")"
  if [[ -f "$file" ]]; then
    tmp="$(mktemp)"
    jq --arg sid "$sid" --arg name "$name" '. + {($sid): $name}' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    jq -n --arg sid "$sid" --arg name "$name" '{($sid): $name}' > "$file"
  fi
}

validate_server_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,31}$ ]]
}

kit_default_server_name() {
  local kit_id="$1"
  local server_json="$2"
  local name sid
  name="$(echo "$server_json" | jq -r '.name // empty')"
  sid="$(echo "$server_json" | jq -r '.id')"
  if [[ -n "$name" ]]; then
    echo "$name"
  else
    echo "${kit_id}-${sid}"
  fi
}

sanitize_session_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

server_session() {
  echo "mc-$(sanitize_session_name "$1")"
}

find_server_json() {
  local kit_id="$1"
  local query="$2"
  local server_json unique_name sid
  while IFS= read -r server_json || [[ -n "${server_json}" ]]; do
    [[ -z "$server_json" ]] && continue
    unique_name="$(server_unique_name "$kit_id" "$server_json")"
    sid="$(echo "$server_json" | jq -r '.id')"
    if [[ "$query" == "$sid" || "$query" == "$unique_name" ]]; then
      echo "$server_json"
      return 0
    fi
  done < <(kit_servers "$kit_id")
  return 1
}

# Paper accepts --nogui; Velocity does not.
server_jar_args() {
  local stype="$1"
  is_backend_server "$stype" && echo "--nogui"
}

server_java_cmd() {
  local stype="$1"
  local nogui=""
  local java_bin
  nogui="$(server_jar_args "$stype")"
  java_bin="$(server_java_bin)"
  echo "${java_bin} -Xms${MEMORY} -Xmx${MEMORY} -jar server.jar ${nogui} 2>&1 | tee -a console.log"
}

port_is_listening() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
}

port_listener_pids() {
  local port="$1"
  lsof -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
}

describe_port_listeners() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
}

kill_port_listeners() {
  local port="$1"
  local pid
  for pid in $(port_listener_pids "$port"); do
    [[ -n "$pid" ]] || continue
    log_info "Stopping process on port ${port} (pid ${pid})..."
    kill "$pid" 2>/dev/null || true
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null && [[ $elapsed -lt 15 ]]; do
      sleep 1
      elapsed=$((elapsed + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
}

kit_server_ports() {
  local kit_id="$1"
  kit_servers "$kit_id" | jq -r '.port'
}

stop_kit_port_listeners() {
  local kit_id="$1"
  local port
  while IFS= read -r port; do
    [[ -n "$port" ]] || continue
    if port_is_listening "$port"; then
      kill_port_listeners "$port"
    fi
  done < <(kit_server_ports "$kit_id")
}

# All Minecraft ports from kit manifests and deployed server.properties files.
all_server_ports() {
  local kit port
  for kit in $(discover_kits); do
    while IFS= read -r port; do
      [[ -n "$port" ]] && echo "$port"
    done < <(kit_server_ports "$kit" 2>/dev/null || true)
  done
  if [[ -d "$SERVERS_DIR" ]]; then
    while IFS= read -r port; do
      [[ -n "$port" ]] && echo "$port"
    done < <(grep -rh '^server-port=' "${SERVERS_DIR}"/*/server.properties "${SERVERS_DIR}"/*/*/server.properties 2>/dev/null \
      | sed 's/server-port=//' || true)
  fi
}

stop_all_mc_tmux_sessions() {
  command -v tmux >/dev/null 2>&1 || return 0
  local session
  while IFS= read -r session; do
    [[ -z "$session" ]] && continue
    log_info "Stopping tmux session ${session}..."
    tmux kill-session -t "$session" 2>/dev/null || true
  done < <(tmux list-sessions -F '#S' 2>/dev/null | grep '^mc-' || true)
}

stop_all_port_listeners() {
  local port
  while IFS= read -r port; do
    [[ -n "$port" ]] || continue
    if port_is_listening "$port"; then
      kill_port_listeners "$port"
    fi
  done < <(all_server_ports | sort -u)
}

stop_orphan_server_java() {
  local pid cwd
  for pid in $(pgrep -x java 2>/dev/null || true); do
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1 || true)"
    [[ -n "$cwd" && "$cwd" == "${SERVERS_DIR}/"* && -f "${cwd}/server.jar" ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      log_info "Stopping orphan server java (pid ${pid}) in ${cwd}..."
      kill "$pid" 2>/dev/null || true
      local elapsed=0
      while kill -0 "$pid" 2>/dev/null && [[ $elapsed -lt 15 ]]; do
        sleep 1
        elapsed=$((elapsed + 1))
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
}

clear_server_pid_files() {
  [[ -d "$PID_DIR" ]] || return 0
  rm -f "${PID_DIR}"/*.pid 2>/dev/null || true
}

ensure_port_available() {
  local port="$1"
  local server_name="$2"
  if ! port_is_listening "$port"; then
    return 0
  fi
  log_error "Port ${port} is already in use (needed for '${server_name}')"
  describe_port_listeners "$port" | sed 's/^/  /'
  echo ""
  die "Stop existing servers first: ./stop-all.sh"
}

ensure_dir() {
  mkdir -p "$1"
}

generate_forwarding_secret() {
  local secret_file="${SERVERS_DIR}/.forwarding.secret"
  if [[ -f "$secret_file" ]]; then
    cat "$secret_file"
    return
  fi
  require_cmd openssl
  local secret
  secret="$(openssl rand -hex 16)"
  ensure_dir "$(dirname "$secret_file")"
  echo "$secret" > "$secret_file"
  echo "$secret"
}

write_eula() {
  local dir="$1"
  echo "eula=true" > "${dir}/eula.txt"
}

render_luckperms_template() {
  local template="$1"
  local dest="$2"
  local server_name="$3"
  local db_path="${4:-}"
  sed -e "s|{{SERVER_NAME}}|${server_name}|g" \
      -e "s|{{LP_DB_PATH}}|${db_path}|g" \
      "$template" > "$dest"
}

configure_luckperms() {
  local kit_id="$1"
  local server_id="$2"
  local server_name="$3"
  local network_sync="$4"
  local sdir
  sdir="$(server_dir "$kit_id" "$server_id")"
  local config_dir="${sdir}/plugins/LuckPerms"
  local config_file="${config_dir}/config.yml"

  [[ -d "${sdir}/plugins" ]] || return 0

  ensure_dir "$config_dir"

  if [[ "$network_sync" == "true" ]]; then
    local db_dir="${SERVERS_DIR}/${kit_id}/.luckperms"
    local db_path="${db_dir}/luckperms"
    ensure_dir "$db_dir"
    render_luckperms_template \
      "${SHARED_DIR}/plugin-configs/LuckPerms/config-network.yml.template" \
      "$config_file" \
      "$server_name" \
      "$db_path"
    log_info "LuckPerms network sync enabled for ${server_name} (shared DB + pluginmsg)"
  else
    render_luckperms_template \
      "${SHARED_DIR}/plugin-configs/LuckPerms/config-standalone.yml.template" \
      "$config_file" \
      "$server_name"
    log_info "LuckPerms standalone config for ${server_name}"
  fi
}


default_voice_port() {
  local mc_port="$1"
  # Unique UDP port per backend: 25566→24454, 25567→24455, etc.
  echo $((24454 + mc_port - 25566))
}

voicechat_installed() {
  local sdir="$1" f
  for f in "${sdir}/mods/"*voicechat* "${sdir}/plugins/"SimpleVoiceChat* "${sdir}/plugins/"*voicechat*; do
    [[ -e "$f" ]] && return 0
  done
  return 1
}

configure_voicechat() {
  local sdir="$1"
  local mc_port="$2"
  local voice_port template dest

  voicechat_installed "$sdir" || return 0

  voice_port="$(default_voice_port "$mc_port")"
  template="${SHARED_DIR}/voicechat/voicechat-server.properties.template"

  local found=0
  while IFS= read -r -d '' dest; do
    found=1
    sed -i.bak "s/^port=.*/port=${voice_port}/" "$dest"
    rm -f "${dest}.bak"
    log_info "Voice chat UDP port ${voice_port} → ${dest#${sdir}/}"
  done < <(find "$sdir" -path '*/voicechat/voicechat-server.properties' -print0 2>/dev/null)

  if (( found == 0 )) && [[ -f "$template" ]]; then
    dest="${sdir}/config/voicechat/voicechat-server.properties"
    ensure_dir "$(dirname "$dest")"
    render_template "$template" "$dest" "" "" "$mc_port"
    log_info "Voice chat UDP port ${voice_port} → config/voicechat/voicechat-server.properties"
  fi
}

render_template() {
  local src="$1"
  local dest="$2"
  local secret="${3:-}"
  local port="${4:-}"
  local server_port="${5:-}"
  local voice_port
  voice_port="$(default_voice_port "${server_port:-25566}")"
  sed -e "s|{{FORWARDING_SECRET}}|${secret}|g" \
      -e "s|{{PORT}}|${port}|g" \
      -e "s|{{SERVER_PORT}}|${server_port}|g" \
      -e "s|{{VOICE_PORT}}|${voice_port}|g" \
      "$src" > "$dest"
}

wait_for_server_ready() {
  local log_file="$1"
  local timeout="${2:-180}"
  local label="${3:-server}"
  local server_dir alt_log
  server_dir="$(dirname "$(dirname "$log_file")")"
  alt_log="${server_dir}/console.log"
  local elapsed=0

  while [[ $elapsed -lt $timeout ]]; do
    if [[ -f "$log_file" ]] && grep -q "Done (" "$log_file" 2>/dev/null; then
      return 0
    fi
    if [[ -f "$alt_log" ]] && grep -q "Done (" "$alt_log" 2>/dev/null; then
      return 0
    fi
    if (( elapsed > 0 && elapsed % 15 == 0 )); then
      log_info "Waiting for ${label} to finish starting... (${elapsed}s / ${timeout}s)"
      log_info "  Watch live: ./scripts/attach-server.sh ${label}"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  log_warn "Timed out waiting for ${label} (${timeout}s) — it may still be starting in tmux"
  return 1
}
