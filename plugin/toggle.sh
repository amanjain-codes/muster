#!/bin/zsh
# alt+d toggle: open dash as a right split beside the current pane; press again to close it and
# return focus to the pane you came from. Focus moves by direction, never by zoom: a zoom resizes the
# Claude pane twice and makes Claude Code redraw. Opening/closing the split itself resizes it once.
herdr="${HERDR_BIN_PATH:-herdr}"
cache="$HOME/.cache/muster"; mkdir -p "$cache"

# Ignore a second trigger within 1s (key repeat / double press).
stamp="$cache/toggle.stamp"
now=$(perl -MTime::HiRes=time -e 'printf "%.0f", time*1000'); last=$(cat "$stamp" 2>/dev/null || echo 0)
[ $((now - last)) -lt 700 ] && exit 0
echo "$now" > "$stamp"

# The dash pane is the one we opened (its id is remembered per tab: a brand-new pane has no "dash"
# label yet, so the label alone would miss it and open a second one), or any pane labelled dash.
read -r tab cur dash <<<"$("$herdr" pane list 2>/dev/null | /usr/bin/python3 -c '
import sys, json, os
panes = json.load(sys.stdin)["result"]["panes"]
cur = next((p for p in panes if p.get("focused")), None)
if not cur: sys.exit()
tab = cur["tab_id"]
try:
    mine = open(os.path.expanduser("~/.cache/muster/dash-pane-" + tab.replace(":", "_"))).read().strip()
except OSError:
    mine = ""
here = [p for p in panes if p["tab_id"] == tab]
dash = next((p["pane_id"] for p in here if p["pane_id"] == mine), None) \
    or next((p["pane_id"] for p in here if "dash" in (p.get("label"), p.get("terminal_title_stripped"))), "-")
print(tab, cur["pane_id"], dash)
')"
[ -z "$tab" ] && exit 0
back="$cache/dash-back-${tab//:/_}"
mine="$cache/dash-pane-${tab//:/_}"

if [ "$dash" = "-" ]; then
  print -r -- "$cur" > "$back"
  out=$("$herdr" plugin pane open --plugin muster --entrypoint dash --placement split --direction right --focus 2>/dev/null)
  id=$(print -r -- "$out" | /usr/bin/python3 -c 'import sys,re; m=re.search(r"\"pane_id\":\s*\"([^\"]+)\"", sys.stdin.read()); print(m.group(1) if m else "")')
  [ -n "$id" ] && print -r -- "$id" > "$mine" && "$herdr" plugin pane focus "$id" >/dev/null 2>&1
  exit 0
else
  # dash is open in this tab: close it and put focus back where you were (by direction, no zoom).
  prev=$(cat "$back" 2>/dev/null)
  if [ "$cur" = "$dash" ]; then
    for dir in left up right down; do
      "$herdr" pane focus --pane "$dash" --direction "$dir" >/dev/null 2>&1
      f=$("$herdr" pane list 2>/dev/null | /usr/bin/python3 -c 'import sys,json; print(next((p["pane_id"] for p in json.load(sys.stdin)["result"]["panes"] if p.get("focused")), ""))')
      [ -z "$prev" ] || [ "$f" = "$prev" ] && break
    done
  fi
  "$herdr" plugin pane close "$dash" >/dev/null 2>&1
  rm -f "$back" "$mine"
fi
