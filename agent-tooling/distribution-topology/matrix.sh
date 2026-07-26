#!/usr/bin/env bash

MATRIX_EFFECTIVE_MANIFEST=
MATRIX_SOURCE_MANIFEST=
MATRIX_MANIFEST_CHANGED=0

matrix_parse() { # matrix output invalid-output
  local matrix="$1" output="$2" invalid="$3"
  : > "$invalid"
  awk -F '|' -v invalid="$invalid" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^\|[[:space:]]*Skill[[:space:]]*\|[[:space:]]*Source[[:space:]]*\|[[:space:]]*Type[[:space:]]*\|[[:space:]]*Claude[[:space:]]*\|[[:space:]]*Codex[[:space:]]*\|/ {
      table = 1
      next
    }
    table && !/^\|/ { table = 0 }
    table && /^\|/ {
      skill = trim($2)
      source = trim($3)
      type = trim($4)
      claude = trim($5)
      codex = trim($6)
      if (skill ~ /^-+$/) next
      if (skill !~ /^`.*`$/) next
      skill = substr(skill, 2, length(skill) - 2)
      if ((type == "skill" || type == "plugin") &&
          (claude == "Y" || claude == "N") &&
          (codex == "Y" || codex == "N")) {
        print skill "\t" source "\t" type "\t" claude "\t" codex
      } else if (skill != "" && source != "") {
        print skill "\t" source "\t" type "\t" claude "\t" codex > invalid
      }
    }
  ' "$matrix" > "$output"
}

matrix_add_finding() { # output code source skill message
  jq -cn --arg code "$2" --arg sourceId "$3" --arg skill "$4" --arg message "$5" \
    '{code:$code,sourceId:$sourceId,skill:$skill,message:$message}' >> "$1"
}

matrix_compare_plugin_rows() { # current expected findings
  local current="$1" expected="$2" findings="$3"
  awk -F '\t' '
    NR == FNR && $3 == "plugin" {
      expected[$1 SUBSEP $2] = $4 SUBSEP $5
      next
    }
    $3 == "plugin" {
      key = $1 SUBSEP $2
      if (!(key in expected) || expected[key] != $4 SUBSEP $5) {
        print $1 "\t" $2
      }
    }
  ' "$expected" "$current" |
    while IFS=$'\t' read -r skill source; do
      matrix_add_finding "$findings" plugin-row-edit matrix "$skill" \
        "plugin matrix row was edited: $skill ($source)"
    done
}

matrix_source_overrides() { # source-id matrix-source inventory current output findings
  local source_id="$1" matrix_source="$2" inventory="$3" current="$4" output="$5" findings="$6"
  local rows="$DISCOVERY_ROOT/$source_id.matrix.tsv" skill claude codex destinations
  awk -F '\t' -v source="$matrix_source" '$2 == source && $3 == "skill" { print $1 "\t" $4 "\t" $5 }' \
    "$current" | LC_ALL=C sort > "$rows"

  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    if ! awk -F '\t' -v skill="$skill" '$1 == skill { found = 1 } END { exit !found }' "$rows"; then
      matrix_add_finding "$findings" new-skill "$source_id" "$skill" \
        "known skill has no matrix row: $source_id/$skill"
    fi
  done < "$inventory"

  while IFS=$'\t' read -r skill claude codex; do
    [ -n "$skill" ] || continue
    if ! rg -Fxq -- "$skill" "$inventory"; then
      if [ "${TOPOLOGY_PHASE:-acquire}" = distribute ] && { [ "$claude" = Y ] || [ "$codex" = Y ]; }; then
        topology_fail 1 "matrix selects $source_id/$skill but staging has no copy; run acquire (update-skill-topology.sh) or git pull"
        return 1
      fi
      matrix_add_finding "$findings" removed-skill "$source_id" "$skill" \
        "matrix row has no known skill: $source_id/$skill"
      continue
    fi
    destinations='[]'
    if [ "$claude" = Y ] && [ "$codex" = Y ]; then
      destinations='["claude","codex"]'
    elif [ "$claude" = Y ]; then
      destinations='["claude"]'
    elif [ "$codex" = Y ]; then
      destinations='["codex"]'
    fi
    jq -cn --arg key "$skill" --argjson value "$destinations" '{key:$key,value:$value}' >> "$output"
  done < "$rows"
}

matrix_prepare() { # current-plan findings
  local current_plan="$1" findings="$2" matrix="$REPO_ROOT/agent-tooling/skills-matrix.md"
  local current="$DISCOVERY_ROOT/matrix-current.tsv" expected_md="$DISCOVERY_ROOT/matrix-expected.md"
  local expected="$DISCOVERY_ROOT/matrix-expected.tsv" invalid="$DISCOVERY_ROOT/matrix-invalid.tsv"
  local source_id matrix_source entries overrides next skill source type claude codex

  MATRIX_EFFECTIVE_MANIFEST="$MANIFEST_PATH"
  MATRIX_SOURCE_MANIFEST="$MANIFEST_PATH"
  MATRIX_MANIFEST_CHANGED=0
  if [ ! -f "$matrix" ]; then
    if jq -e 'any(.sources[]; has("matrixOverridesStart") or has("matrixOverridesEnd"))' "$MANIFEST_PATH" >/dev/null; then
      topology_fail 1 'skills matrix is missing: agent-tooling/skills-matrix.md'
      return 1
    fi
    return 0
  fi

  matrix_parse "$matrix" "$current" "$invalid"
  if ! SKILL_MATRIX_PLAN_PATH="$current_plan" python3 "$REPO_ROOT/agent-tooling/generate-skills-matrix.py" > "$expected_md"; then
    topology_fail 1 'skills matrix baseline generation failed'
    return 1
  fi
  matrix_parse "$expected_md" "$expected" "$DISCOVERY_ROOT/matrix-expected-invalid.tsv"
  matrix_compare_plugin_rows "$current" "$expected" "$findings"

  while IFS=$'\t' read -r skill source type claude codex; do
    if awk -F '\t' -v skill="$skill" -v source="$source" \
      '$1 == skill && $2 == source && $3 == "plugin" { found = 1 } END { exit !found }' "$expected"; then
      matrix_add_finding "$findings" plugin-row-edit matrix "$skill" \
        "plugin matrix row has invalid destination cells: $skill ($source)"
    else
      matrix_add_finding "$findings" invalid-matrix-row matrix "$skill" \
        "matrix row has invalid type or destination cells: $skill ($source)"
    fi
  done < "$invalid"

  while IFS=$'\t' read -r skill source type; do
    matrix_add_finding "$findings" invalid-matrix-row matrix "$skill" \
      "matrix contains a duplicate row: $skill ($source, $type)"
  done < <(awk -F '\t' '{ key=$1 SUBSEP $2 SUBSEP $3; count[key]++; row[key]=$1 "\t" $2 "\t" $3 }
    END { for (key in count) if (count[key] > 1) print row[key] }' "$current")

  while IFS=$'\t' read -r skill source; do
    if ! jq -e --arg source "$source" 'any(.[]; .matrixSource == $source)' "$REGISTRY_PATH" >/dev/null; then
      matrix_add_finding "$findings" removed-skill matrix "$skill" \
        "skill matrix row has no registered source: $skill ($source)"
    fi
  done < <(awk -F '\t' '$3 == "skill" { print $1 "\t" $2 }' "$current")

  next="$DISCOVERY_ROOT/matrix-manifest.json"
  cp "$MATRIX_SOURCE_MANIFEST" "$next"
  while IFS=$'\t' read -r source_id matrix_source; do
    entries="$DISCOVERY_ROOT/$source_id.matrix-overrides.ndjson"
    : > "$entries"
    matrix_source_overrides "$source_id" "$matrix_source" \
      "$DISCOVERY_ROOT/$source_id.inventory" "$current" "$entries" "$findings" || return $?
    overrides="$(jq -s 'sort_by(.key) | from_entries' "$entries")"
    jq --arg source "$source_id" --argjson overrides "$overrides" '
      .sources |= map(
        if .id == $source then
          . as $entry |
          {id:$entry.id, classification:$entry.classification,
           defaultDestinations:$entry.defaultDestinations,
           matrixOverridesStart:"generated from agent-tooling/skills-matrix.md",
           overrides:$overrides,
           matrixOverridesEnd:"end generated overrides"} +
          ($entry | del(.id,.classification,.defaultDestinations,.matrixOverridesStart,.overrides,.matrixOverridesEnd))
        else . end
      )
    ' "$next" > "$next.tmp" && mv "$next.tmp" "$next"
  done < <(jq -r '.[] | select(.matrixSource != null) | [.sourceId,.matrixSource] | @tsv' "$REGISTRY_PATH")

  MATRIX_EFFECTIVE_MANIFEST="$next"
  cmp -s "$MATRIX_SOURCE_MANIFEST" "$next" || MATRIX_MANIFEST_CHANGED=1
}

matrix_persist_manifest() {
  [ "$MATRIX_MANIFEST_CHANGED" -eq 1 ] || return 0
  cp "$MATRIX_EFFECTIVE_MANIFEST" "$MATRIX_SOURCE_MANIFEST.tmp" \
    && mv "$MATRIX_SOURCE_MANIFEST.tmp" "$MATRIX_SOURCE_MANIFEST"
}

matrix_regenerate_report() { # post-reconcile plan
  local plan="$1" matrix="$REPO_ROOT/agent-tooling/skills-matrix.md"
  local generated="$DISCOVERY_ROOT/skills-matrix-generated.md" next="$matrix.tmp"
  [ -f "$matrix" ] || return 0

  SKILL_MATRIX_PLAN_PATH="$plan" python3 "$REPO_ROOT/agent-tooling/generate-skills-matrix.py" > "$generated" || return 1
  awk '
    /^## Counts[[:space:]]*$/ { boundary = 1; exit }
    /^\|[[:space:]]*Skill[[:space:]]*\|[[:space:]]*Source[[:space:]]*\|[[:space:]]*Type[[:space:]]*\|[[:space:]]*Claude[[:space:]]*\|[[:space:]]*Codex[[:space:]]*\|/ {
      boundary = 1
      exit
    }
    { print }
    END { if (!boundary) exit 1 }
  ' "$matrix" > "$next" || return 1
  [ ! -s "$next" ] || [ -z "$(tail -n 1 "$next")" ] || printf '\n' >> "$next"
  cat "$generated" >> "$next" && mv "$next" "$matrix"
}
