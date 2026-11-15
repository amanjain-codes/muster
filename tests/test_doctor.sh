#!/bin/bash
# muster doctor on a machine without Muster: one clear line, not a list of failures.
set -u
D=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; expect() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (want '$3', got '$2')"; fail=1; fi; }
out=$(HOME="$T" python3 "$D/../plugin/doctor.py" --quick 2>&1); rc=$?
expect "not installed: exits 1" "$rc" "1"
expect "not installed: says so" "$(grep -c "Muster isn't installed" <<<"$out")" "1"
expect "not installed: names the installer" "$(grep -c 'install.sh' <<<"$out")" "1"
expect "not installed: no per-check noise" "$(grep -c 'hook ' <<<"$out")" "0"
json=$(HOME="$T" python3 "$D/../plugin/doctor.py" --quick --json)
expect "not installed: JSON for dash" "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(len(r), r[0]["ok"])' "$json")" "1 False"
mkdir -p "$T/.local/share/muster" && touch "$T/.local/share/muster/install-manifest.txt"
out=$(HOME="$T" python3 "$D/../plugin/doctor.py" --quick 2>&1)
expect "installed: no 'not installed' line" "$(grep -c "isn't installed" <<<"$out")" "0"
expect "installed: runs the real checks" "$([ "$(grep -cE '✓|✗' <<<"$out")" -gt 5 ] && echo yes || echo no)" "yes"
exit $fail
