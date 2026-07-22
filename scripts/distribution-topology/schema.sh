#!/usr/bin/env bash

topology_is_name() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

topology_is_classification() {
  case "$1" in
    repo-owned|npx-only|source-only|dual-plugin|plugin-claude-only) return 0 ;;
    *) return 1 ;;
  esac
}

topology_validate_fields() { # file jq_path allowed_json required_json label
  local file="$1" path="$2" allowed="$3" required="$4" label="$5" unknown missing
  if ! jq -e "$path | type == \"object\"" "$file" >/dev/null 2>&1; then
    topology_fail 2 "$label must be an object"
    return 2
  fi
  unknown="$(jq -r "$path | (keys - ($allowed)) | first // empty" "$file")"
  if [ -n "$unknown" ]; then
    topology_fail 2 "$label contains unknown field: $unknown"
    return 2
  fi
  missing="$(jq -r "$path as \$value | ($required)[] as \$key | select(\$value | has(\$key) | not) | \$key" "$file" | head -1)"
  if [ -n "$missing" ]; then
    topology_fail 2 "$label is missing required field: $missing"
    return 2
  fi
}

topology_validate_destinations() { # file jq_path label
  local file="$1" path="$2" label="$3" unknown
  if ! jq -e "$path | type == \"array\" and length > 0" "$file" >/dev/null 2>&1; then
    topology_fail 2 "$label must be a non-empty destination array"
    return 2
  fi
  unknown="$(jq -r "${path}[] | select(. != \"claude\" and . != \"codex\") | tostring" "$file" | head -1)"
  if [ -n "$unknown" ]; then
    topology_fail 2 "$label contains unknown destination: $unknown"
    return 2
  fi
  if ! jq -e "$path | length == (unique | length)" "$file" >/dev/null; then
    topology_fail 2 "$label contains a duplicate destination"
    return 2
  fi
}

topology_validate_manifest() { # file
  local file="$1" parse_error count index label source_id classification skill
  if ! parse_error="$(jq empty "$file" 2>&1)"; then
    topology_fail 2 "skill topology manifest is not valid JSON: $parse_error"
    return 2
  fi
  topology_validate_fields "$file" '.' '["version","sources"]' '["version","sources"]' 'skill topology manifest' || return $?
  if ! jq -e '.version == 1' "$file" >/dev/null; then
    topology_fail 2 'skill topology manifest version must be 1'
    return 2
  fi
  if ! jq -e '.sources | type == "array" and length > 0' "$file" >/dev/null; then
    topology_fail 2 'skill topology manifest sources must be a non-empty array'
    return 2
  fi
  if ! jq -e '[.sources[].id] | length == (unique | length)' "$file" >/dev/null; then
    source_id="$(jq -r '[.sources[].id] | group_by(.)[] | select(length > 1) | first' "$file" | head -1)"
    topology_fail 2 "skill topology manifest contains duplicate source id: $source_id"
    return 2
  fi

  count="$(jq '.sources | length' "$file")"
  for ((index = 0; index < count; index++)); do
    label="skill topology manifest source $index"
    topology_validate_fields "$file" ".sources[$index]" '["id","classification","defaultDestinations","overrides"]' '["id","classification","defaultDestinations","overrides"]' "$label" || return $?
    source_id="$(jq -r ".sources[$index].id" "$file")"
    if ! jq -e ".sources[$index].id | type == \"string\"" "$file" >/dev/null || ! topology_is_name "$source_id"; then
      topology_fail 2 "$label has an invalid id"
      return 2
    fi
    classification="$(jq -r ".sources[$index].classification" "$file")"
    if ! topology_is_classification "$classification"; then
      topology_fail 2 "$label contains unknown classification: $classification"
      return 2
    fi
    topology_validate_destinations "$file" ".sources[$index].defaultDestinations" "$label defaultDestinations" || return $?
    if ! jq -e ".sources[$index].overrides | type == \"object\"" "$file" >/dev/null; then
      topology_fail 2 "$label overrides must be an object"
      return 2
    fi
    while IFS= read -r skill; do
      if ! topology_is_name "$skill"; then
        topology_fail 2 "$label has an invalid override skill name: $skill"
        return 2
      fi
      topology_validate_destinations "$file" ".sources[$index].overrides[\"$skill\"]" "$label override $skill" || return $?
    done < <(jq -r ".sources[$index].overrides | keys[]" "$file")
  done
}

topology_validate_plugin() { # file index label classification
  local file="$1" index="$2" label="$3" classification="$4" destination value supported
  if ! jq -e ".[${index}].plugin | type == \"object\"" "$file" >/dev/null 2>&1; then
    topology_fail 2 "$label requires plugin metadata for a plugin source"
    return 2
  fi
  topology_validate_fields "$file" ".[${index}].plugin" '["name","repo","marketplaces","identifiers","skills"]' '["name","repo","marketplaces","skills"]' "$label plugin" || return $?
  value="$(jq -r ".[${index}].plugin.name" "$file")"
  jq -e ".[${index}].plugin.name | type == \"string\"" "$file" >/dev/null \
    && topology_is_name "$value" \
    || { topology_fail 2 "$label plugin has an invalid name"; return 2; }
  value="$(jq -r ".[${index}].plugin.repo" "$file")"
  jq -e ".[${index}].plugin.repo | type == \"string\"" "$file" >/dev/null \
    && [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || { topology_fail 2 "$label plugin has an invalid repo"; return 2; }
  if ! jq -e ".[${index}].plugin.marketplaces | type == \"object\" and length > 0" "$file" >/dev/null; then
    topology_fail 2 "$label plugin marketplaces must be a non-empty object"
    return 2
  fi
  while IFS= read -r destination; do
    case "$destination" in
      claude|codex) ;;
      *) topology_fail 2 "$label plugin marketplaces contains unknown destination: $destination"; return 2 ;;
    esac
    supported="$(jq -r --arg destination "$destination" ".[${index}].supportedDestinations | index(\$destination) != null" "$file")"
    if { [ "$classification" = plugin-claude-only ] && [ "$destination" != claude ]; } || [ "$supported" != true ]; then
      topology_fail 2 "$label plugin marketplaces contains unsupported destination: $destination"
      return 2
    fi
  done < <(jq -r ".[${index}].plugin.marketplaces | keys[]" "$file")
  if jq -e ".[${index}].plugin | has(\"identifiers\")" "$file" >/dev/null; then
    if ! jq -e ".[${index}].plugin.identifiers | type == \"object\" and length > 0" "$file" >/dev/null; then
      topology_fail 2 "$label plugin identifiers must be a non-empty object"
      return 2
    fi
    while IFS= read -r destination; do
      case "$destination" in
        claude|codex) ;;
        *) topology_fail 2 "$label plugin identifiers contains unknown destination: $destination"; return 2 ;;
      esac
      value="$(jq -r --arg destination "$destination" ".[${index}].plugin.identifiers[\$destination] // empty" "$file")"
      if ! jq -e --arg destination "$destination" ".[${index}].plugin.identifiers[\$destination] | type == \"string\"" "$file" >/dev/null \
        || ! topology_is_name "$value"; then
        topology_fail 2 "$label plugin has an invalid native $destination identifier"
        return 2
      fi
    done < <(jq -r ".[${index}].plugin.identifiers | keys[]" "$file")
  fi
  for destination in claude $([ "$classification" = dual-plugin ] && printf codex); do
    value="$(jq -r --arg destination "$destination" ".[${index}].plugin.marketplaces[\$destination] // empty" "$file")"
    if ! jq -e --arg destination "$destination" ".[${index}].plugin.marketplaces[\$destination] | type == \"string\"" "$file" >/dev/null \
      || ! topology_is_name "$value"; then
      topology_fail 2 "$label plugin is missing a valid $destination marketplace"
      return 2
    fi
  done
  if ! jq -e ".[${index}].plugin.skills | type == \"array\" and length > 0" "$file" >/dev/null; then
    topology_fail 2 "$label plugin skills must be a non-empty array"
    return 2
  fi
  if ! jq -e ".[${index}].plugin.skills | length == (unique | length)" "$file" >/dev/null; then
    topology_fail 2 "$label plugin skills contains a duplicate skill"
    return 2
  fi
  while IFS= read -r skill; do
    if ! topology_is_name "$skill"; then
      topology_fail 2 "$label plugin skills contains an invalid skill name: $skill"
      return 2
    fi
  done < <(jq -r ".[${index}].plugin.skills[] | tostring" "$file")
}

topology_validate_registry() { # file
  local file="$1" parse_error count index label source_id classification command normalized_command state plugin_kind
  if ! parse_error="$(jq empty "$file" 2>&1)"; then
    topology_fail 2 "topology adapter registry is not valid JSON: $parse_error"
    return 2
  fi
  if ! jq -e 'type == "array" and length > 0' "$file" >/dev/null; then
    topology_fail 2 'topology adapter registry must be a non-empty array'
    return 2
  fi
  if ! jq -e '[.[].sourceId] | length == (unique | length)' "$file" >/dev/null; then
    source_id="$(jq -r '[.[].sourceId] | group_by(.)[] | select(length > 1) | first' "$file" | head -1)"
    topology_fail 2 "topology adapter registry contains duplicate sourceId: $source_id"
    return 2
  fi
  count="$(jq 'length' "$file")"
  for ((index = 0; index < count; index++)); do
    label="topology adapter registry entry $index"
    topology_validate_fields "$file" ".[$index]" '["sourceId","classification","supportedDestinations","command","stateInspection","plugin"]' '["sourceId","classification","supportedDestinations","command"]' "$label" || return $?
    source_id="$(jq -r ".[$index].sourceId" "$file")"
    jq -e ".[$index].sourceId | type == \"string\"" "$file" >/dev/null \
      && topology_is_name "$source_id" \
      || { topology_fail 2 "$label has an invalid sourceId"; return 2; }
    classification="$(jq -r ".[$index].classification" "$file")"
    topology_is_classification "$classification" || { topology_fail 2 "$label contains unknown classification: $classification"; return 2; }
    topology_validate_destinations "$file" ".[$index].supportedDestinations" "$label supportedDestinations" || return $?
    command="$(jq -r ".[$index].command" "$file")"
    normalized_command="${command//\\//}"
    if ! jq -e ".[$index].command | type == \"string\"" "$file" >/dev/null \
      || [ -z "$command" ] || [[ "$command" = /* ]] || [[ "/$normalized_command/" = *'/../'* ]]; then
      topology_fail 2 "$label has an invalid command"
      return 2
    fi
    state="$(jq -r "if .[$index] | has(\"stateInspection\") then .[$index].stateInspection else \"topology\" end" "$file")"
    case "$state" in topology|adapter) ;; *) topology_fail 2 "$label has an invalid stateInspection"; return 2 ;; esac
    plugin_kind=0
    case "$classification" in dual-plugin|plugin-claude-only) plugin_kind=1 ;; esac
    if [ "$plugin_kind" -eq 1 ]; then
      topology_validate_plugin "$file" "$index" "$label" "$classification" || return $?
    elif jq -e ".[$index] | has(\"plugin\")" "$file" >/dev/null; then
      topology_fail 2 "$label has plugin metadata for a non-plugin source"
      return 2
    fi
  done
}
