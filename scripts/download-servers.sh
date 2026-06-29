#!/usr/bin/env bash
# Download Paper and Velocity server JARs via the PaperMC API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

latest_stable_version() {
  local project="$1"
  papermc_project_versions "$project" | \
    jq -r '[.versions[] | select(test("pre|rc|snapshot|SNAPSHOT"; "i") | not)] | .[-1]'
}

download_papermc_jar() {
  local project="$1"   # paper | velocity
  local version="$2"
  local dest_dir="$3"
  local jar_name="$4"

  log_info "Downloading ${project} ${version}..."

  local versions_json
  versions_json="$(curl -fsSL "https://api.papermc.io/v2/projects/${project}")"

  if ! echo "$versions_json" | jq -e --arg v "$version" '.versions | index($v)' >/dev/null; then
    die "Version ${version} not available for ${project}. Available: $(echo "$versions_json" | jq -r '.versions | join(", ")')"
  fi

  local builds_json
  builds_json="$(curl -fsSL "https://api.papermc.io/v2/projects/${project}/versions/${version}")"
  local build
  build="$(echo "$builds_json" | jq -r '.builds[-1]')"

  local build_json
  build_json="$(curl -fsSL "https://api.papermc.io/v2/projects/${project}/versions/${version}/builds/${build}")"
  local download_name
  download_name="$(echo "$build_json" | jq -r '.downloads.application.name')"

  ensure_dir "$dest_dir"
  local url="https://api.papermc.io/v2/projects/${project}/versions/${version}/builds/${build}/downloads/${download_name}"
  curl -fsSL -o "${dest_dir}/${jar_name}" "$url"
  log_ok "Downloaded ${jar_name} (build ${build})"
}

download_server_jar() {
  local type="$1"
  local dest_dir="$2"

  case "$type" in
    paper)
      download_papermc_jar "paper" "${MC_VERSION}" "$dest_dir" "server.jar"
      ;;
    velocity)
      local velocity_version="${VELOCITY_VERSION:-$(latest_stable_version velocity)}"
      download_papermc_jar "velocity" "$velocity_version" "$dest_dir" "server.jar"
      ;;
    *)
      die "Unknown server type: $type"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  download_server_jar "${1:?type}" "${2:?dest_dir}"
fi
