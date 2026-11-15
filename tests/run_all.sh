#!/bin/bash
# Run every test. Tests only touch scratch folders under tests/ and ~/.cache; nothing calls GitHub, Slack or Claude.
cd "$(dirname "$0")" || exit 1
status=0
for t in test_verify_gate.sh test_review_gate.sh test_ci_watch.sh test_ci_autopilot_hook.sh test_notes.sh test_fetch_slack.sh test_dash_ui.sh; do
  echo "== $t"; bash "$t" || status=1
done
echo; [ $status -eq 0 ] && echo "all tests passed" || echo "some tests failed"
exit $status
