#!/usr/bin/env bash

topology_is_name() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

read -r -d '' TOPOLOGY_SCHEMA_JQ <<'JQ' || true
def is_name: type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$");

def is_classification: . as $value | ["repo-owned", "npx-only", "source-only", "dual-plugin", "plugin-claude-only"] | index($value) != null;
def pretty_json($indent):
  if type == "object" then if length == 0 then "{}" else "{\n" + (to_entries | map((" " * ($indent + 2)) + (.key | tojson) + ": " + (.value | pretty_json($indent + 2))) | join(",\n")) + "\n" + (" " * $indent) + "}" end
  elif type == "array" then if length == 0 then "[]" else "[\n" + (map((" " * ($indent + 2)) + (. | pretty_json($indent + 2))) | join(",\n")) + "\n" + (" " * $indent) + "]" end
  else tojson end;
def raw_output: if type == "string" then . elif type == "object" or type == "array" then pretty_json(0) else tostring end;
def head_output: raw_output | split("\n")[0];

def fields_error($value; $allowed; $required; $label):
  ($value | type) as $type | ($value | if type == "object" then (keys - $allowed | first) else null end) as $unknown |
  ($required - ($value | if type == "object" then keys else [] end) | first) as $missing |
  if $type != "object" then
    "\($label) must be an object"
  elif $unknown != null then
    "\($label) contains unknown field: \($unknown)"
  elif $missing != null then
    "\($label) is missing required field: \($missing)"
  else
    null
  end;
def destinations_error($value; $label):
  ($value | type) as $type | ($value | if type == "array" then
    ([.[] | select(. != "claude" and . != "codex") | tostring] | first) else null end) as $unknown |
  if $type != "array" or ($value | length) == 0 then
    "\($label) must be a non-empty destination array"
  elif $unknown != null then
    "\($label) contains unknown destination: \($unknown)"
  elif ($value | length) != ($value | unique | length) then
    "\($label) contains a duplicate destination"
  else
    null
  end;
def duplicate_group($values): $values | group_by(.) | map(select(length > 1)) | first;

def manifest_source_error($index):
  .sources[$index] as $source |
  "skill topology manifest source \($index)" as $label |
  fields_error($source; ["id", "classification", "defaultDestinations"];
    ["id", "classification", "defaultDestinations"]; $label) as $error |
  if $error != null then
    $error
  elif ($source.id | is_name | not) then
    "\($label) has an invalid id"
  elif ($source.classification | is_classification | not) then
    "\($label) contains unknown classification: \($source.classification | raw_output)"
  else
    destinations_error($source.defaultDestinations; "\($label) defaultDestinations")
  end;

def validate_manifest:
  fields_error(.; ["version", "sources"]; ["version", "sources"]; "skill topology manifest") as $error |
  if $error != null then
    $error
  elif .version != 1 then
    "skill topology manifest version must be 1"
  elif ((.sources | type) != "array" or (.sources | length) == 0) then
    "skill topology manifest sources must be a non-empty array"
  else
    duplicate_group([.sources[] | select(type == "object") | .id]) as $duplicate |
    if $duplicate != null then
      "skill topology manifest contains duplicate source id: \($duplicate[0] | head_output)"
    else
      ([range(0; (.sources | length)) as $index | manifest_source_error($index) | select(. != null)] | first)
    end
  end;

def plugin_error($entry; $index):
  "topology adapter registry entry \($index)" as $label |
  $entry.plugin as $plugin |
  if ($plugin | type) != "object" then
    "\($label) requires plugin metadata for a plugin source"
  else
    fields_error($plugin; ["name", "repo", "marketplaces", "identifiers", "skills"];
      ["name", "repo", "marketplaces", "skills"]; "\($label) plugin") as $error |
    if $error != null then
      $error
    elif ($plugin.name | is_name | not) then
      "\($label) plugin has an invalid name"
    elif (($plugin.repo | type) != "string" or ($plugin.repo | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") | not)) then
      "\($label) plugin has an invalid repo"
    elif (($plugin.marketplaces | type) != "object" or ($plugin.marketplaces | length) == 0) then
      "\($label) plugin marketplaces must be a non-empty object"
    else
      ([$plugin.marketplaces | keys[] as $destination |
        if $destination != "claude" and $destination != "codex" then
          "\($label) plugin marketplaces contains unknown destination: \($destination)"
        elif ($entry.classification == "plugin-claude-only" and $destination != "claude") or
          (($entry.supportedDestinations | index($destination)) == null) then
          "\($label) plugin marketplaces contains unsupported destination: \($destination)"
        else empty end] | first) as $marketplace_error |
      if $marketplace_error != null then
        $marketplace_error
      elif ($plugin | has("identifiers")) and (($plugin.identifiers | type) != "object" or ($plugin.identifiers | length) == 0) then
        "\($label) plugin identifiers must be a non-empty object"
      else
        ([$plugin.identifiers // {} | keys[] as $destination |
          if $destination != "claude" and $destination != "codex" then
            "\($label) plugin identifiers contains unknown destination: \($destination)"
          elif ($plugin.identifiers[$destination] | is_name) | not then
            "\($label) plugin has an invalid native \($destination) identifier"
          else empty end] | first) as $identifier_error |
        (["claude"] + (if $entry.classification == "dual-plugin" then ["codex"] else [] end)) as $required_marketplaces |
        ([$required_marketplaces[] as $destination | select(
          ($plugin.marketplaces[$destination] | is_name) | not) | $destination] | first) as $missing_marketplace |
        if $identifier_error != null then
          $identifier_error
        elif $missing_marketplace != null then
          "\($label) plugin is missing a valid \($missing_marketplace) marketplace"
        elif (($plugin.skills | type) != "array" or ($plugin.skills | length) == 0) then
          "\($label) plugin skills must be a non-empty array"
        elif ($plugin.skills | length) != ($plugin.skills | unique | length) then
          "\($label) plugin skills contains a duplicate skill"
        else
          ([$plugin.skills[] | tostring | select(is_name | not)] | first) as $invalid_skill |
          if $invalid_skill != null then
            "\($label) plugin skills contains an invalid skill name: \($invalid_skill)"
          else
            null
          end
        end
      end
    end
  end;

def registry_entry_error($index):
  .[$index] as $entry |
  "topology adapter registry entry \($index)" as $label |
  fields_error($entry;
    ["sourceId", "classification", "supportedDestinations", "command", "stateInspection", "matrixSource", "plugin"];
    ["sourceId", "classification", "supportedDestinations", "command"]; $label) as $error |
  if $error != null then
    $error
  elif ($entry.sourceId | is_name | not) then
    "\($label) has an invalid sourceId"
  elif ($entry.classification | is_classification | not) then
    "\($label) contains unknown classification: \($entry.classification | raw_output)"
  else
    destinations_error($entry.supportedDestinations; "\($label) supportedDestinations") as $destination_error |
    if $destination_error != null then
      $destination_error
    elif (
      ($entry.command | type) != "string" or
      $entry.command == "" or
      ($entry.command | startswith("/")) or
      (("/" + ($entry.command | gsub("\\\\"; "/")) + "/") | contains("/../"))
    ) then
      "\($label) has an invalid command"
    elif (($entry | if has("stateInspection") then .stateInspection else "topology" end) as $state | $state != "topology" and $state != "adapter") then
      "\($label) has an invalid stateInspection"
    elif ($entry | has("matrixSource")) and (
      ($entry.matrixSource | type) != "string" or
      ($entry.matrixSource | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") | not)
    ) then
      "\($label) has an invalid matrixSource"
    elif ($entry.classification == "dual-plugin" or $entry.classification == "plugin-claude-only") then
      plugin_error($entry; $index)
    elif ($entry | has("plugin")) then
      "\($label) has plugin metadata for a non-plugin source"
    else
      null
    end
  end;

def validate_registry:
  if (type != "array" or length == 0) then
    "topology adapter registry must be a non-empty array"
  else
    duplicate_group([.[] | select(type == "object") | .sourceId]) as $duplicate |
    if $duplicate != null then
      "topology adapter registry contains duplicate sourceId: \($duplicate[0] | head_output)"
    else
      ([range(0; length) as $index | registry_entry_error($index) | select(. != null)] | first)
    end
  end;

.[0] |
(if $kind == "manifest" then validate_manifest else validate_registry end) |
select(. != null)
JQ

topology_validate_document() { # file kind
  local file="$1" kind="$2" parse_label validation
  case "$kind" in
    manifest) parse_label='skill topology manifest' ;;
    registry) parse_label='topology adapter registry' ;;
  esac

  if ! validation="$(jq -rs --arg kind "$kind" "$TOPOLOGY_SCHEMA_JQ" "$file" 2>&1)"; then
    topology_fail 2 "$parse_label is not valid JSON: $validation"
    return 2
  fi
  if [ -n "$validation" ]; then
    topology_fail 2 "$validation"
    return 2
  fi
}

topology_validate_manifest() { topology_validate_document "$1" manifest; }

topology_validate_registry() { topology_validate_document "$1" registry; }
