#!/usr/bin/env bash
# Patch the installed nowledge-mem plugins of Codex and Pi so each injects one
# short search note instead of the Context Bundle. Codex adds nothing on each
# prompt. Neither plugin has a switch for this. A plugin update replaces the
# files, so update-plugins.sh runs this after the refresh. Same note as the
# Claude patch (claude-code-settings hooks/nowledge-lean.sh).
# NMEM_FULL_CONTEXT=1 restores the plugin's own output without unpatching.
# shortcut: string match on upstream code; if upstream changes an anchor, that
# file is skipped and the script exits 1, so update-plugins.sh warns. Then update the anchor.
set -euo pipefail

python3 - "${CODEX_HOME:-$HOME/.codex}" "$HOME/.pi/agent/npm/node_modules/nowledge-mem-pi" <<'PY'
import glob, json, os, shutil, sys

codex_home, pi_root = sys.argv[1:3]
NOTE = ("[Nowledge Mem] Memory is available. For prior decisions, history, or "
        "continuation work, search first: nmem --json m search \"query\" -n 5, or "
        "nmem --json t search \"query\" --limit 5. If retrieval fails, say so. "
        "Save durable decisions with nmem m add \"content\" -t \"Title\" -i 0.8.")
MARKER = "local patch: nowledge-lean"
failed = False


def patch(path, edits):
    global failed
    with open(path, encoding="utf-8", newline="") as f:
        src = f.read()
    if MARKER in src:
        return
    for old, new in edits:
        if src.count(old) != 1:
            print(f"nowledge-lean: anchor not found in {path}; patch skipped", file=sys.stderr)
            failed = True
            return
        src = src.replace(old, new)
    tmp = path + ".lean-tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(src)
    shutil.copymode(path, tmp)
    os.replace(tmp, path)


# Codex: SessionStart gets the note, UserPromptSubmit gets nothing. A thread
# resume (resume_context) still goes through.
old = ('    if event_name == "UserPromptSubmit":\n'
       '        guidance = PROMPT_ROUTING_GUIDANCE\n'
       '    elif event_name == "SubagentStart":')
new = ("    # " + MARKER + "\n"
       '    if os.environ.get("NMEM_FULL_CONTEXT") != "1" and event_name in {"SessionStart", "UserPromptSubmit"}:\n'
       '        lean = ([' + json.dumps(NOTE) + '] if event_name == "SessionStart" else []) + ([resume_context] if resume_context else [])\n'
       '        if lean:\n'
       '            _write_hook_response(event_name, "\\n\\n".join(lean))\n'
       '        return 0\n') + old
for path in glob.glob(f"{codex_home}/plugins/cache/nowledge-community/nowledge-mem/*/hooks/nmem-context.py"):
    patch(path, [(old, new)])

# Pi: the extension appends the bundle to the system prompt on every agent
# start. Swap it for the note, and skip the nmem reads that fill the bundle.
path = f"{pi_root}/extensions/nowledge-mem.ts"
if os.path.isfile(path):
    refresh = "async function refreshStartupContext(ctx: ExtensionContext): Promise<void> {\n"
    append = "async function appendMemoryContext(systemPrompt: string, ctx: ExtensionContext): Promise<string> {\n"
    patch(path, [
        (refresh, refresh + "\t// " + MARKER + "\n\tif (process.env.NMEM_FULL_CONTEXT !== \"1\") return;\n"),
        (append, append + "\tif (process.env.NMEM_FULL_CONTEXT !== \"1\") return systemPrompt + \"\\n\\n\" + " + json.dumps(NOTE) + ";\n"),
    ])

sys.exit(1 if failed else 0)
PY
