#!/bin/bash
# Tests for claude/hooks/ci-autopilot.sh with a fake gh, in dry-run mode. No network, no Claude.
set -u
D=$(cd "$(dirname "$0")" && pwd); R="$D/repo"
# The repo copy has an @MUSTER_DIR@ placeholder (install.sh fills it in): point it at this repo's plugin/.
HD="$D/hooktmp"; mkdir -p "$HD"; cp "$D/../claude/hooks/git_push_target.py" "$HD/"
H="$HD/ci-autopilot.sh"; sed "s#@MUSTER_DIR@#$D/../plugin#g" "$D/../claude/hooks/ci-autopilot.sh" > "$H"; chmod +x "$H"
rm -rf "$R" && mkdir -p "$R" && cd "$R" && git init -q --bare remote.git && git clone -q remote.git work 2>/dev/null
cd work && git commit -q --allow-empty -m one && git push -q -u origin HEAD:main 2>/dev/null
export MUSTER_GH="$D/fakegh" MUSTER_CI_DRY=1 MUSTER_CI_POLL=1 FAKE_SCENARIO=green FAKE_STATE="$D/nh" HERDR_PANE_ID=w9:p9
fail=0; expect() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (want '$3', got '$2')"; fail=1; fi; }
hook() { jq -n --arg c "$1" --arg d "$R/work" '{cwd:$d, tool_input:{command:$c}, tool_response:{}}' | "$H"; }
STATE=~/.cache/muster/ci/acme_svc-412.json
rm -f ~/.cache/muster/ci/acme_svc-412.* "$D/nh"

expect "landed push starts the watcher" "$(hook "git push" | jq -r '.systemMessage')" "CI autopilot is watching acme/svc#412"
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q '"green"' "$STATE" 2>/dev/null && break; sleep 1; done
expect "watcher reaches green" "$(python3 -c "import json;print(json.load(open('$STATE'))['state'])" 2>/dev/null)" "green"
expect "not a push: nothing" "$(hook "git status")" ""
git commit -q --allow-empty -m two
expect "push that didn't land (HEAD ahead): nothing" "$(hook "git push")" ""
expect "push --delete: nothing" "$(hook "git push origin --delete x")" ""
rm -rf "$R" "$HD" ~/.cache/muster/ci/acme_svc-412.* "$D/nh"
exit $fail
