#!/usr/bin/env zsh
set -uo pipefail

# Repo status sweep: reports uncommitted + unpushed changes across repos.
# Unlike `git status` on one branch, this surfaces commits on ANY local
# branch that aren't on a remote (catches orphan/feature branches too).
#
# Usage:
#   repo-check.zsh                 # check default repo list
#   repo-check.zsh ~/foo ~/bar     # check given repos instead

DEFAULT_REPOS=(
  ~/.claude
  ~/.codex
  ~/dotfiles
  ~/Projects/agent-scripts
  ~/Projects/nix-config
  ~/.emacs.d
)

repos=( "${@:-${DEFAULT_REPOS[@]}}" )
(( $# )) && repos=( "$@" )

bold()  { printf '\n\033[1;33m===== %s =====\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }

dirty_total=0
unpushed_total=0

for d in "${repos[@]}"; do
  bold "$d"

  if ! git -C "$d" rev-parse --is-inside-work-tree &>/dev/null; then
    red "(not a git repo)"
    continue
  fi

  # Working tree: modified / staged / untracked
  porcelain=$(git -C "$d" status -sb 2>&1)
  changes=$(printf '%s\n' "$porcelain" | tail -n +2)
  if [ -n "$changes" ]; then
    (( dirty_total++ ))
    printf '%s\n' "$porcelain"
  else
    green "✓ working tree clean ($(printf '%s' "$porcelain" | head -1))"
  fi

  # Unpushed: commits on any local branch not on any remote-tracking ref
  unpushed=$(git -C "$d" log --branches --not --remotes \
              --pretty='  %C(auto)%h%Creset %s %C(dim)(%S)%Creset' 2>/dev/null)
  if [ -n "$unpushed" ]; then
    (( unpushed_total++ ))
    red "--- unpushed commits (not on any remote) ---"
    printf '%s\n' "$unpushed"
  fi
done

bold "Summary"
if (( dirty_total == 0 && unpushed_total == 0 )); then
  green "✓ all clean — nothing uncommitted or unpushed"
  exit 0
fi
printf 'repos with uncommitted changes: %d\n' "$dirty_total"
printf 'repos with unpushed commits:    %d\n' "$unpushed_total"
exit 1
