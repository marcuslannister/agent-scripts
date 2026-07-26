#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
for required_tool in bash git jq python3 rg; do
  executable="$(command -v "$required_tool")"
  ln -s "$executable" "$TMP_ROOT/bin/$required_tool"
done

while IFS= read -r executable; do
  name="${executable##*/}"
  [ "$name" = node ] && continue
  [ -e "$TMP_ROOT/bin/$name" ] || ln -s "$executable" "$TMP_ROOT/bin/$name"
done < <(
  for path_root in ${PATH//:/ }; do
    [ -d "$path_root" ] || continue
    find "$path_root" -maxdepth 1 -type f -perm -111 -print 2>/dev/null
  done
)

if PATH="$TMP_ROOT/bin" command -v node >/dev/null 2>&1; then
  echo "FAIL: node remained available in no-node regression" >&2
  exit 1
fi

PATH="$TMP_ROOT/bin" "$REPO_ROOT/agent-tooling/update-skill-topology.sh" --help >/dev/null

for test_file in \
  topology-cutover-policy-test.sh \
  update-codex-root-hygiene-test.sh \
  update-copy-distributed-topology-test.sh \
  update-npx-distributed-topology-test.sh \
  update-plugin-distributed-topology-test.sh \
  update-skill-topology-acquire-test.sh \
  sync-skill-surfaces-test.sh \
  matrix-driven-topology-test.sh
do
  PATH="$TMP_ROOT/bin" bash "$REPO_ROOT/tests/$test_file" >/dev/null
done

echo "topology no-Node tests passed"
