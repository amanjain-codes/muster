#!/bin/bash
# Verification gate for Claude Code.
#   verify-gate.sh record  (PostToolUse on Edit|Write|MultiEdit): remember which files this session changed.
#   verify-gate.sh stop    (Stop): before the agent finishes, run fast checks on those files only.
#                          Failing checks block the stop and hand the errors back, so the agent fixes them first.
# Checks: a repo's own .claude/verify.sh if present (gets the changed files as args); otherwise
# Go build + tests for touched packages, Python compile, TypeScript tsc --noEmit when the repo has tsc.
# At most 3 blocks per session, so a check the agent can't fix never traps it in a loop.
mode="${1:-stop}"
input=$(cat)
state="$HOME/.cache/claude-verify"; mkdir -p "$state"
sid=$(jq -r '.session_id // "unknown"' <<<"$input")
files="$state/$sid.files"; blocks="$state/$sid.blocks"

if [ "$mode" = "record" ]; then
  f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
  [ -n "$f" ] && echo "$f" >> "$files"
  exit 0
fi

[ -s "$files" ] || exit 0
n=$(cat "$blocks" 2>/dev/null || echo 0)
if [ "$n" -ge 3 ]; then
  rm -f "$files" "$blocks"
  printf '{"systemMessage":"verify-gate: checks still failing after 3 attempts; letting the agent stop. Check the errors yourself."}\n'
  exit 0
fi

limit() { perl -e 'alarm shift; exec @ARGV' "$@"; }  # macOS has no `timeout`
out=""; fail=0
run() {  # run a check in a directory; collect output on failure
  local dir="$1"; shift
  local res; res=$(cd "$dir" && limit 150 "$@" 2>&1); local rc=$?
  if [ $rc -ne 0 ]; then fail=1; out+=$'\n'"\$ (in ${dir/#$HOME/~}) $*"$'\n'"$(printf '%s' "$res" | tail -40)"$'\n'; fi
}

# Only files that still exist; group by git repo. (macOS bash 3.2: no mapfile.)
changed=()
while IFS= read -r f; do [ -f "$f" ] && changed+=("$f"); done < <(sort -u "$files")
[ ${#changed[@]} -gt 0 ] || { rm -f "$files"; exit 0; }
roots=$(for f in "${changed[@]}"; do git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null; done | sort -u)

# Checks run repo code (go test, a repo's .claude/verify.sh), so only in repos you trust:
# one repo path per line in ~/.config/muster/trusted-roots (`muster trust` inside a repo adds it).
# Exact repos, not parent folders: a clone or fork checkout dropped into your code folder must not run unasked.
# A worktree counts as its main repo.
TRUST="${MUSTER_TRUSTED_ROOTS_FILE:-$HOME/.config/muster/trusted-roots}"
trusted() {
  [ -f "$TRUST" ] || return 1
  local here main line
  here=$(cd "$1" && pwd -P)
  main=$(cd "$1" && cd "$(git rev-parse --git-common-dir)/.." 2>/dev/null && pwd -P)
  while IFS= read -r line; do
    line="${line/#\~/$HOME}"; line="${line%/}"
    { [ -n "$line" ] && [ "${line:0:1}" != "#" ]; } || continue
    line=$(cd "$line" 2>/dev/null && pwd -P) || continue
    { [ "$here" = "$line" ] || [ "$main" = "$line" ]; } && return 0
  done < "$TRUST"
  return 1
}
hinted="$state/$sid.hinted"; skipped=""

for root in $roots; do
  if ! trusted "$root"; then  # not a trusted repo: don't run its code; say so once per session
    grep -qxF "$root" "$hinted" 2>/dev/null || { echo "$root" >> "$hinted"; skipped+="${skipped:+, }${root/#$HOME/~}"; }
    continue
  fi
  mine=(); for f in "${changed[@]}"; do [[ "$f" == "$root"/* ]] && mine+=("$f"); done
  if [ -x "$root/.claude/verify.sh" ]; then run "$root" "$root/.claude/verify.sh" "${mine[@]}"; continue; fi

  # Go: build and test each touched package, from its module root.
  for mod in $(for f in "${mine[@]}"; do [[ "$f" == *.go ]] || continue; d=$(dirname "$f")
                 while [ "$d" != "/" ] && [ ! -f "$d/go.mod" ]; do d=$(dirname "$d"); done; [ -f "$d/go.mod" ] && echo "$d"; done | sort -u); do
    pkgs=$(for f in "${mine[@]}"; do [[ "$f" == "$mod"/*.go ]] && echo "./$(dirname "${f#$mod/}")"; done | sed 's#^\./\.$#.#' | sort -u)
    run "$mod" go build $pkgs
    [ $fail -eq 0 ] && run "$mod" go test -count=1 -timeout 120s $pkgs
  done

  # Python: syntax check the touched files.
  py=(); for f in "${mine[@]}"; do [[ "$f" == *.py ]] && py+=("$f"); done
  [ ${#py[@]} -gt 0 ] && run "$root" python3 -m py_compile "${py[@]}"

  # TypeScript: type check when the repo has its own tsc.
  ts=0; for f in "${mine[@]}"; do [[ "$f" == *.ts || "$f" == *.tsx ]] && ts=1; done
  [ $ts -eq 1 ] && [ -f "$root/tsconfig.json" ] && [ -x "$root/node_modules/.bin/tsc" ] && run "$root" "$root/node_modules/.bin/tsc" --noEmit -p "$root"
done

if [ $fail -eq 1 ]; then
  echo $((n + 1)) > "$blocks"
  reason="verify-gate: checks failed on the files you changed. Fix these before finishing (attempt $((n + 1)) of 3):"$'\n'"$out"
  jq -n --arg r "$reason" '{decision: "block", reason: $r}'
  exit 0
fi
rm -f "$files" "$blocks"  # verified: start fresh for the next change
[ -n "$skipped" ] && jq -n --arg m "verify-gate: no checks run in $skipped (not a trusted repo). To check it, run: muster trust <repo>" '{systemMessage: $m}'
exit 0
