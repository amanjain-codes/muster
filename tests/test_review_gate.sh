#!/bin/bash
# Tests for claude/hooks/review-gate.sh against a scratch repo with a local bare remote. No network, no Claude.
# Run from a file: if these strings were typed into Claude Code, the live hook would see them.
set -u
D=$(cd "$(dirname "$0")" && pwd); H="$D/../claude/hooks/review-gate.sh"; S="$D/rg"
rm -rf "$S"; mkdir -p "$S" && cd "$S" && git init -q --bare remote.git && git clone -q remote.git work 2>/dev/null
cd work && echo hello > a.txt && git add a.txt && git commit -qm "add a"
fail=0
t() {  # t <command> <cwd> <expected allow|deny>
  r=$(jq -n --arg c "$1" --arg d "$2" '{cwd:$d, tool_input:{command:$c}}' | "$H")
  got=allow; [ -n "$r" ] && got=$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$r")
  if [ "$got" = "$3" ]; then echo "  ok   $3  ${1:0:50}"; else echo "  FAIL ${1:0:50} (want $3, got $got)"; fail=1; fi
}
[ -x "$H" ] || { echo "  FAIL hook not found at $H"; exit 1; }
t "git status"                                    "$S/work" allow
t "git push origin main"                          "$S/work" deny
t "cd $S && cd work && git push origin HEAD:main" /tmp      deny
t "git -C work push"                              "$S"      deny
t "git push origin --delete old"                  "$S/work" allow
t "git push --tags"                               "$S/work" allow
t "echo 'run git push later'"                     "$S/work" allow
t "git commit -m x && git push"                   "$S/work" deny
t "git push"                                      /tmp      allow   # not a git repo
t "/usr/bin/git push origin main"                 "$S/work" deny    # path-qualified git
t "git -c core.x=1 push"                          "$S/work" deny    # git global options
t "env FOO=1 git push"                            "$S/work" deny    # env wrapper
t "sh -c 'git push origin main'"                  "$S/work" deny    # shell -c
t "git push origin main --tags"                   "$S/work" deny    # tags plus a branch is still a push
t "git push origin :old"                          "$S/work" allow   # delete-only refspec
t "git push origin :"                             "$S/work" deny    # bare : pushes matching branches
gd=$(git rev-parse --absolute-git-dir); mkdir -p "$gd/claude-reviewed"; touch "$gd/claude-reviewed/$(git rev-parse HEAD)"
t "git push origin main"                          "$S/work" allow   # reviewed
git commit -q --allow-empty -m next
t "git push origin main"                          "$S/work" deny    # a new commit needs a new review
rm -rf "$S"
exit $fail
