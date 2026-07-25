find_claude_mem_bun() {
  local candidate found
  for candidate in \
    "$home"/scoop/apps/bun/*/bun.exe \
    "$home/scoop/apps/bun/current/bun.exe" \
    "$home/scoop/shims/bun" \
    "$home/scoop/shims/bun.exe" \
    "$home/.bun/bin/bun" \
    "$home/.bun/bin/bun.exe" \
    /usr/local/bin/bun \
    /opt/homebrew/bin/bun \
    /home/linuxbrew/.linuxbrew/bin/bun
  do
    [ -e "$candidate" ] || continue
    "$candidate" --version >/dev/null 2>&1 && return 0
  done
  found="$(command -v bun 2>/dev/null || true)"
  [ -n "$found" ] && "$found" --version >/dev/null 2>&1
}

find_claude_mem_uv_command() {
  local command_name="$1"
  local candidate found
  for candidate in \
    "$home"/scoop/apps/uv/*/"${command_name}.exe" \
    "$home/scoop/apps/uv/current/${command_name}.exe" \
    "$home/scoop/shims/${command_name}" \
    "$home/scoop/shims/${command_name}.exe" \
    "$home/.local/bin/${command_name}" \
    /usr/local/bin/"$command_name" \
    /opt/homebrew/bin/"$command_name" \
    /home/linuxbrew/.linuxbrew/bin/"$command_name"
  do
    [ -e "$candidate" ] || continue
    "$candidate" --version >/dev/null 2>&1 && return 0
  done
  found="$(command -v "$command_name" 2>/dev/null || true)"
  [ -n "$found" ] && "$found" --version >/dev/null 2>&1
}

require_claude_mem_dependencies() {
  local failed=0
  if ! find_claude_mem_bun; then
    printf 'claude-mem requires runnable Bun for its shared hooks; install or repair Bun: https://bun.sh/docs/installation\n' >&2
    failed=1
  fi
  if ! find_claude_mem_uv_command uv || ! find_claude_mem_uv_command uvx; then
    printf 'claude-mem requires runnable uv and uvx for shared vector search; install or repair Astral uv\n' >&2
    failed=1
  fi
  return "$failed"
}
