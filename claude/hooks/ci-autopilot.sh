#!/bin/bash
# PostToolUse (Bash): after an agent's successful `git push` of a branch with an open PR, start the CI
# autopilot (@MUSTER_DIR@/ci_watch.py) in the background. Never blocks or changes the push.
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
# Same parser as review-gate.sh (git_push_target.py): find the repo of a branch push in the command.
dir=$(python3 "$(dirname "$0")/git_push_target.py" "$cmd" "$cwd")
[ -n "$dir" ] || exit 0

# Only when the push really landed: HEAD equals its upstream.
head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || exit 0
up=$(git -C "$dir" rev-parse '@{u}' 2>/dev/null) || exit 0
[ "$head" = "$up" ] || exit 0

pr=$(cd "$dir" && ${MUSTER_GH:-gh} pr view --json number,headRepository,url -q '.number' 2>/dev/null) || exit 0
[ -n "$pr" ] || exit 0
repo=$(cd "$dir" && ${MUSTER_GH:-gh} repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || exit 0

mkdir -p "$HOME/.cache/muster/ci"
nohup python3 "@MUSTER_DIR@/ci_watch.py" --repo "$repo" --pr "$pr" --sha "$head" --pane "${HERDR_PANE_ID:-}" \
  >>"$HOME/.cache/muster/ci/autopilot.log" 2>&1 &
echo "{\"systemMessage\":\"CI autopilot is watching $repo#$pr\"}"
exit 0
