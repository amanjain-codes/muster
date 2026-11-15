#!/bin/bash
# Tests for claude/hooks/verify-gate.sh on a scratch Go repo (needs go and python3).
set -u
D=$(cd "$(dirname "$0")" && pwd); H="$D/../claude/hooks/verify-gate.sh"; R="$D/vg/repo"; sid="test-$$"
rm -rf "$D/vg" && mkdir -p "$R/pkg" && cd "$R" && git init -q && go mod init example.com/t >/dev/null 2>&1
printf 'package pkg\n\nfunc Add(a, b int) int { return a + b }\n' > pkg/add.go
printf 'package pkg\n\nimport "testing"\n\nfunc TestAdd(t *testing.T) { if Add(1, 2) != 3 { t.Fatal("bad") } }\n' > pkg/add_test.go
git add -A && git commit -qm init
export MUSTER_TRUSTED_ROOTS_FILE="$D/vg/trusted"; echo "$R" > "$MUSTER_TRUSTED_ROOTS_FILE"
rec()  { jq -n --arg s "$sid" --arg f "$1" '{session_id:$s, tool_input:{file_path:$f}}' | "$H" record; }
stop() { jq -n --arg s "$sid" --arg c "$PWD" '{session_id:$s, cwd:$c}' | "$H" stop; }
fail=0; expect() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (want '$3', got '$2')"; fail=1; fi; }

expect "no edits: passes silently" "$(stop)" ""
printf 'package pkg\n\nfunc Add(a, b int) int { return a + c }\n' > pkg/add.go; rec "$PWD/pkg/add.go"
expect "compile error: blocks" "$(stop | jq -r .decision)" "block"
printf 'package pkg\n\nfunc Add(a, b int) int { return a - b }\n' > pkg/add.go; rec "$PWD/pkg/add.go"
expect "failing test: blocks with FAIL" "$(stop | jq -r '.reason | test("FAIL")')" "true"
printf 'package pkg\n\nfunc Add(a, b int) int { return a + b }\n' > pkg/add.go; rec "$PWD/pkg/add.go"
expect "fixed: passes and clears state" "$(stop)$(ls ~/.cache/claude-verify/$sid.* 2>/dev/null)" ""
printf 'package pkg\n\nfunc Add(a, b int) int { return x }\n' > pkg/add.go
for i in 1 2 3; do rec "$PWD/pkg/add.go"; stop >/dev/null; done; rec "$PWD/pkg/add.go"
expect "cap: 4th attempt lets it stop" "$(stop | jq -r 'has("systemMessage")')" "true"
git checkout -q -- .; printf 'def f(:\n  pass\n' > bad.py; rec "$PWD/bad.py"
expect "python syntax error: blocks" "$(stop | jq -r .decision)" "block"
rm bad.py; mkdir -p .claude; printf '#!/bin/sh\necho "custom check: $*"; exit 1\n' > .claude/verify.sh; chmod +x .claude/verify.sh; rec "$PWD/pkg/add.go"
expect "repo .claude/verify.sh is used" "$(stop | jq -r '.reason | test("custom check")')" "true"
echo "/nowhere" > "$MUSTER_TRUSTED_ROOTS_FILE"; printf 'package pkg\n\nfunc Add(a, b int) int { return x }\n' > pkg/add.go; rec "$PWD/pkg/add.go"
out=$(stop)
expect "untrusted repo: its code is not run" "$(jq -r '.decision // "none"' <<<"$out")" "none"
expect "  ...and says how to trust it" "$(jq -r '.systemMessage | test("muster trust")' <<<"$out")" "true"
rec "$PWD/pkg/add.go"
expect "  ...only once per session" "$(stop)" ""
# A parent folder is not a trusted repo: a clone or fork checkout dropped next to your repos must not run.
echo "$D/vg" > "$MUSTER_TRUSTED_ROOTS_FILE"; rec "$PWD/pkg/add.go"
expect "trusted parent folder: repos inside are not run" "$(stop | grep -c '"block"')" "0"
rm -f .claude/verify.sh; git checkout -q -- .
echo "$R" > "$MUSTER_TRUSTED_ROOTS_FILE"; git worktree add -q "$D/vg/repo-wt" -b wt >/dev/null 2>&1
printf 'package pkg\n\nfunc Add(a, b int) int { return x }\n' > "$D/vg/repo-wt/pkg/add.go"; rec "$D/vg/repo-wt/pkg/add.go"
expect "worktree of a trusted repo is checked" "$(stop | jq -r .decision)" "block"
# A folder whose hand-made .git file points at the trusted repo's .git is not one of its worktrees.
rm -f ~/.cache/claude-verify/$sid.*
E="$D/vg/evil"; mkdir -p "$E/.claude" && echo "gitdir: $R/.git" > "$E/.git"
printf '#!/bin/sh\necho "evil ran"; exit 1\n' > "$E/.claude/verify.sh"; chmod +x "$E/.claude/verify.sh"; echo x > "$E/f.txt"; rec "$E/f.txt"
expect "fake worktree (.git file into a trusted repo) is not run" "$(stop | grep -c 'evil ran')" "0"
rm -rf "$D/vg" ~/.cache/claude-verify/test-*
exit $fail
