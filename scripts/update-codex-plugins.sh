#!/usr/bin/env bash
set -euo pipefail

# Refresh Codex plugin marketplace snapshots.
# Codex currently exposes marketplace refresh, not a per-installed-plugin update command.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

resolve_codex() {
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi

  if [ -x "${HOME}/.local/npm-global/bin/codex" ]; then
    printf '%s\n' "${HOME}/.local/npm-global/bin/codex"
    return 0
  fi

  return 1
}

section "Codex plugin marketplaces"

if ! CODEX_BIN="$(resolve_codex)"; then
  warn "codex not found"
  exit 1
fi

info "current: $("$CODEX_BIN" --version 2>/dev/null || echo unknown)"

if ! OUT="$("$CODEX_BIN" plugin marketplace upgrade --json 2>&1)"; then
  warn "codex plugin marketplace upgrade failed"
  printf '%s\n' "$OUT"
  exit 1
fi

if ! PARSED="$(CODEX_UPGRADE_JSON="$OUT" python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["CODEX_UPGRADE_JSON"])
selected = data.get("selectedMarketplaces") or []
upgraded = data.get("upgradedRoots") or []
errors = data.get("errors") or []

print("selected: " + (", ".join(selected) if selected else "none"))
print("upgraded roots: " + (", ".join(upgraded) if upgraded else "none"))

if errors:
    print("errors:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)
PY
)"; then
  warn "codex plugin marketplace upgrade reported errors"
  printf '%s\n' "$PARSED"
  exit 1
fi

printf '%s\n' "$PARSED"
section "Codex plugin marketplaces done"
