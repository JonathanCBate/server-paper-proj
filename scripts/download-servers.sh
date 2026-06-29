#!/usr/bin/env bash
# Download Paper and Velocity server JARs via the PaperMC fill API (v3).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

download_papermc_jar() {
  local project="$1"   # paper | velocity
  local version="$2"
  local dest_dir="$3"
  local jar_name="$4"

  log_info "Downloading ${project} ${version}..."

  papermc_version_exists "$project" "$version" || \
    die "Version ${version} not available for ${project}."

  local builds_json
  builds_json="$(curl -fsSL "${PAPERMC_FILL_API}/projects/${project}/versions/${version}/builds")"

  local build_json
  build_json="$(echo "$builds_json" | jq -r '
    ([.[] | select(.channel == "STABLE")] | .[0]) // .[0]
  ')"
  [[ -n "$build_json" && "$build_json" != "null" ]] || die "No builds found for ${project} ${version}"

  local build url
  build="$(echo "$build_json" | jq -r '.id')"
  url="$(echo "$build_json" | jq -r '.downloads["server:default"].url')"
  [[ -n "$url" && "$url" != "null" ]] || die "Download URL not found for ${project} ${version} build ${build}"

  ensure_dir "$dest_dir"
  curl -fsSL -o "${dest_dir}/${jar_name}" "$url"
  log_ok "Downloaded ${jar_name} (build ${build})"
}

download_fabric_server() {
  local mc_version="$1"
  local dest_dir="$2"
  local loader installer url

  log_info "Downloading Fabric server ${mc_version}..."

  loader="$(curl -fsSL "${FABRIC_META_API}/versions/loader/${mc_version}" | \
    jq -r '[.[] | select(.loader.stable == true)][0].loader.version')"
  [[ -n "$loader" && "$loader" != "null" ]] || \
    die "No stable Fabric loader for Minecraft ${mc_version}"

  installer="$(curl -fsSL "${FABRIC_META_API}/versions/installer" | \
    jq -r '[.[] | select(.stable == true)][0].version')"
  [[ -n "$installer" && "$installer" != "null" ]] || die "Could not resolve Fabric installer version"

  url="${FABRIC_META_API}/versions/loader/${mc_version}/${loader}/${installer}/server/jar"
  ensure_dir "$dest_dir"
  curl -fsSL -o "${dest_dir}/server.jar" "$url"
  log_ok "Downloaded server.jar (Fabric loader ${loader}, MC ${mc_version})"
}

download_server_jar() {
  local type="$1"
  local dest_dir="$2"

  case "$type" in
    paper)
      download_papermc_jar "paper" "${MC_VERSION}" "$dest_dir" "server.jar"
      ;;
    fabric)
      download_fabric_server "${MC_VERSION}" "$dest_dir"
      ;;
    velocity)
      resolve_velocity_version
      download_papermc_jar "velocity" "${VELOCITY_VERSION}" "$dest_dir" "server.jar"
      ;;
    *)
      die "Unknown server type: $type"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  download_server_jar "${1:?type}" "${2:?dest_dir}"
fi
