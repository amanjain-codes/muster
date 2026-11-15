#!/bin/zsh
# alt+h: swap the current Claude session for a fresh one that carries the context over.
#   1. /handoff <note>  (the agent writes a handoff note)
#   2. /clear           (new session in the same pane)
#   3. "Continue from the handoff note at <note>"
# Only when the agent is idle and its input box is empty. Runs in the background; macOS notifications report the outcome.
# MUSTER_HANDOFF_PANE overrides the target pane (for tests).
herdr="${HERDR_BIN_PATH:-herdr}"
note() { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1; echo "$1: $2"; }

pane="${MUSTER_HANDOFF_PANE:-}"
if [ -z "$pane" ]; then
  pane=$("$herdr" pane list 2>/dev/null | /usr/bin/python3 -c '
import sys, json
panes = json.load(sys.stdin)["result"]["panes"]
cur = next((p for p in panes if p.get("focused")), None)
if cur:
    if cur.get("agent") == "claude": print(cur["pane_id"])
    else: print(next((p["pane_id"] for p in panes if p["tab_id"] == cur["tab_id"] and p.get("agent") == "claude"), ""))
')
fi
[ -z "$pane" ] && { note "Handoff" "No Claude agent in this tab."; exit 0; }

agent_state=$("$herdr" pane list 2>/dev/null | /usr/bin/python3 -c "import sys,json; print(next((p.get('agent_status','') for p in json.load(sys.stdin)['result']['panes'] if p['pane_id']=='$pane'), ''))")
[ "$agent_state" = "working" ] && { note "Handoff" "Agent is working. Try again when it's idle."; exit 0; }
draft=$("$herdr" pane read "$pane" 2>/dev/null | /usr/bin/python3 -c 'import sys; l=[x.lstrip() for x in sys.stdin.read().splitlines() if x.lstrip().startswith("❯")]; print(l[-1][1:].strip() if l else "")')
[ -n "$draft" ] && { note "Handoff" "The input box has text. Send or clear it first."; exit 0; }

pinfo() {  # "<agent_status> <session id>" for the pane
  "$herdr" pane list 2>/dev/null | /usr/bin/python3 -c "import sys,json; p=next((p for p in json.load(sys.stdin)['result']['panes'] if p['pane_id']=='$pane'), {}); print(p.get('agent_status',''), (p.get('agent_session') or {}).get('value',''))"
}
nap() { perl -e 'select(undef,undef,undef,1)'; }

# Poll instead of `agent prompt --wait`: a fast reply can finish before herdr ever sees "working",
# and --wait then hangs. We wait for real outcomes: the note on disk, the session id changing.
run() {
  # (zsh: `path` and `status` are special variables, so neither is used as a name here)
  local nf="$HOME/.claude/handoffs/$(date +%Y-%m-%d-%H%M%S)-${pane//:/_}.md"
  mkdir -p "${nf:h}"
  local sid0=$(pinfo | cut -d' ' -f2)
  "$herdr" agent prompt "$pane" "/handoff $nf" >/dev/null 2>&1
  local i=0
  while [ $i -lt 600 ]; do  # up to 10 min to write the note, then for the agent to go idle
    [ -s "$nf" ] && [ "$(pinfo | cut -d' ' -f1)" != "working" ] && break
    nap; i=$((i + 1))
  done
  if [ ! -s "$nf" ]; then note "Handoff failed" "No note was written; the session was left as it was."; return; fi
  nap; nap
  "$herdr" agent prompt "$pane" "/clear" >/dev/null 2>&1
  i=0
  while [ $i -lt 30 ]; do  # /clear starts a new session id
    [ "$(pinfo | cut -d' ' -f2)" != "$sid0" ] && break
    nap; i=$((i + 1))
  done
  nap
  "$herdr" agent prompt "$pane" "Continue from the handoff note at $nf: read it first, then pick up at its Next step. Ask me before anything risky." >/dev/null 2>&1
  note "Fresh session" "Context carried over: ${nf:t}"
}
if [ -n "$MUSTER_HANDOFF_FG" ]; then run; else (run &) >/dev/null 2>&1; fi
