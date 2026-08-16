#!/usr/bin/env bash
set -euo pipefail

# Operator-run repair for claude-mem's missing or stale Codex runtime marker.
#
# The native Codex marketplace can install claude-mem without the marker that
# its SessionStart hook requires. Repair every non-orphaned installed cache
# version by default. This is the narrow ADR-0007 exception: it changes only
# .install-version, never a marketplace snapshot, Codex metadata, config, or
# plugin registration. It never invokes codex or npx.

cache_root="${CODEX_MARKER_CACHE_ROOT:-$HOME/.codex/plugins/cache/claude-mem-local/claude-mem}"
check_only=0

info() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2; }

usage() {
  printf '%s\n' \
    'Usage: repair-claude-mem-marker.sh [--check]' \
    '' \
    'Repair missing, unreadable, or stale claude-mem Codex runtime markers.' \
    'The default action repairs every installed, non-orphaned cache version.' \
    '' \
    'Options:' \
    '  --check     Report marker drift without changing files.' \
    '  -h, --help  Show this help and exit.'
}

for argument in "$@"; do
  case "$argument" in
    -h|--help) usage; exit 0 ;;
    --check) check_only=1 ;;
    *)
      warn "unknown option: $argument"
      printf 'Run repair-claude-mem-marker.sh --help for usage.\n' >&2
      exit 2
      ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  warn 'required tool not found: node'
  exit 2
fi

package_version() { # package_json
  node -e '
    const fs = require("fs");
    const versionPattern = /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
    try {
      const version = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).version;
      if (typeof version !== "string" || !versionPattern.test(version)) process.exit(1);
      process.stdout.write(version);
    } catch {
      process.exit(1);
    }
  ' "$1"
}

marker_version() { # marker
  node -e '
    const fs = require("fs");
    const versionPattern = /^v?[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
    try {
      const content = fs.readFileSync(process.argv[1], "utf8");
      try {
        const marker = JSON.parse(content);
        if (marker && typeof marker.version === "string") {
          process.stdout.write(marker.version);
          process.exit(0);
        }
      } catch {}
      const legacyVersion = content.trim();
      if (versionPattern.test(legacyVersion)) {
        process.stdout.write(legacyVersion.replace(/^v/i, ""));
        process.exit(0);
      }
      process.exit(1);
    } catch {
      process.exit(1);
    }
  ' "$1"
}

write_marker() { # plugin_root package_version
  local plugin_root="$1" version="$2" marker temp_marker
  marker="$plugin_root/.install-version"
  temp_marker="$(mktemp "$plugin_root/.install-version.tmp.XXXXXX")" || return 1
  if ! printf '{"version":"%s"}\n' "$version" > "$temp_marker"; then
    rm -f -- "$temp_marker"
    return 1
  fi
  if ! mv -f -- "$temp_marker" "$marker"; then
    rm -f -- "$temp_marker"
    return 1
  fi
}

if [ ! -d "$cache_root" ]; then
  warn "claude-mem Codex cache not found: $cache_root"
  exit 1
fi

shopt -s nullglob
roots=("$cache_root"/*)
checked=0
needed=0
repaired=0
failed=0

for plugin_root in "${roots[@]}"; do
  [ -d "$plugin_root" ] || continue
  [ -e "$plugin_root/.orphaned_at" ] && continue
  checked=$((checked + 1))

  package_json="$plugin_root/package.json"
  marker="$plugin_root/.install-version"
  if [ ! -f "$package_json" ]; then
    warn "$(basename "$plugin_root"): package.json is missing"
    failed=$((failed + 1))
    continue
  fi
  if ! version="$(package_version "$package_json")"; then
    warn "$(basename "$plugin_root"): package.json has no valid version"
    failed=$((failed + 1))
    continue
  fi

  marker_state=missing
  if [ -e "$marker" ]; then
    if marker_value="$(marker_version "$marker")" && [ "$marker_value" = "$version" ]; then
      printf '\033[0;32m✓\033[0m %-16s marker matches %s\n' "$(basename "$plugin_root")" "$version"
      continue
    fi
    marker_state=stale-or-unreadable
  fi

  needed=$((needed + 1))
  if [ "$check_only" -eq 1 ]; then
    printf '\033[0;31m✗\033[0m %-16s %s marker; would write %s\n' \
      "$(basename "$plugin_root")" "$marker_state" "$version"
    continue
  fi
  if write_marker "$plugin_root" "$version"; then
    printf '\033[0;32m✓\033[0m %-16s repaired marker for %s\n' \
      "$(basename "$plugin_root")" "$version"
    repaired=$((repaired + 1))
  else
    warn "$(basename "$plugin_root"): could not write runtime marker"
    failed=$((failed + 1))
  fi
done

if [ "$checked" -eq 0 ]; then
  warn "no non-orphaned claude-mem Codex cache versions found in $cache_root"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  warn "$failed claude-mem marker repairs failed"
  exit 1
fi
if [ "$check_only" -eq 1 ] && [ "$needed" -gt 0 ]; then
  warn "$needed claude-mem markers need repair"
  exit 1
fi
if [ "$repaired" -gt 0 ]; then
  info "repaired $repaired claude-mem runtime markers"
else
  info 'every claude-mem runtime marker matches its installed package version'
fi
