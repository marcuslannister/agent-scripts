#!/usr/bin/env bash
# Refresh matrix inventory and derived sections without changing selections.
set -euo pipefail

shopt -s nullglob
export LC_COLLATE=C

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MATRIX="$SCRIPT_DIR/skills-matrix.md"
HOME_ROOT="${HOME:?HOME must be set}"
SELF="marcuslannister/agent-scripts"
UPSTREAM_MIRROR="steipete/agent-scripts"

TMP_ROOT="$(mktemp -d)"
cleanup() {
  exit_code=$?
  trap - EXIT
  rm -rf "$TMP_ROOT" || true
  exit "$exit_code"
}
trap cleanup EXIT

RECORDS="$TMP_ROOT/records.tsv"
MIRROR_NAMES="$TMP_ROOT/mirror-names"
STAGED_NAMES="$TMP_ROOT/staged-names"
MERGED_ROWS="$TMP_ROOT/merged.tsv"
SORTED_ROWS="$TMP_ROOT/sorted.tsv"
ENABLED_KEYS="$TMP_ROOT/enabled.tsv"
SOURCES="$TMP_ROOT/sources"
: > "$RECORDS"
: > "$MIRROR_NAMES"
: > "$STAGED_NAMES"
: > "$ENABLED_KEYS"

for candidate in C.UTF-8 en_US.UTF-8 UTF-8; do
  if LC_ALL='' LC_CTYPE="$candidate" locale charmap >/dev/null 2>&1; then
    TEXT_LOCALE="$candidate"
    break
  fi
done
TEXT_LOCALE="${TEXT_LOCALE:-${LC_CTYPE:-${LANG:-C}}}"

github_repo() {
  local value="${1:-}"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  case "$value" in
    http://github.com/*) value="${value#http://github.com/}" ;;
    https://github.com/*) value="${value#https://github.com/}" ;;
    git@github.com:*) value="${value#git@github.com:}" ;;
  esac
  case "$value" in
    *.git) value="${value%.git}" ;;
  esac

  if [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

token_count() {
  local path="$1"
  local characters quotient remainder

  if ! characters="$(LC_ALL='' LC_CTYPE="$TEXT_LOCALE" wc -m < "$path" 2>/dev/null)"; then
    printf '1\n'
    return
  fi
  characters="${characters//[[:space:]]/}"
  if [[ ! "$characters" =~ ^[0-9]+$ ]]; then
    printf '1\n'
    return
  fi

  quotient=$((characters / 4))
  remainder=$((characters % 4))
  if [ "$remainder" -gt 2 ] \
    || { [ "$remainder" -eq 2 ] && [ $((quotient % 2)) -eq 1 ]; }; then
    quotient=$((quotient + 1))
  fi
  [ "$quotient" -ge 1 ] || quotient=1
  printf '%s\n' "$quotient"
}

append_discovered() {
  local display="$1"
  local source="$2"
  local delivery="$3"
  local path="$4"
  local claude_plugin_key="${5:-}"
  local codex_plugin_key="${6:-}"
  local tokens

  tokens="$(token_count "$path")"
  printf '%s\t%s\t%s\tN\tN\t%s\t%s\t%s\tdiscovered\n' \
    "$display" "$source" "$delivery" "$tokens" \
    "$claude_plugin_key" "$codex_plugin_key" >> "$RECORDS"
}

if [ -f "$MATRIX" ]; then
  awk -F '|' -v OFS='\t' '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^\|/ {
      display = trim($2)
      source = trim($3)
      delivery = trim($4)
      claude = trim($5)
      codex = trim($6)
      tokens = trim($7)
      if (display !~ /^`[^`]+`$/ || delivery !~ /^(skill|plugin)$/ \
          || claude !~ /^[YN]$/ || codex !~ /^[YN]$/ \
          || tokens !~ /^~?[0-9]+$/) {
        next
      }
      display = substr(display, 2, length(display) - 2)
      sub(/^~/, "", tokens)
      print display, source, delivery, claude, codex, tokens, "", "", "existing"
    }
  ' "$MATRIX" >> "$RECORDS"
fi

for path in "$REPO_ROOT"/skills/*/SKILL.md; do
  [ -f "$path" ] || continue
  skill_root="${path%/*}"
  name="${skill_root##*/}"
  printf '%s\n' "$name" >> "$MIRROR_NAMES"
  append_discovered "$name" "$UPSTREAM_MIRROR" skill "$path"
done

for path in "$REPO_ROOT"/codex-skills/*/SKILL.md; do
  [ -f "$path" ] || continue
  skill_root="${path%/*}"
  name="${skill_root##*/}"
  if rg -Fxq -- "$name" "$MIRROR_NAMES"; then
    continue
  fi
  append_discovered "$name" "$SELF" skill "$path"
done

for path in "$REPO_ROOT"/other-skills/*/*/SKILL.md; do
  [ -f "$path" ] || continue
  skill_root="${path%/*}"
  name="${skill_root##*/}"
  if rg -Fxq -- "$name" "$MIRROR_NAMES" \
    || rg -Fxq -- "$name" "$STAGED_NAMES"; then
    continue
  fi
  printf '%s\n' "$name" >> "$STAGED_NAMES"

  owner_root="${skill_root%/*}"
  owner="${owner_root##*/}"
  repo_url=""
  if [ -f "$owner_root/.source.json" ]; then
    repo_url="$(jq -er '.repo | strings' "$owner_root/.source.json" 2>/dev/null || true)"
  fi
  source="$(github_repo "$repo_url" || true)"
  source="${source:-$owner}"
  append_discovered "$name" "$source" skill "$path"
done

KNOWN_MARKETPLACES="$HOME_ROOT/.claude/plugins/known_marketplaces.json"
CACHE_ROOT="$HOME_ROOT/.claude/plugins/cache"
plugin_index=0
for version_root in "$CACHE_ROOT"/*/*/*; do
  [ -d "$version_root" ] || continue
  relative="${version_root#"$CACHE_ROOT"/}"
  marketplace="${relative%%/*}"
  plugin_tail="${relative#*/}"
  plugin_name="${plugin_tail%%/*}"

  plugin_index=$((plugin_index + 1))
  plugin_paths_file="$TMP_ROOT/plugin-paths-$plugin_index"
  find -L "$version_root" \
    \( -type d -name '.*' -prune \) -o \
    \( -name SKILL.md -print \) \
    | LC_ALL=C sort > "$plugin_paths_file"
  plugin_count="$(awk 'END { print NR + 0 }' "$plugin_paths_file")"
  [ "$plugin_count" -gt 0 ] || continue

  repo_url=""
  if [ -f "$KNOWN_MARKETPLACES" ]; then
    repo_url="$(jq -er --arg marketplace "$marketplace" \
      '.[$marketplace].source.repo | strings' \
      "$KNOWN_MARKETPLACES" 2>/dev/null || true)"
  fi
  source="$(github_repo "$repo_url" || true)"
  source="${source:-$marketplace}"

  while IFS= read -r path; do
    skill_root="${path%/*}"
    if [ "$skill_root" = "$version_root" ]; then
      name="$plugin_name"
    else
      name="${skill_root##*/}"
    fi
    display="$name"
    if [ "$plugin_count" -ne 1 ]; then
      display="$plugin_name:$name"
    fi
    append_discovered "$display" "$source" plugin "$path" \
      "$plugin_name@$marketplace" "$plugin_name"
  done < "$plugin_paths_file"
done

awk -F '\t' -v OFS='\t' '
  {
    key = $1 SUBSEP $3
    if (!(key in row_number)) {
      row_number[key] = ++count
    }
    row = row_number[key]

    if ($9 == "existing") {
      display[row] = $1
      source[row] = $2
      delivery[row] = $3
      claude[row] = $4
      codex[row] = $5
      tokens[row] = $6
      claude_key[row] = $7
      codex_key[row] = $8
      next
    }

    if (display[row] == "") {
      display[row] = $1
      delivery[row] = $3
      claude[row] = "N"
      codex[row] = "N"
    }
    source[row] = $2
    tokens[row] = $6
    claude_key[row] = $7
    codex_key[row] = $8
  }
  END {
    for (row = 1; row <= count; row++) {
      print display[row], source[row], delivery[row], claude[row], codex[row], \
        tokens[row], claude_key[row], codex_key[row]
    }
  }
' "$RECORDS" > "$MERGED_ROWS"

LC_ALL=C sort -t $'\t' -k1,1 -k2,2 -k3,3 "$MERGED_ROWS" > "$SORTED_ROWS"

CLAUDE_SETTINGS="$HOME_ROOT/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
  while IFS= read -r key; do
    [ -n "$key" ] && printf 'claude\t%s\n' "$key" >> "$ENABLED_KEYS"
  done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | .key' \
    "$CLAUDE_SETTINGS" 2>/dev/null || true)
fi

CODEX_CONFIG="$HOME_ROOT/.codex/config.toml"
if [ -f "$CODEX_CONFIG" ]; then
  while IFS= read -r key; do
    [ -n "$key" ] && printf 'codex\t%s\n' "$key" >> "$ENABLED_KEYS"
  done < <(
    awk '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      {
        line = trim($0)
        if (line ~ /^\[plugins\."[^"]+"\]$/) {
          pending = line
          sub(/^\[plugins\."/, "", pending)
          sub(/"\]$/, "", pending)
          next
        }
        if (pending == "") {
          next
        }
        if (line == "") {
          next
        }
        if (line ~ /^enabled[[:space:]]*=[[:space:]]*(true|false)/) {
          value = line
          sub(/^enabled[[:space:]]*=[[:space:]]*/, "", value)
          if (value ~ /^true/) {
            print pending
          }
        }
        pending = ""
      }
    ' "$CODEX_CONFIG"
  )
fi

awk -F '\t' -v rows_file="$SORTED_ROWS" '
  function plugin_state(agent, delivery, key) {
    if (delivery == "skill") {
      return "always-on"
    }
    if (key == "" || !enabled[agent SUBSEP key]) {
      return "disabled"
    }
    return "enabled"
  }
  FILENAME != rows_file {
    enabled[$1 SUBSEP $2] = 1
    next
  }
  {
    row = ++count
    display[row] = $1
    source[row] = $2
    delivery[row] = $3
    claude[row] = $4
    codex[row] = $5
    tokens[row] = $6
    claude_key[row] = $7
    codex_key[row] = $8

    claude_selected = claude[row] == "Y"
    codex_selected = codex[row] == "Y"
    if (claude_selected && codex_selected) {
      both++
    } else if (claude_selected) {
      claude_only++
    } else if (codex_selected) {
      codex_only++
    }
    if (claude_selected) {
      claude_state[plugin_state("claude", delivery[row], claude_key[row])]++
    }
    if (codex_selected) {
      codex_state[plugin_state("codex", delivery[row], codex_key[row])]++
    }
  }
  END {
    total_claude = both + claude_only
    total_codex = both + codex_only

    print "## Counts"
    print ""
    print "| Availability | Claude | Codex |"
    print "|---|---|---|"
    printf "| Total | %d | %d |\n", total_claude, total_codex
    printf "| Shared | %d | %d |\n", both, both
    printf "| Agent-only | %d | %d |\n", claude_only, codex_only
    print ""
    print "| Skill | Source | Type | Claude | Codex | ~Tokens |"
    print "|---|---|---|---|---|---|"
    for (row = 1; row <= count; row++) {
      printf "| `%s` | %s | %s | %s | %s | ~%s |\n", \
        display[row], source[row], delivery[row], claude[row], codex[row], tokens[row]
    }
    print ""
    printf "<!-- total=%d both=%d claude_only=%d codex_only=%d total_claude=%d total_codex=%d -->\n", \
      count, both, claude_only, codex_only, total_claude, total_codex

    print ""
    print "## Enable-state"
    print ""
    print "Config truth on this machine, point-in-time (mutable — retoggling a plugin changes these). *Enabled/disabled* apply only to native plugin-delivered skills; selected plain copies have no toggle and count as *always-on*. Claude Code\047s `/skills` picker reports fewer because it lists only enabled, plugin-registered skills, while this is the full selected inventory."
    print ""
    print "| State | Claude | Codex |"
    print "|---|---|---|"
    printf "| Enabled | %d | %d |\n", claude_state["enabled"], codex_state["enabled"]
    printf "| Disabled | %d | %d |\n", claude_state["disabled"], codex_state["disabled"]
    printf "| Always-on | %d | %d |\n", claude_state["always-on"], codex_state["always-on"]
    printf "| Total | %d | %d |\n", \
      claude_state["enabled"] + claude_state["disabled"] + claude_state["always-on"], \
      codex_state["enabled"] + codex_state["disabled"] + codex_state["always-on"]
  }
' "$ENABLED_KEYS" "$SORTED_ROWS"

awk -F '\t' '{ print $2 }' "$SORTED_ROWS" | LC_ALL=C sort -u > "$SOURCES"
printf '\n## Repos\n\n'
printf '| Repo | URL |\n'
printf '|---|---|\n'
while IFS= read -r source; do
  [ -n "$source" ] || continue
  repo="$(github_repo "$source" || true)"
  if [ -n "$repo" ]; then
    url="https://github.com/$repo"
  else
    url="?"
  fi
  printf "| \`%s\` | %s |\\n" "$source" "$url"
done < "$SOURCES"
