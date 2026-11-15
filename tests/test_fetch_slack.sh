#!/bin/bash
# Tests for the Slack mention clean-up in plugin/fetch.py: untrusted connector output must not reach dash unfiltered.
set -u
D=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
HOME="$T" python3 - "$D/../plugin" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
from fetch import sanitize_slack, READ_TOOLS

fail = 0
def expect(name, got, want):
    global fail
    print(f"  {'ok  ' if got == want else 'FAIL'} {name}" + ("" if got == want else f" (want {want!r}, got {got!r})"))
    fail |= got != want

good = "https://acme.slack.com/archives/C0123ABC/p1731650000123456?thread_ts=1731650000.123456&cid=C0123ABC"
out = sanitize_slack([
    {"who": "Sam", "where": "#eng", "text": "can you look at the deploy?", "url": good, "ts": 1731650000},
    {"who": "Eve\x1b[31m", "where": "DM", "text": "x" * 200, "url": "javascript:alert(1)", "ts": "soon"},
    {"who": "Mal", "where": "DM", "text": "hi", "url": "https://evil.example/archives/C1/p1"},
    "not a dict", None,
] + [{"who": str(i), "url": good} for i in range(10)])
expect("permalink kept", out[0]["url"], good)
expect("control characters stripped", out[1]["who"], "Eve [31m")
expect("text capped at 60", len(out[1]["text"]), 60)
expect("non-Slack link dropped", out[1]["url"], None)
expect("look-alike host dropped", out[2]["url"], None)
expect("bad timestamp becomes 0", out[1]["ts"], 0.0)
expect("at most 5 kept", len(out), 5)
expect("garbage input gives []", sanitize_slack({"oops": 1}), [])
expect("only the Slack search tool, no send", [t for t in READ_TOOLS if "Slack" in t], ["mcp__claude_ai_Slack__slack_search_public_and_private"])
from fetch import prompt
expect("prompt without Slack has no Slack part", ("slack_search" in prompt(False), '3. "errors"' in prompt(False)), (False, True))
expect("prompt with Slack uses a 24h unix cutoff", ('after="' in prompt(True), '4. "errors"' in prompt(True)), (True, True))
sys.exit(fail)
EOF
