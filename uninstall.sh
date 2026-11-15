#!/bin/bash
# Undo install.sh: unlink the plugin, remove its hooks/commands/status line, restore your backed-up configs.
#   ./uninstall.sh          keep your ~/.config/muster (settings, .env, TODO notes, recaps)
#   ./uninstall.sh --purge  remove those too
set -uo pipefail
STATE="$HOME/.local/share/muster"; MANIFEST="$STATE/install-manifest.txt"
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1
[ -f "$MANIFEST" ] || { echo "Nothing to undo (no $MANIFEST)."; exit 0; }

echo "==> Removing hooks from ~/.claude/settings.json"
python3 - "$HOME/.claude/settings.json" "$HOME/.claude/statusline-muster.sh" <<'EOF'
import json, os, sys
path, sl = sys.argv[1], sys.argv[2]
if not os.path.exists(path): sys.exit()
d = json.load(open(path)); ours = ("verify-gate.sh", "review-gate.sh", "ci-autopilot.sh")
for ev, groups in list(d.get("hooks", {}).items()):
    kept = []
    for g in groups:
        g["hooks"] = [x for x in g.get("hooks", []) if not any(o in x.get("command", "") for o in ours)]
        if g["hooks"]: kept.append(g)
    if kept:
        d["hooks"][ev] = kept
    else:
        del d["hooks"][ev]  # leave no empty event lists behind
if "hooks" in d and not d["hooks"]: del d["hooks"]
if sl in json.dumps(d.get("statusLine", {})): d.pop("statusLine")
tmp = path + ".tmp"; json.dump(d, open(tmp, "w"), indent=2); os.replace(tmp, path); print("  done")
EOF

echo "==> Unlinking the plugin and removing installed files"
grep -q '^plugin muster' "$MANIFEST" && herdr plugin unlink muster >/dev/null 2>&1 && echo "  plugin unlinked"
awk '$1=="ghplugin" {print $2}' "$MANIFEST" | while read -r id; do herdr plugin uninstall "$id" >/dev/null 2>&1 && echo "  removed $id"; done
while read -r kind a b; do
  case "$kind" in
    file) case "$a" in "$HOME/.config/muster/"*) [ $PURGE -eq 1 ] && rm -f "$a" ;; *) rm -f "$a" ;; esac ;;
    dir)  rm -rf "$a" ;;
  esac
done < "$MANIFEST"

echo "==> Restoring the oldest backup of each config this installer changed"
# The first backup taken is your original file, from before any install run.
awk '$1=="backup" && !seen[$2]++ {print $2, $3}' "$MANIFEST" | while read -r orig bak; do
  case "$orig" in "$HOME/.claude/settings.json") continue ;; esac  # hooks were removed above; keep later edits you made
  [ -e "$bak" ] && cp -p "$bak" "$orig" && echo "  restored ${orig/#$HOME/~}"
done
command -v herdr >/dev/null && herdr server reload-config >/dev/null 2>&1
[ $PURGE -eq 1 ] && rm -rf "$HOME/.config/muster" "$HOME/.cache/muster"
mv "$MANIFEST" "$MANIFEST.undone-$(date +%Y%m%d-%H%M%S)"
echo "Done. Backups (*.bak-muster-*) were left in place; delete them when you're happy."
