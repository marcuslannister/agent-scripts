#!/usr/bin/env bash
set -euo pipefail

# Shared Sparkle/release helpers for CodexBar/Trimmy/RepoBar.
# Expected env/args:
#   SPARKLE_PRIVATE_KEY_FILE : path to ed25519 private key (comment-free)
#   APPCAST                  : path to appcast.xml
#   APP_NAME                 : e.g. CodexBar
#   ARTIFACT_PREFIX          : e.g. CodexBar-
#   BUNDLE_ID                : e.g. com.steipete.codexbar
#   VERSION                  : marketing version (e.g. 0.5.6)
#   BUILD_NUMBER             : build (sparkle:version) if needed

require_bin() {
  for b in "$@"; do
    command -v "$b" >/dev/null 2>&1 || { echo "Missing required tool: $b" >&2; exit 1; }
  done
}

clean_key() {
  local keyfile=${1:?"key file required"}
  if [[ ! -f "$keyfile" ]]; then
    echo "Sparkle key file not found: $keyfile" >&2
    exit 1
  fi
  local lines
  lines=$(grep -v '^[[:space:]]*#' "$keyfile" | sed '/^[[:space:]]*$/d')
  if [[ $(printf "%s\n" "$lines" | wc -l) -ne 1 ]]; then
    echo "Sparkle key must be a single base64 line (no comments/blank lines)." >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  printf "%s" "$lines" >"$tmp"
  echo "$tmp"
}

verify_enclosure() {
  local url=$1 sig=$2 keyfile=$3 expected_len=$4
  require_bin curl sign_update
  local tmp
  tmp=$(mktemp /tmp/sparkle-enclosure.XXXX)
  trap 'rm -f "$tmp"' RETURN
  curl -L -o "$tmp" "$url"
  local len
  len=$(stat -f%z "$tmp")
  if [[ "$len" != "$expected_len" ]]; then
    echo "Length mismatch for $url (expected $expected_len, got $len)" >&2
    exit 1
  fi
  sign_update --verify "$tmp" "$sig" --ed-key-file "$keyfile"
}

verify_appcast_entry() {
  local appcast=${1:?"appcast path"} version=${2:?"version"} keyfile=${3:?"key file"}
  require_bin python3 curl sign_update
  local verify_codesign=${SPARKLE_VERIFY_CODESIGN:-0}
  local tmp_meta
  tmp_meta=$(mktemp)
  trap 'rm -f "$tmp_meta"' RETURN

  python3 - "$appcast" "$version" >"$tmp_meta" <<'PY'
import sys, xml.etree.ElementTree as ET
appcast, version = sys.argv[1], sys.argv[2]
root = ET.parse(appcast).getroot()
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
entry = None
for item in root.findall("./channel/item"):
    if item.findtext("sparkle:shortVersionString", default="", namespaces=ns) == version:
        entry = item
        break
if entry is None:
    sys.exit("No appcast entry for version {}".format(version))
enc = entry.find("enclosure")
url = enc.get("url")
sig = enc.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature")
length = enc.get("length")
if not (url and sig and length):
    sys.exit("Missing url/signature/length for version {}".format(version))
print(url)
print(sig)
print(length)
PY

  readarray -t m <"$tmp_meta"
  verify_enclosure "${m[0]}" "${m[1]}" "$keyfile" "${m[2]}"
  echo "Appcast entry $version verified (signature & length)."

  if [[ "$verify_codesign" == "1" ]]; then
    verify_codesign_from_enclosure "${m[0]}"
  fi
}

check_assets() {
  local tag=${1:?"tag"} prefix=${2:?"artifact prefix"} repo
  require_bin gh
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  local assets
  assets=$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')
  local zip dsym
  zip=$(printf "%s\n" "$assets" | grep -E "^${prefix}[0-9]+(\\.[0-9]+)*\\.zip$" || true)
  dsym=$(printf "%s\n" "$assets" | grep -E "^${prefix}[0-9]+(\\.[0-9]+)*\\.dSYM\\.zip$" || true)
  [[ -z "$zip" ]] && { echo "ERROR: app zip missing on release $tag" >&2; exit 1; }
  [[ -z "$dsym" ]] && { echo "ERROR: dSYM zip missing on release $tag" >&2; exit 1; }
  echo "Release $tag has zip ($zip) and dSYM ($dsym)."
}

clear_sparkle_caches() {
  rm -rf ~/Library/Caches/${1} ~/Library/Caches/org.sparkle-project.Sparkle || true
}

# Removes AppleDouble/extended attributes that break codesign after zipping.
clean_macos_metadata() {
  local path=${1:?"path required"}
  xattr -cr "$path" 2>/dev/null || true
  find "$path" -name '._*' -delete 2>/dev/null || true
}

# Zips a bundle without resource-fork baggage.
safe_zip() {
  local source=${1:?"source bundle/app required"} dest=${2:?"destination zip required"}
  clean_macos_metadata "$source"
  /usr/bin/ditto --norsrc -c -k --keepParent "$source" "$dest"
}

# Download an enclosure, extract, and verify codesign/spctl on the bundled app.
verify_codesign_from_enclosure() {
  local url=${1:?"enclosure URL required"}
  require_bin curl ditto codesign spctl

  local tmp_dir tmp_zip
  tmp_dir=$(mktemp -d /tmp/sparkle-verify.XXXX)
  tmp_zip="$tmp_dir/enclosure.zip"
  curl -L -o "$tmp_zip" "$url"

  # Extract without resource forks to avoid introducing AppleDouble files.
  /usr/bin/ditto -x -k --norsrc "$tmp_zip" "$tmp_dir"

  local app
  app=$(find "$tmp_dir" -maxdepth 2 -name "*.app" | head -n 1)
  if [[ -z "$app" ]]; then
    echo "No .app found in enclosure $url" >&2
    return 1
  fi

  if ! codesign --verify --deep --strict --verbose "$app"; then
    echo "codesign verification failed for $app" >&2
    return 1
  fi
  if ! spctl --assess --type execute --verbose "$app"; then
    echo "spctl assessment failed for $app" >&2
    return 1
  fi
  if command -v stapler >/dev/null 2>&1; then
    stapler validate "$app" >/dev/null || true
  fi
  echo "Codesign/spctl verification OK for $(basename "$app") from $url"
}
