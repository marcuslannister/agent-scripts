#!/usr/bin/env bash
set -uo pipefail

MODULE_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd "$MODULE_DIR/../.." && pwd)"
MANIFEST_PATH="$REPO_ROOT/skill-topology.json"
REGISTRY_PATH="$MODULE_DIR/registry.json"

source "$MODULE_DIR/errors.sh"
source "$MODULE_DIR/lock.sh"
source "$MODULE_DIR/schema.sh"
source "$MODULE_DIR/state.sh"
source "$MODULE_DIR/report.sh"

MODE=reconcile
JSON_OUTPUT=0
REQUESTED_JSON=0
INTERRUPTED=0
ACTIVE_CHILD=
DISCOVERY_ROOT=
DOCUMENT_PATH=
PROCESS_SEQUENCE=0
PROCESS_OUT=
PROCESS_ERR=
PROCESS_CODE=0

topology_append_json_string() { # file value
  jq -Rn --arg value "$2" '$value' >> "$1"
}

topology_trim() { # value
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

topology_add_process_errors() { # output_file prefix destination
  local output_file="$1" prefix="$2" destination="$3" line found=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(topology_trim "$line")"
    [ -n "$line" ] || continue
    topology_append_json_string "$destination" "$prefix: $line"
    found=1
  done < "$output_file"
  [ "$found" -eq 1 ] || topology_append_json_string "$destination" "$prefix"
}

topology_run_process() { # command args...
  local command="$1" wait_code
  shift
  PROCESS_SEQUENCE=$((PROCESS_SEQUENCE + 1))
  PROCESS_OUT="$DISCOVERY_ROOT/process-$PROCESS_SEQUENCE.out"
  PROCESS_ERR="$DISCOVERY_ROOT/process-$PROCESS_SEQUENCE.err"
  "$command" "$@" > "$PROCESS_OUT" 2> "$PROCESS_ERR" &
  ACTIVE_CHILD=$!
  wait "$ACTIVE_CHILD"
  wait_code=$?
  ACTIVE_CHILD=
  PROCESS_CODE="$wait_code"
  if [ "$INTERRUPTED" -eq 1 ]; then
    topology_fail 130 interrupted
    return 130
  fi
}

topology_decode_hex() { # encoded
  local encoded="$1"
  [[ "$encoded" =~ ^([0-9a-f][0-9a-f])*$ ]] || return 1
  printf '%b' "$(printf '%s' "$encoded" | sed 's/../\\x&/g')"
}

topology_inspect_hygiene() { # output_directory
  local output="$1" line record encoded kind extra name status
  mkdir -p "$output"
  : > "$output/entries.ndjson"
  : > "$output/errors.ndjson"
  topology_run_process "$MODULE_DIR/codex-root-hygiene.sh" inspect "$HOME" || return $?
  if [ "$PROCESS_CODE" -ne 0 ]; then
    topology_add_process_errors "$PROCESS_ERR" 'Codex-root hygiene inspection failed' "$output/errors.ndjson"
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    IFS=$'\t' read -r record encoded kind extra <<< "$line"
    case "$kind" in root-symlink|root-file|directory|symlink|file|other) ;; *) kind=invalid ;; esac
    if [ "$record" != entry ] || [ -n "${extra:-}" ] || [ "$kind" = invalid ] || ! name="$(topology_decode_hex "$encoded")"; then
      topology_append_json_string "$output/errors.ndjson" 'Codex-root hygiene returned invalid inspection output'
      continue
    fi
    jq -cn --arg name "$name" --arg kind "$kind" '{name:$name,kind:$kind}' >> "$output/entries.ndjson"
  done < "$PROCESS_OUT"
  if [ -s "$output/errors.ndjson" ]; then status=failed
  elif [ -s "$output/entries.ndjson" ]; then status=drift
  else status=clean
  fi
  jq -n \
    --arg status "$status" \
    --arg legacyRoot "$HOME/.codex/skills" \
    --slurpfile entries "$output/entries.ndjson" \
    --slurpfile errors "$output/errors.ndjson" \
    '{status:$status,legacyRoot:$legacyRoot,entries:($entries|sort_by(.name)),changes:[],errors:$errors}' \
    > "$output/hygiene.json"
}

topology_write_native_allowlist() {
  jq -r --slurpfile registry "$REGISTRY_PATH" '
    .sources[] as $source |
    $registry[0][] | select(.sourceId == $source.id and (.plugin? != null)) |
    .plugin as $plugin | .plugin.marketplaces | to_entries[] |
    "\(.key)\t\($plugin.name)@\(.value)"
  ' "$MANIFEST_PATH" | LC_ALL=C sort > "$DISCOVERY_ROOT/native-plugins.tsv"
}

topology_registry_value() { # source_id jq_suffix
  jq -r --arg source "$1" ".[] | select(.sourceId == \$source) | $2" "$REGISTRY_PATH"
}

topology_manifest_value() { # source_id jq_suffix
  jq -r --arg source "$1" ".sources[] | select(.id == \$source) | $2" "$MANIFEST_PATH"
}

topology_claimed_by_other() { # plan source skill destination
  jq -e --arg source "$2" --arg skill "$3" --arg destination "$4" '
    any(.sourceId != $source and .skill == $skill and (.destinations | index($destination) != null))
  ' "$1" >/dev/null
}

topology_expected_states() { # source_id output_tsv plan_json
  local source_id="$1" output="$2" plan_json="$3" skill destination desired
  : > "$output"
  while IFS= read -r skill; do
    while IFS= read -r destination; do
      [ "$source_id" = repo-claude ] && [ "$destination" = claude ] && continue
      desired="$(jq -r --arg source "$source_id" --arg skill "$skill" --arg destination "$destination" '
        .[] | select(.sourceId == $source and .skill == $skill) | (.destinations | index($destination) != null)
      ' "$plan_json")"
      if [ "$desired" != true ] && topology_claimed_by_other "$plan_json" "$source_id" "$skill" "$destination"; then
        continue
      fi
      [ "$desired" = true ] && printf 'present\t%s\t%s\n' "$skill" "$destination" >> "$output" \
        || printf 'absent\t%s\t%s\n' "$skill" "$destination" >> "$output"
    done < <(topology_registry_value "$source_id" '.supportedDestinations[]')
  done < <(jq -r --arg source "$source_id" '.[] | select(.sourceId == $source) | .skill' "$plan_json")
}

topology_seen() { # seen_file key
  rg -Fxq -- "$2" "$1"
}

topology_mark_seen() { # seen_file key
  printf '%s\n' "$2" >> "$1"
}

topology_inspect_adapter() { # source_id plan_json output_dir mode
  local source_id="$1" plan_json="$2" output="$3" mode="$4"
  local expected="$DISCOVERY_ROOT/$source_id.inspect.tsv" command line state skill destination detail extra key detail_key
  local seen_file="$DISCOVERY_ROOT/$source_id.seen"
  : > "$seen_file"
  topology_expected_states "$source_id" "$expected" "$plan_json"
  command="$MODULE_DIR/$(topology_registry_value "$source_id" '.command')"
  topology_run_process "$command" "$source_id" "$REPO_ROOT" "$DISCOVERY_ROOT" inspect "$expected" "$HOME" "$mode" || return $?
  if [ "$PROCESS_CODE" -ne 0 ]; then
    topology_add_process_errors "$PROCESS_ERR" "source $source_id inspection failed" "$output/errors.ndjson"
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    IFS=$'\t' read -r state skill destination detail extra <<< "$line"
    if [ -n "${extra:-}" ] || ! topology_is_name "${skill:-}" \
      || { [ "$destination" != claude ] && [ "$destination" != codex ]; } || [ -z "${detail:-}" ]; then
      topology_append_json_string "$output/errors.ndjson" "source $source_id returned invalid inspection output"
      continue
    fi
    key="$skill"$'\034'"$destination"
    case "$state" in
      decision)
        detail_key="decision"$'\034'"$destination"$'\034'"$detail"
        if [[ ! "$detail" =~ ^[a-z0-9]+(-[a-z0-9]+)*@[a-z0-9]+(-[a-z0-9]+)*$ ]] || topology_seen "$seen_file" "$detail_key"; then
          topology_append_json_string "$output/errors.ndjson" "source $source_id returned invalid decision inspection output"
          continue
        fi
        topology_mark_seen "$seen_file" "$detail_key"
        jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" --arg pluginId "$detail" \
          '{code:"unknown-installed-plugin",sourceId:$sourceId,skill:$skill,destination:$destination,pluginId:$pluginId,message:("installed third-party plugin " + $pluginId + " on " + $destination + " is not listed in skill-topology.json")}' \
          >> "$output/decisions.ndjson"
        ;;
      npx-decision)
        detail_key="npx"$'\034'"$skill"$'\034'"$destination"
        if [[ ! "$detail" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || topology_seen "$seen_file" "$detail_key"; then
          topology_append_json_string "$output/errors.ndjson" "source $source_id returned invalid npx decision inspection output"
          continue
        fi
        topology_mark_seen "$seen_file" "$detail_key"
        jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" --arg lockSource "$detail" \
          '{code:"unknown-npx-lock-source",sourceId:$sourceId,skill:$skill,destination:$destination,lockSource:$lockSource,message:("skills lock entry " + $skill + " belongs to unknown npx source " + $lockSource)}' \
          >> "$output/decisions.ndjson"
        ;;
      orphan)
        detail_key="orphan"$'\034'"$key"
        if rg -q -F $'\t'"$skill"$'\t'"$destination" "$expected" || topology_seen "$seen_file" "$detail_key"; then
          topology_append_json_string "$output/errors.ndjson" "source $source_id returned invalid orphan inspection output"
          continue
        fi
        topology_mark_seen "$seen_file" "$detail_key"
        jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
          '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:"unexpected"}' >> "$output/drift.ndjson"
        ;;
      present|absent|drift|outdated|foreign|error)
        if ! rg -q -F $'\t'"$skill"$'\t'"$destination" "$expected" || topology_seen "$seen_file" "$key"; then
          topology_append_json_string "$output/errors.ndjson" "source $source_id returned invalid inspection output"
          continue
        fi
        topology_mark_seen "$seen_file" "$key"
        local_expected="$(awk -F '\t' -v skill="$skill" -v destination="$destination" '$2 == skill && $3 == destination { print $1; exit }' "$expected")"
        case "$state" in
          error) topology_append_json_string "$output/errors.ndjson" "cannot verify $source_id/$skill on $destination: $detail" ;;
          foreign)
            if [ "$local_expected" = present ]; then
              jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
                '{code:"surface-ownership-collision",sourceId:$sourceId,skill:$skill,destination:$destination,message:($skill + " exists on " + $destination + " but is not the managed " + $sourceId + " copy")}' \
                >> "$output/decisions.ndjson"
            else
              jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" --arg reason "$detail" \
                '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:$reason}' >> "$output/skipped.ndjson"
            fi
            ;;
          absent)
            [ "$local_expected" = present ] && jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
              '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:"missing"}' >> "$output/drift.ndjson"
            ;;
          drift)
            if [ "$local_expected" = present ]; then reason="$detail"; else reason=unexpected; fi
            jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" --arg reason "$reason" \
              '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:$reason}' >> "$output/drift.ndjson"
            ;;
          outdated)
            if [ "$local_expected" != present ]; then
              topology_append_json_string "$output/errors.ndjson" "source $source_id returned invalid outdated inspection output"
              continue
            fi
            jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" --arg detail "$detail" \
              '{kind:"outdated",sourceId:$sourceId,skill:$skill,destination:$destination,reason:("outdated: " + $detail)}' \
              >> "$output/drift.ndjson"
            ;;
          present)
            [ "$local_expected" = absent ] && jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
              '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:"unexpected"}' >> "$output/drift.ndjson"
            ;;
        esac
        ;;
      *) topology_append_json_string "$output/errors.ndjson" "source $source_id returned invalid inspection output" ;;
    esac
  done < "$PROCESS_OUT"

  while IFS=$'\t' read -r state skill destination; do
    key="$skill"$'\034'"$destination"
    topology_seen "$seen_file" "$key" || topology_append_json_string "$output/errors.ndjson" \
      "source $source_id returned incomplete inspection for $skill -> $destination"
  done < "$expected"
}

topology_inspect_plan() { # plan_json output_dir mode
  local plan_json="$1" output="$2" mode="$3" source_id skill destination desired reason retired retired_source
  mkdir -p "$output"
  : > "$output/drift.ndjson"
  : > "$output/decisions.ndjson"
  : > "$output/errors.ndjson"
  : > "$output/skipped.ndjson"

  while IFS=$'\t' read -r source_id skill; do
    [ "$(topology_registry_value "$source_id" '.stateInspection // "topology"')" = adapter ] && continue
    while IFS= read -r destination; do
      desired="$(jq -r --arg source "$source_id" --arg skill "$skill" --arg destination "$destination" '
        .[] | select(.sourceId == $source and .skill == $skill) | (.destinations | index($destination) != null)
      ' "$plan_json")"
      if [ "$desired" != true ] && topology_claimed_by_other "$plan_json" "$source_id" "$skill" "$destination"; then continue; fi
      topology_inspect_destination "$source_id" "$skill" "$destination"
      case "$DESTINATION_KIND" in
        foreign)
          if [ "$desired" = true ]; then
            jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
              '{code:"surface-ownership-collision",sourceId:$sourceId,skill:$skill,destination:$destination,message:($skill + " exists on " + $destination + " but is not the managed " + $sourceId + " copy")}' >> "$output/decisions.ndjson"
          else
            jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" --arg reason "$DESTINATION_REASON" \
              '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:$reason}' >> "$output/skipped.ndjson"
          fi
          ;;
        verification-failed) topology_append_json_string "$output/errors.ndjson" "$DESTINATION_MESSAGE" ;;
        absent)
          [ "$desired" = true ] && jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
            '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:"missing"}' >> "$output/drift.ndjson"
          ;;
        managed|canonical)
          if [ "$desired" = true ] && [ -n "$DESTINATION_REASON" ]; then reason="$DESTINATION_REASON"
          elif [ "$desired" != true ] && [ "$DESTINATION_KIND" != canonical ]; then reason=unexpected
          else continue
          fi
          jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" --arg reason "$reason" \
            '{sourceId:$sourceId,skill:$skill,destination:$destination,reason:$reason}' >> "$output/drift.ndjson"
          ;;
      esac
    done < <(topology_registry_value "$source_id" '.supportedDestinations[]')
  done < <(jq -r '.[] | [.sourceId,.skill] | @tsv' "$plan_json")

  while IFS= read -r retired; do
    jq -e --arg skill "$retired" 'any(.skill == $skill and (.destinations | index("codex") != null))' "$plan_json" >/dev/null && continue
    jq -s -e --arg skill "$retired" 'any(.[]; .skill == $skill and .destination == "codex")' "$output/drift.ndjson" >/dev/null && continue
    retired_source="$(jq -r --arg skill "$retired" '[.[] | select(.skill == $skill) | .sourceId][0] // "repo-claude"' "$plan_json")"
    jq -cn --arg sourceId "$retired_source" --arg skill "$retired" \
      '{sourceId:$sourceId,skill:$skill,destination:"codex",reason:"unexpected"}' >> "$output/drift.ndjson"
  done < <(topology_list_retired_copies | LC_ALL=C sort)

  while IFS= read -r source_id; do
    [ "$(topology_registry_value "$source_id" '.stateInspection // "topology"')" = adapter ] || continue
    topology_inspect_adapter "$source_id" "$plan_json" "$output" "$mode" || return $?
  done < <(jq -r '.[].sourceId' "$REGISTRY_PATH")
}

topology_build_document() { # mode status sources plan inspect errors warnings changes hygiene output
  local mode="$1" status="$2" sources="$3" plan="$4" inspect="$5" errors="$6" warnings="$7" changes="$8" hygiene="$9" output="${10}"
  jq -n \
    --arg mode "$mode" --arg status "$status" \
    --slurpfile sources "$sources" --slurpfile plan "$plan" \
    --slurpfile drift "$inspect/drift.ndjson" --slurpfile decisions "$inspect/decisions.ndjson" \
    --slurpfile errors "$errors" --slurpfile warnings "$warnings" --slurpfile changes "$changes" \
    --slurpfile skipped "$inspect/skipped.ndjson" --slurpfile hygiene "$hygiene" '
      ($drift | sort_by(.sourceId,.skill,.destination)) as $sortedDrift |
      {
        schemaVersion:1, mode:$mode, status:$status,
        sources:$sources,
        plan:($plan | map(. as $item |
          .missingDestinations = [$sortedDrift[] | select(.sourceId == $item.sourceId and .skill == $item.skill and .reason == "missing") | .destination] |
          .unexpectedDestinations = [$sortedDrift[] | select(.sourceId == $item.sourceId and .skill == $item.skill and .reason == "unexpected") | .destination])),
        drift:$sortedDrift,
        decisions:($decisions | sort_by((.code + "~"),((.sourceId // (.sourceIds | join(",")) // "") + "~"),((.skill // "") + "~"),((.destination // "") + "~"))),
        errors:$errors,warnings:$warnings,
        changes:(if $mode == "check" then
          ($changes + [$sortedDrift[] | select(.kind == "outdated") |
            {action:"updated",sourceId,skill,destination}])
          else $changes end),
        skipped:($skipped | sort_by(.sourceId,.skill,.destination)),
        hygiene:$hygiene[0]
      }
    ' > "$output"
}

topology_evaluate() {
  local source_id classification registry_classification adapter_command inventory_file skill destinations_json
  local supported_json defaults_json source_count plan_json inspect_dir hygiene_dir status exit_code
  local sources_file="$DISCOVERY_ROOT/sources.ndjson" plan_file="$DISCOVERY_ROOT/plan.ndjson"
  local base_errors="$DISCOVERY_ROOT/base-errors.ndjson" warnings="$DISCOVERY_ROOT/warnings.ndjson" changes="$DISCOVERY_ROOT/changes.ndjson"
  : > "$sources_file"; : > "$plan_file"; : > "$base_errors"; : > "$warnings"; : > "$changes"

  topology_validate_manifest "$MANIFEST_PATH" || return $?
  topology_validate_registry "$REGISTRY_PATH" || return $?

  while IFS= read -r source_id; do
    if ! jq -e --arg source "$source_id" 'any(.[]; .sourceId == $source)' "$REGISTRY_PATH" >/dev/null; then
      topology_fail 2 "manifest source has no registered adapter: $source_id"
      return 2
    fi
    classification="$(topology_manifest_value "$source_id" '.classification')"
    registry_classification="$(topology_registry_value "$source_id" '.classification')"
    if [ "$classification" != "$registry_classification" ]; then
      topology_fail 2 "source classification mismatch for $source_id: manifest=$classification, registry=$registry_classification"
      return 2
    fi
  done < <(jq -r '.sources[].id' "$MANIFEST_PATH")

  topology_inspect_hygiene "$DISCOVERY_ROOT/hygiene-initial" || return $?
  topology_write_native_allowlist
  : > "$DISCOVERY_ROOT/pre-decisions.ndjson"

  while IFS= read -r source_id; do
    if ! jq -e --arg source "$source_id" 'any(.sources[]; .id == $source)' "$MANIFEST_PATH" >/dev/null; then
      jq -cn --arg sourceId "$source_id" '{code:"adapter-without-policy",sourceId:$sourceId,message:("registered adapter has no manifest policy: " + $sourceId)}' \
        >> "$DISCOVERY_ROOT/pre-decisions.ndjson"
    fi
  done < <(jq -r '.[].sourceId' "$REGISTRY_PATH")

  while IFS= read -r source_id; do
    classification="$(topology_manifest_value "$source_id" '.classification')"
    while IFS= read -r destination; do
      if ! jq -e --arg source "$source_id" --arg destination "$destination" '.[] | select(.sourceId == $source) | .supportedDestinations | index($destination) != null' "$REGISTRY_PATH" >/dev/null; then
        jq -cn --arg sourceId "$source_id" --arg destination "$destination" \
          '{code:"unsupported-destination",sourceId:$sourceId,destination:$destination,message:($sourceId + " does not support its default destination " + $destination)}' \
          >> "$DISCOVERY_ROOT/pre-decisions.ndjson"
      fi
    done < <(topology_manifest_value "$source_id" '.defaultDestinations[]')
    while IFS=$'\t' read -r skill destination; do
      if ! jq -e --arg source "$source_id" --arg destination "$destination" '.[] | select(.sourceId == $source) | .supportedDestinations | index($destination) != null' "$REGISTRY_PATH" >/dev/null; then
        jq -cn --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
          '{code:"unsupported-destination",sourceId:$sourceId,skill:$skill,destination:$destination,message:($sourceId + " cannot distribute " + $skill + " to " + $destination)}' \
          >> "$DISCOVERY_ROOT/pre-decisions.ndjson"
      fi
    done < <(jq -r --arg source "$source_id" '.sources[] | select(.id == $source) | .overrides | to_entries[] | .key as $skill | .value[] | [$skill,.] | @tsv' "$MANIFEST_PATH")

    inventory_file="$DISCOVERY_ROOT/$source_id.inventory"
    adapter_command="$MODULE_DIR/$(topology_registry_value "$source_id" '.command')"
    topology_run_process "$adapter_command" "$source_id" "$REPO_ROOT" "$DISCOVERY_ROOT" discover '' "$HOME" "$MODE" || return $?
    if [ "$PROCESS_CODE" -ne 0 ]; then
      detail="$(topology_trim "$(cat "$PROCESS_ERR")")"
      topology_fail 1 "source $source_id discovery failed${detail:+: $detail}"
      return 1
    fi
    LC_ALL=C sort "$PROCESS_OUT" | awk 'NF' > "$inventory_file"
    if [ "$(LC_ALL=C sort -u "$inventory_file" | wc -l | tr -d ' ')" != "$(wc -l < "$inventory_file" | tr -d ' ')" ]; then
      topology_fail 1 "source $source_id returned an invalid inventory"; return 1
    fi
    while IFS= read -r skill; do topology_is_name "$skill" || { topology_fail 1 "source $source_id returned an invalid inventory"; return 1; }; done < "$inventory_file"
    while IFS= read -r skill; do
      rg -Fxq "$skill" "$inventory_file" || jq -cn --arg sourceId "$source_id" --arg skill "$skill" \
        '{code:"stale-override",sourceId:$sourceId,skill:$skill,message:("override names a skill absent from " + $sourceId + ": " + $skill)}' >> "$DISCOVERY_ROOT/pre-decisions.ndjson"
    done < <(topology_manifest_value "$source_id" '.overrides | keys[]')
    while IFS= read -r skill; do
      destinations_json="$(jq -c --arg source "$source_id" --arg skill "$skill" '
        (.sources[] | select(.id == $source) | (.overrides[$skill] // .defaultDestinations)) as $wanted |
        ["claude","codex"] | map(select(. as $destination | $wanted | index($destination) != null))
      ' "$MANIFEST_PATH")"
      jq -cn --arg sourceId "$source_id" --arg skill "$skill" --argjson destinations "$destinations_json" \
        '{sourceId:$sourceId,skill:$skill,destinations:$destinations,missingDestinations:[],unexpectedDestinations:[]}' >> "$plan_file"
    done < "$inventory_file"
    defaults_json="$(topology_manifest_value "$source_id" '["claude","codex"] as $order | .defaultDestinations as $wanted | [$order[] | select(. as $d | $wanted | index($d) != null)]')"
    supported_json="$(topology_registry_value "$source_id" '["claude","codex"] as $order | .supportedDestinations as $wanted | [$order[] | select(. as $d | $wanted | index($d) != null)]')"
    source_count="$(wc -l < "$inventory_file" | tr -d ' ')"
    jq -cn --arg id "$source_id" --arg classification "$classification" --argjson inventoryCount "$source_count" \
      --argjson defaults "$defaults_json" --argjson supported "$supported_json" \
      '{id:$id,classification:$classification,inventoryCount:$inventoryCount,defaultDestinations:$defaults,supportedDestinations:$supported,result:"clean"}' >> "$sources_file"
  done < <(jq -r '.sources | sort_by(.id) | .[].id' "$MANIFEST_PATH")

  topology_progress 2 'Planning topology'
  jq -s '.' "$plan_file" > "$DISCOVERY_ROOT/plan.json"
  plan_json="$DISCOVERY_ROOT/plan.json"
  jq -c '
    [.[] as $entry | $entry.destinations[] as $destination | {skill:$entry.skill,destination:$destination,sourceId:$entry.sourceId}]
    | group_by([.skill,.destination])[] | select(length > 1)
    | {code:"surface-collision",sourceIds:(map(.sourceId)|sort),skill:.[0].skill,destination:.[0].destination,
       message:(.[0].skill + " is claimed by multiple sources on " + .[0].destination + ": " + (map(.sourceId)|sort|join(", ")))}
  ' "$plan_json" >> "$DISCOVERY_ROOT/pre-decisions.ndjson"

  if [ "$MODE" = check ]; then
    topology_progress 3 'Inspecting adapters'
  else
    topology_progress 3 'Executing adapters'
  fi
  inspect_dir="$DISCOVERY_ROOT/inspect-initial"
  topology_inspect_plan "$plan_json" "$inspect_dir" "$MODE" || return $?
  [ -s "$DISCOVERY_ROOT/pre-decisions.ndjson" ] && cat "$DISCOVERY_ROOT/pre-decisions.ndjson" >> "$inspect_dir/decisions.ndjson"
  cat "$DISCOVERY_ROOT/hygiene-initial/errors.ndjson" >> "$inspect_dir/errors.ndjson"
  cp "$inspect_dir/errors.ndjson" "$base_errors"

  if [ -s "$inspect_dir/decisions.ndjson" ]; then status=decision-required; exit_code=3
  elif [ -s "$inspect_dir/errors.ndjson" ]; then status=failed; exit_code=1
  elif [ -s "$inspect_dir/drift.ndjson" ] || [ -s "$DISCOVERY_ROOT/hygiene-initial/entries.ndjson" ]; then status=drift; exit_code=1
  else status=clean; exit_code=0
  fi

  # Rewrite NDJSON source results without losing one-object-per-line form.
  jq -s -c --slurpfile decisions "$inspect_dir/decisions.ndjson" --slurpfile drift "$inspect_dir/drift.ndjson" \
    --slurpfile errors "$inspect_dir/errors.ndjson" '
    .[] as $source | $source + {result:
      (if any($decisions[]; .sourceId == $source.id or ((.sourceIds? // []) | index($source.id) != null)) then "decision-required"
       elif any($errors[]; contains($source.id + "/") or contains("source " + $source.id + " ")) then "failed"
       elif any($drift[]; .sourceId == $source.id) then "drift" else "clean" end)}
  ' "$sources_file" > "$DISCOVERY_ROOT/sources-updated.ndjson"
  mv "$DISCOVERY_ROOT/sources-updated.ndjson" "$sources_file"

  if [ "$MODE" = reconcile ] && [ "$exit_code" -ne 3 ] && [ ! -s "$inspect_dir/errors.ndjson" ]; then
    topology_reconcile "$sources_file" "$plan_file" "$plan_json" "$inspect_dir" "$warnings" "$changes"
    return $?
  fi
  topology_progress 4 'Final verification'
  topology_build_document "$MODE" "$status" "$sources_file" "$plan_file" "$inspect_dir" "$base_errors" "$warnings" "$changes" "$DISCOVERY_ROOT/hygiene-initial/hygiene.json" "$DISCOVERY_ROOT/document.json"
  DOCUMENT_PATH="$DISCOVERY_ROOT/document.json"
  return "$exit_code"
}

topology_reconcile() { # sources plan_ndjson plan_json initial_inspect warnings changes
  local sources="$1" plan_file="$2" plan_json="$3" initial="$4" warnings="$5" changes="$6"
  local errors="$DISCOVERY_ROOT/reconcile-errors.ndjson" source_id action_file expected_file command line action skill destination extra
  local hygiene_dir="$DISCOVERY_ROOT/hygiene-reconcile" final_hygiene="$DISCOVERY_ROOT/hygiene-final" final_inspect="$DISCOVERY_ROOT/inspect-final"
  local status exit_code reason
  : > "$errors"; : > "$changes"

  topology_run_process "$MODULE_DIR/codex-root-hygiene.sh" reconcile "$HOME" || return $?
  mkdir -p "$hygiene_dir"; : > "$hygiene_dir/changes.ndjson"; : > "$hygiene_dir/errors.ndjson"
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    IFS=$'\t' read -r action encoded kind backup extra <<< "$line"
    if [ "$action" != migrated ] || [ -n "${extra:-}" ] || ! name="$(topology_decode_hex "$encoded")" || ! backup_path="$(topology_decode_hex "$backup")"; then
      topology_append_json_string "$hygiene_dir/errors.ndjson" 'Codex-root hygiene returned invalid reconcile output'
      continue
    fi
    jq -cn --arg name "$name" --arg kind "$kind" --arg backupPath "$backup_path" '{name:$name,kind:$kind,backupPath:$backupPath}' >> "$hygiene_dir/changes.ndjson"
  done < "$PROCESS_OUT"
  [ "$PROCESS_CODE" -eq 0 ] || topology_add_process_errors "$PROCESS_ERR" 'Codex-root hygiene reconciliation failed' "$hygiene_dir/errors.ndjson"
  cat "$hygiene_dir/errors.ndjson" >> "$errors"

  while IFS= read -r source_id; do
    action_file="$DISCOVERY_ROOT/$source_id.reconcile.tsv"
    : > "$action_file"
    jq -r --arg source "$source_id" --slurpfile plan "$plan_json" '
      .[] | select(.sourceId == $source) as $drift |
      ([$plan[0][] | select(.sourceId == $drift.sourceId and .skill == $drift.skill)][0] // null) as $entry |
      [(if $drift.kind == "outdated" then "refresh"
        elif $entry == null then "remove"
        elif ($entry.destinations | index($drift.destination)) != null then "install"
        else "remove" end),$drift.skill,$drift.destination] | @tsv
    ' "$initial/drift.ndjson" --slurp >> "$action_file"
    if [ "$(topology_registry_value "$source_id" '.classification')" = plugin-both ]; then
      topology_expected_states "$source_id" "$DISCOVERY_ROOT/$source_id.refresh-states.tsv" "$plan_json"
      while IFS=$'\t' read -r state skill destination; do
        [ "$state" = present ] || continue
        rg -q -F $'\t'"$skill"$'\t'"$destination" "$action_file" || printf 'refresh\t%s\t%s\n' "$skill" "$destination" >> "$action_file"
      done < "$DISCOVERY_ROOT/$source_id.refresh-states.tsv"
    fi
    LC_ALL=C sort -t $'\t' -k2,2 -k3,3 "$action_file" -o "$action_file"
    command="$MODULE_DIR/$(topology_registry_value "$source_id" '.command')"
    topology_run_process "$command" "$source_id" "$REPO_ROOT" "$DISCOVERY_ROOT" reconcile "$action_file" "$HOME" reconcile || return $?
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      IFS=$'\t' read -r action skill destination extra <<< "$line"
      if [ -n "${extra:-}" ] || { [ "$action" != installed ] && [ "$action" != removed ] && [ "$action" != updated ]; } \
        || ! topology_is_name "${skill:-}" || { [ "$destination" != claude ] && [ "$destination" != codex ]; }; then
        topology_append_json_string "$errors" "source $source_id returned invalid reconcile output"
        continue
      fi
      jq -cn --arg action "$action" --arg sourceId "$source_id" --arg skill "$skill" --arg destination "$destination" \
        '{action:$action,sourceId:$sourceId,skill:$skill,destination:$destination}' >> "$changes"
    done < "$PROCESS_OUT"
    [ "$PROCESS_CODE" -eq 0 ] || topology_add_process_errors "$PROCESS_ERR" "source $source_id reconciliation failed" "$errors"
  done < <(jq -r '.[].sourceId' "$REGISTRY_PATH" | LC_ALL=C sort)

  topology_progress 4 'Verifying final topology'
  while IFS= read -r source_id; do
    expected_file="$DISCOVERY_ROOT/$source_id.verify.tsv"
    topology_expected_states "$source_id" "$expected_file" "$plan_json"
    jq -r --arg source "$source_id" --slurpfile plan "$plan_json" '
      .[] | select(.sourceId == $source) as $drift |
      select(any($plan[0][]; .sourceId == $drift.sourceId and .skill == $drift.skill) | not) |
      ["absent",$drift.skill,$drift.destination] | @tsv
    ' "$initial/drift.ndjson" --slurp >> "$expected_file"
    LC_ALL=C sort -t $'\t' -k2,2 -k3,3 "$expected_file" -o "$expected_file"
    command="$MODULE_DIR/$(topology_registry_value "$source_id" '.command')"
    topology_run_process "$command" "$source_id" "$REPO_ROOT" "$DISCOVERY_ROOT" verify "$expected_file" "$HOME" reconcile || return $?
    [ ! -s "$PROCESS_OUT" ] || topology_append_json_string "$errors" "source $source_id returned invalid verification output"
    [ "$PROCESS_CODE" -eq 0 ] || topology_add_process_errors "$PROCESS_ERR" "source $source_id verification failed" "$errors"
  done < <(jq -r '.[].sourceId' "$REGISTRY_PATH" | LC_ALL=C sort)

  topology_inspect_plan "$plan_json" "$final_inspect" reconcile || return $?
  topology_inspect_hygiene "$final_hygiene" || return $?
  cat "$final_inspect/errors.ndjson" >> "$errors"
  cat "$final_hygiene/errors.ndjson" >> "$errors"
  while IFS=$'\t' read -r source_id skill destination reason; do
    topology_append_json_string "$errors" "final verification failed: $source_id/$skill -> $destination: $reason"
  done < <(jq -r '. | [.sourceId,.skill,.destination,.reason] | @tsv' "$final_inspect/drift.ndjson")
  while IFS=$'\t' read -r name kind; do
    topology_append_json_string "$errors" "final Codex-root hygiene verification failed: $name ($kind)"
    topology_append_json_string "$hygiene_dir/errors.ndjson" "final Codex-root hygiene verification failed: $name ($kind)"
  done < <(jq -r '. | [.name,.kind] | @tsv' "$final_hygiene/entries.ndjson")
  cat "$final_hygiene/errors.ndjson" >> "$hygiene_dir/errors.ndjson"

  if [ -s "$final_inspect/decisions.ndjson" ]; then status=decision-required; exit_code=3
  elif [ -s "$errors" ]; then status=failed; exit_code=1
  else status=reconciled; exit_code=0
  fi
  jq -n --arg status "$([ -s "$hygiene_dir/errors.ndjson" ] && printf failed || printf clean)" --arg root "$HOME/.codex/skills" \
    --slurpfile entries "$final_hygiene/entries.ndjson" --slurpfile changes "$hygiene_dir/changes.ndjson" --slurpfile errors "$hygiene_dir/errors.ndjson" \
    '{status:$status,legacyRoot:$root,entries:($entries|sort_by(.name)),changes:($changes|sort_by(.name)),errors:$errors}' > "$hygiene_dir/hygiene.json"
  jq -s -c --slurpfile decisions "$final_inspect/decisions.ndjson" --slurpfile drift "$final_inspect/drift.ndjson" --slurpfile changes "$changes" --slurpfile errors "$errors" '
    .[] as $source | $source + {result:
      (if any($decisions[]; .sourceId == $source.id) then "decision-required"
       elif any($errors[]; contains("source " + $source.id + " ")) or any($drift[]; .sourceId == $source.id) then "failed"
       elif any($changes[]; .sourceId == $source.id) then "changed" else "clean" end)}
  ' "$sources" > "$DISCOVERY_ROOT/sources-final.ndjson"
  topology_build_document reconcile "$status" "$DISCOVERY_ROOT/sources-final.ndjson" "$plan_file" "$final_inspect" "$errors" "$warnings" "$changes" "$hygiene_dir/hygiene.json" "$DISCOVERY_ROOT/document.json"
  DOCUMENT_PATH="$DISCOVERY_ROOT/document.json"
  return "$exit_code"
}

topology_interrupt() {
  [ "$INTERRUPTED" -eq 0 ] || return
  INTERRUPTED=1
  if [ -n "$ACTIVE_CHILD" ]; then
    kill -TERM "$ACTIVE_CHILD" 2>/dev/null || true
    wait "$ACTIVE_CHILD" 2>/dev/null || true
    ACTIVE_CHILD=
  fi
  if [ "$REQUESTED_JSON" -eq 1 ]; then
    topology_failure_document interrupted 130 "$MODE"
  else
    topology_write_human_failure interrupted 130 "$MODE"
  fi
  exit 130
}

topology_cleanup() {
  topology_release_lock
  [ -z "$DISCOVERY_ROOT" ] || rm -rf -- "$DISCOVERY_ROOT"
}

trap topology_interrupt INT TERM
trap topology_cleanup EXIT

for argument in "$@"; do [ "$argument" = --json ] && REQUESTED_JSON=1; done
if [ "$#" -eq 1 ] && { [ "$1" = --help ] || [ "$1" = -h ]; }; then
  topology_help
  exit 0
fi
check_count=0
json_count=0
for argument in "$@"; do
  case "$argument" in
    --check) check_count=$((check_count + 1)); MODE=check ;;
    --json) json_count=$((json_count + 1)); JSON_OUTPUT=1 ;;
    *) topology_fail 2 'invalid arguments; use --check only to preview the skill topology'; break ;;
  esac
done
if [ "$check_count" -gt 1 ] || [ "$json_count" -gt 1 ]; then topology_fail 2 'invalid arguments; use --check only to preview the skill topology'; fi
topology_init_color
if [ -n "$TOPOLOGY_ERROR_MESSAGE" ]; then
  if [ "$REQUESTED_JSON" -eq 1 ]; then topology_failure_document "$TOPOLOGY_ERROR_MESSAGE" "$TOPOLOGY_ERROR_CODE" "$MODE"
  else topology_write_human_failure "$TOPOLOGY_ERROR_MESSAGE" "$TOPOLOGY_ERROR_CODE" "$MODE"
  fi
  exit "$TOPOLOGY_ERROR_CODE"
fi

if ! topology_acquire_lock; then
  if [ "$REQUESTED_JSON" -eq 1 ]; then topology_failure_document "$TOPOLOGY_ERROR_MESSAGE" "$TOPOLOGY_ERROR_CODE" "$MODE"
  else topology_write_human_failure "$TOPOLOGY_ERROR_MESSAGE" "$TOPOLOGY_ERROR_CODE" "$MODE"
  fi
  exit "$TOPOLOGY_ERROR_CODE"
fi
DISCOVERY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-scripts-topology-discovery-XXXXXX")"

topology_progress 1 'Discovering sources'
topology_evaluate
result_code=$?
if { [ -n "$TOPOLOGY_RECOVERED_PID" ] || [ "$TOPOLOGY_RECOVERED_PENDING" -eq 1 ]; } && [ -n "$DOCUMENT_PATH" ]; then
  if [ -n "$TOPOLOGY_RECOVERED_PID" ]; then
    recovery_message="recovered stale topology lock held by PID $TOPOLOGY_RECOVERED_PID"
  else
    recovery_message="recovered stale topology lock with no recorded PID"
  fi
  jq --arg message "$recovery_message" '.warnings |= [{code:"stale-lock-recovered",message:$message}] + .' "$DOCUMENT_PATH" > "$DOCUMENT_PATH.tmp"
  mv "$DOCUMENT_PATH.tmp" "$DOCUMENT_PATH"
fi
if [ -n "$DOCUMENT_PATH" ]; then
  if [ "$JSON_OUTPUT" -eq 1 ]; then cat "$DOCUMENT_PATH"; else topology_write_human "$DOCUMENT_PATH"; fi
else
  [ -n "$TOPOLOGY_ERROR_MESSAGE" ] || topology_fail "$result_code" "$([ "$INTERRUPTED" -eq 1 ] && printf interrupted || printf 'topology failed')"
  if [ "$REQUESTED_JSON" -eq 1 ]; then topology_failure_document "$TOPOLOGY_ERROR_MESSAGE" "$TOPOLOGY_ERROR_CODE" "$MODE"
  else topology_write_human_failure "$TOPOLOGY_ERROR_MESSAGE" "$TOPOLOGY_ERROR_CODE" "$MODE"
  fi
fi
exit "$result_code"
