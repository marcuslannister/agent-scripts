#!/usr/bin/env bash
set -euo pipefail

for required_tool in bash git python3 bun node npm ruby; do
  if command -v "$required_tool" >/dev/null 2>&1; then
    continue
  fi

  printf 'error: required tool not found: %s\n' "$required_tool" >&2
  case "$required_tool" in
    python3) echo "Install Python 3, then install PyYAML: python3 -m pip install pyyaml" >&2 ;;
    bun) echo "Install Bun: https://bun.sh/docs/installation" >&2 ;;
    node|npm) echo "Install Node.js with npm: https://nodejs.org/" >&2 ;;
    ruby) echo "Install Ruby to run the maintainer policy check." >&2 ;;
    *) echo "Install $required_tool and retry." >&2 ;;
  esac
  exit 1
done

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "error: required Python package not found: PyYAML" >&2
  echo "Install it: python3 -m pip install pyyaml" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIDEO_DIR="$REPO_ROOT/skills/video-transcript-downloader"

if [ ! -d "$REPO_ROOT/node_modules" ]; then
  echo "error: browser helper dependencies not installed." >&2
  echo "Install them: bun install --frozen-lockfile" >&2
  exit 1
fi

if [ ! -d "$VIDEO_DIR/node_modules" ]; then
  echo "error: video downloader dependencies not installed." >&2
  echo "Install them: npm ci --prefix skills/video-transcript-downloader" >&2
  exit 1
fi

section() {
  printf '\n==> %s\n' "$1"
}

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-scripts-verify.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$REPO_ROOT"

section "Bash syntax"
while IFS= read -r -d '' candidate; do
  first_line=
  IFS= read -r first_line < "$candidate" || true
  case "$candidate:$first_line" in
    *.sh:*|*:'#!'*bash*) bash -n "$candidate" ;;
  esac
done < <(git ls-files -co --exclude-standard -z)

section "Skill front matter"
scripts/validate-skills

section "Updater and copy regressions"
for test_file in tests/*-test.sh; do
  bash "$test_file"
done

section "Maintainer policy"
scripts/test-maintainer-orchestrator-policy

section "Browser helper"
bun test scripts/browser-tools-profile.test.ts
bun build scripts/browser-tools.ts --compile --target bun --outfile "$BUILD_DIR/browser-tools"
"$BUILD_DIR/browser-tools" --help >/dev/null

section "Video downloader"
(
  cd "$VIDEO_DIR"
  node -e "import('youtube-transcript-plus').then(m => { if (typeof m.YoutubeTranscript?.fetchTranscript !== 'function') process.exit(1); })"
  ./scripts/vtd.js transcript --help >/dev/null
)

printf '\nVerification passed.\n'
