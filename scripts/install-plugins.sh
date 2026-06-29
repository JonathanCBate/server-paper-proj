#!/usr/bin/env bash
# Download and install plugins for Paper and Velocity servers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

download_luckperms() {
  local platform="$1"
  local dest="$2"
  local meta
  meta="$(curl -fsSL "https://metadata.luckperms.net/data/downloads")"
  local url
  url="$(echo "$meta" | jq -r --arg p "$platform" '.downloads[$p]')"
  [[ "$url" != "null" && -n "$url" ]] || die "LuckPerms download not found for platform: $platform"
  curl -fsSL -o "$dest" "$url"
}

download_hangar() {
  local namespace="$1"
  local slug="$2"
  local platform="$3"
  local dest="$4"
  local version
  version="$(curl -fsSL "https://hangar.papermc.io/api/v1/projects/${namespace}/${slug}/latestrelease?platform=${platform}")"
  version="$(echo "$version" | tr -d '"')"
  local url="https://hangar.papermc.io/api/v1/projects/${namespace}/${slug}/versions/${version}/${platform}/download"
  curl -fsSL -o "$dest" "$url"
}

download_modrinth() {
  local slug="$1"
  local dest="$2"
  local loaders_json="$3"
  local encoded
  encoded="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$loaders_json")"
  local url="https://api.modrinth.com/v2/project/${slug}/version?loaders=${encoded}"
  local response
  response="$(curl -fsSL "$url")"
  local download_url
  download_url="$(echo "$response" | jq -r '.[0].files[] | select(.primary == true) | .url' | head -1)"
  if [[ -z "$download_url" || "$download_url" == "null" ]]; then
    download_url="$(echo "$response" | jq -r '.[0].files[0].url')"
  fi
  [[ -n "$download_url" && "$download_url" != "null" ]] || die "Modrinth download not found for: $slug"
  curl -fsSL -o "$dest" "$download_url"
}

download_github_release() {
  local repo="$1"
  local asset="$2"
  local dest="$3"
  local release
  release="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")"
  local url
  url="$(echo "$release" | jq -r --arg a "$asset" '.assets[] | select(.name == $a) | .browser_download_url')"
  [[ -n "$url" && "$url" != "null" ]] || die "GitHub release asset not found: ${repo}/${asset}"
  curl -fsSL -L -o "$dest" "$url"
}

install_plugin_entry() {
  local entry="$1"
  local plugins_dir="$2"
  local name file source dest config_src

  name="$(echo "$entry" | jq -r '.name')"
  file="$(echo "$entry" | jq -r '.file')"
  source="$(echo "$entry" | jq -r '.source')"
  dest="${plugins_dir}/${file}"

  log_info "Installing plugin: ${name}"
  ensure_dir "$plugins_dir"

  case "$source" in
    luckperms)
      download_luckperms "$(echo "$entry" | jq -r '.platform')" "$dest"
      ;;
    hangar)
      download_hangar \
        "$(echo "$entry" | jq -r '.namespace')" \
        "$(echo "$entry" | jq -r '.slug')" \
        "$(echo "$entry" | jq -r '.platform')" \
        "$dest"
      ;;
    modrinth)
      download_modrinth \
        "$(echo "$entry" | jq -r '.slug')" \
        "$dest" \
        "$(echo "$entry" | jq -c '(.loaders // ["paper"])')"
      ;;
    github)
      download_github_release \
        "$(echo "$entry" | jq -r '.repo')" \
        "$(echo "$entry" | jq -r '.asset')" \
        "$dest"
      ;;
    url)
      curl -fsSL -o "$dest" "$(echo "$entry" | jq -r '.url')"
      ;;
    *)
      die "Unknown plugin source: $source"
      ;;
  esac

  config_src="$(echo "$entry" | jq -r '.config // empty')"
  if [[ -n "$config_src" ]]; then
    local shared_config="${SHARED_DIR}/plugin-configs/${config_src}"
    local target_config="${plugins_dir}/$(dirname "$config_src")"
    if [[ -f "$shared_config" ]]; then
      ensure_dir "$target_config"
      local final="${plugins_dir}/${config_src}"
      if [[ ! -f "$final" ]]; then
        cp "$shared_config" "$final"
        log_info "Copied default config for ${name}"
      fi
    fi
  fi

  log_ok "Installed ${name}"
}

install_plugins_for_type() {
  local bundle="$1"
  local server_dir="$2"
  local manifest="${SHARED_DIR}/plugins-${bundle}.json"

  [[ -f "$manifest" ]] || die "Plugin manifest not found: $manifest"
  local plugins_dir="${server_dir}/plugins"
  ensure_dir "$plugins_dir"

  local count
  count="$(jq 'length' "$manifest")"
  local i
  for ((i = 0; i < count; i++)); do
    install_plugin_entry "$(jq -c ".[$i]" "$manifest")" "$plugins_dir"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_plugins_for_type "${1:?bundle}" "${2:?server_dir}"
fi
