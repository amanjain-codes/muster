#!/bin/zsh
# alt+e toggle: the editor (fresh) full screen in its own "ide" tab; press again to return
# to the exact tab you came from. fresh keeps running in its tab, so unsaved edits survive.
#
# One ide tab per workspace, remembered in ~/.cache/muster/ide-<workspace>:  "<tab_id> <pane_id>".
# The tab is created with its cwd in this plugin folder so the autoclaude plugin (which starts
# Claude in new tabs) skips it; fresh then opens in your project folder.
herdr="${HERDR_BIN_PATH:-herdr}"
cache="$HOME/.cache/muster"; mkdir -p "$cache"
here="${0:A:h}"

read -r ws tab cwd <<<"$("$herdr" pane list 2>/dev/null | /usr/bin/python3 -c '
import sys, json
panes = json.load(sys.stdin)["result"]["panes"]
cur = next((p for p in panes if p.get("focused")), None)
if cur: print(cur["workspace_id"], cur["tab_id"], cur.get("foreground_cwd") or cur.get("cwd") or "~")
')"
[ -z "$ws" ] && exit 0

memo="$cache/ide-${ws//:/_}"
back="$memo.back"
ide_tab=""; ide_pane=""
[ -f "$memo" ] && read -r ide_tab ide_pane < "$memo"
if [ -n "$ide_tab" ] && ! "$herdr" tab list 2>/dev/null | grep -q "\"tab_id\":\"$ide_tab\""; then
  ide_tab=""; ide_pane=""  # the ide tab was closed by hand
fi

if [ -n "$ide_tab" ] && [ "$tab" = "$ide_tab" ]; then
  # In the ide tab: go back where we came from.
  prev=$(cat "$back" 2>/dev/null)
  [ -n "$prev" ] && exec "$herdr" tab focus "$prev" >/dev/null
  exit 0
fi

print -r -- "$tab" > "$back"
if [ -n "$ide_tab" ]; then
  exec "$herdr" tab focus "$ide_tab" >/dev/null
fi

out=$("$herdr" tab create --workspace "$ws" --cwd "$here" --label "ide" --focus 2>/dev/null)
ide_tab=$(print -r -- "$out" | /usr/bin/python3 -c 'import sys,re; m=re.search(r"\"tab_id\":\s*\"([^\"]+)\"", sys.stdin.read()); print(m.group(1) if m else "")')
[ -z "$ide_tab" ] && exit 1
ide_pane=$("$herdr" pane list 2>/dev/null | /usr/bin/python3 -c '
import sys, json
t = sys.argv[1]
print(next((p["pane_id"] for p in json.load(sys.stdin)["result"]["panes"] if p["tab_id"] == t), ""))' "$ide_tab")
[ -z "$ide_pane" ] && exit 1
print -r -- "$ide_tab $ide_pane" > "$memo"
"$herdr" pane run "$ide_pane" "cd ${(q)cwd} && clear && fresh ." >/dev/null
