#!/bin/bash
# Tests for plugin/ci_watch.py with a fake gh, in dry-run mode (prints actions instead of prompting/notifying).
set -u
D=$(cd "$(dirname "$0")" && pwd); W="$D/../plugin/ci_watch.py"
export MUSTER_GH="$D/fakegh" MUSTER_CI_DRY=1 MUSTER_CI_POLL=1 MUSTER_CI_STUCK=2
STATE=~/.cache/muster/ci/acme_svc-412.json
fail=0; expect() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (want '$3', got '$2')"; fail=1; fi; }
st() { python3 -c "import json;print(json.load(open('$STATE'))['state'])"; }
clean() { rm -f ~/.cache/muster/ci/acme_svc-412.* "$D"/n?; }

clean; FAKE_SCENARIO=green FAKE_STATE="$D/n1" python3 "$W" --repo acme/svc --pr 412 --pane w0:p0 >/dev/null
expect "green: notifies ready to merge" "$(st)" "green"
clean; for i in 1 2; do FAKE_SCENARIO=red FAKE_STATE="$D/n2" python3 "$W" --repo acme/svc --pr 412 --pane w0:p0 >/dev/null; done
expect "red: hands back to the agent (2 rounds)" "$(st)" "fixing"
FAKE_SCENARIO=red FAKE_STATE="$D/n2" python3 "$W" --repo acme/svc --pr 412 --pane w0:p0 >/dev/null
expect "red x3: needs you" "$(st)" "needs you"
clean; FAKE_SCENARIO=stuck FAKE_STATE="$D/n3" python3 "$W" --repo acme/svc --pr 412 --pane w0:p0 >/dev/null
expect "only pending checks: stuck" "$(st)" "stuck"
clean
exit $fail
