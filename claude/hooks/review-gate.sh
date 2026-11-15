#!/bin/bash
# PreToolUse (Bash) review gate: an agent can't `git push` a commit until that exact commit has had a
# review pass. The marker is per commit and per worktree: <git-dir>/claude-reviewed/<HEAD sha>.
# A new commit after review needs a new review. Pushes you run yourself in a shell are never affected.
# A guardrail so review isn't forgotten, not a sandbox: an agent set on bypassing it could write the marker.
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")

deny() { jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'; exit 0; }

# Parse the command like a shell would (chains, cd, git options, wrappers, sh -c, eval); see git_push_target.py.
parser="$(dirname "$0")/git_push_target.py"
if [ ! -f "$parser" ]; then  # fail closed: a broken gate must not silently allow pushes
  grep -q 'push' <<<"$cmd" && grep -q 'git' <<<"$cmd" && deny "review-gate is broken (git_push_target.py missing next to it). Tell the user to run: muster update"
  exit 0
fi
dir=$(python3 "$parser" "$cmd" "$cwd")
[ -n "$dir" ] || exit 0  # no push that needs review

gd=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || exit 0
[ -f "$gd/claude-reviewed/$sha" ] && exit 0

reason="review-gate: commit ${sha:0:8} hasn't been reviewed. Before pushing: run the code-review skill on this branch's changes (git diff \$(git merge-base origin/HEAD HEAD)...HEAD), fix the real findings and commit, then mark the final commit reviewed with: mkdir -p \"$gd/claude-reviewed\" && touch \"$gd/claude-reviewed/\$(git rev-parse HEAD)\" and push again. If the user explicitly asked to push without review, mark it and say so in your reply."
deny "$reason"
