#!/usr/bin/env bash
# Download and install Fabric mods from Modrinth manifests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

download_modrinth_mod() {
  local slug="$1"
  local dest="$2"
  local loaders_json="$3"
  local mc_version="${MC_VERSION:-}"
  local query
  query="$(python3 -c 'import urllib.parse,sys,json; loaders=json.loads(sys.argv[1]); gv=json.loads(sys.argv[2]) if sys.argv[2] else None; q={"loaders": loaders};
if gv: q["game_versions"]=gv
print(urllib.parse.urlencode({k: json.dumps(v) for k,v in q.items()}))' "$loaders_json" "${mc_version:+[\"$mc_version\"]}")"
  local url="https://api.modrinth.com/v2/project/${slug}/version?${query}"
  local response
  response="$(curl -fsSL "$url")"
  local download_url filename
  download_url="$(echo "$response" | jq -r '.[0].files[] | select(.primary == true) | .url' | head -1)"
  filename="$(echo "$response" | jq -r '.[0].files[] | select(.primary == true) | .filename' | head -1)"
  if [[ -z "$download_url" || "$download_url" == "null" ]]; then
    download_url="$(echo "$response" | jq -r '.[0].files[0].url')"
    filename="$(echo "$response" | jq -r '.[0].files[0].filename')"
  fi
  [[ -n "$download_url" && "$download_url" != "null" ]] || \
    die "Modrinth download not found for: ${slug} (MC ${mc_version:-any})"
  curl -fsSL -o "$dest" "$download_url"
  echo "$filename"
}

install_mod_entry() {
  local entry="$1"
  local mods_dir="$2"
  local name slug dest filename

  name="$(echo "$entry" | jq -r '.name')"
  slug="$(echo "$entry" | jq -r '.slug')"
  dest="${mods_dir}/${slug}.jar.tmp"

  log_info "Installing mod: ${name}"
  ensure_dir "$mods_dir"
  filename="$(download_modrinth_mod "$slug" "$dest" "$(echo "$entry" | jq -c '(.loaders // ["fabric"])')")"
  mv "$dest" "${mods_dir}/${filename}"
  log_ok "Installed ${name} (${filename})"
}

install_mods_for_type() {
  local bundle="$1"
  local server_dir="$2"
  local manifest="${SHARED_DIR}/mods-${bundle}.json"

  [[ -f "$manifest" ]] || die "Mod manifest not found: $manifest"
  local mods_dir="${server_dir}/mods"
  ensure_dir "$mods_dir"

  local count i
  count="$(jq 'length' "$manifest")"
  for ((i = 0; i < count; i++)); do
    install_mod_entry "$(jq -c ".[$i]" "$manifest")" "$mods_dir"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_mods_for_type "${1:?bundle}" "${2:?server_dir}"
fi
