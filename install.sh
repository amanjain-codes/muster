#!/bin/bash
# Agentic terminal installer (macOS). Safe to re-run: every step is idempotent, every file it changes
# is backed up first, and nothing you already have is overwritten. Undo with ./uninstall.sh.
#
#   ./install.sh                 interactive
#   ./install.sh --yes           accept defaults, install missing tools without asking
#   ./install.sh --with-ghostty  also install the Ghostty config (your existing one is backed up)
#   ./install.sh --with-theme    also set herdr's Everforest theme (your config is backed up)
#   ./install.sh --dry-run       print what would happen, change nothing
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
MUSTER_DIR="${MUSTER_DIR:-$HOME/.local/share/muster/dash}"
STATE="$HOME/.local/share/muster"
MANIFEST="$STATE/install-manifest.txt"
STAMP="$(date +%Y%m%d-%H%M%S)"
YES=0; DRY=0; WITH_GHOSTTY=0; WITH_THEME=0
for a in "$@"; do case "$a" in
  --yes|-y) YES=1 ;; --dry-run) DRY=1 ;; --with-ghostty) WITH_GHOSTTY=1 ;; --with-theme) WITH_THEME=1 ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;; *) echo "unknown option: $a"; exit 2 ;;
esac; done

say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
run()  { if [ $DRY -eq 1 ]; then echo "  [dry-run] $*"; else eval "$@"; fi; }
ask()  { [ $YES -eq 1 ] && return 0; read -r -p "  $1 [Y/n] " r; [ -z "$r" ] || [[ "$r" =~ ^[Yy] ]]; }
prompt() { local q="$1" def="$2" v; if [ $YES -eq 1 ]; then echo "$def"; return; fi; read -r -p "  $q [$def]: " v; echo "${v:-$def}"; }
backup() {  # backup <file>: copy to <file>.bak-muster-<stamp> and record it for uninstall
  [ -e "$1" ] || return 0
  run "cp -p '$1' '$1.bak-muster-$STAMP'"
  [ $DRY -eq 1 ] || echo "backup $1 $1.bak-muster-$STAMP" >> "$MANIFEST"
}
record() { [ $DRY -eq 1 ] || echo "$*" >> "$MANIFEST"; }

[ "$(uname)" = "Darwin" ] || { echo "This installer is for macOS."; exit 1; }
[ $DRY -eq 1 ] || mkdir -p "$STATE"  # a dry run changes nothing, not even this folder

# ---------------------------------------------------------------- 1. tools
say "Checking tools"
command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh"; exit 1; }
need() {  # need <command> <description> <install command>
  if command -v "$1" >/dev/null 2>&1; then ok "$2"; return; fi
  if ask "$2 is missing. Install it with: $3 ?"; then run "$3"; else warn "$2 skipped: parts of the setup won't work until it's installed"; fi
}
[ -d /Applications/Ghostty.app ] && ok "Ghostty" || { ask "Ghostty is missing. Install it with brew?" && run "brew install --cask ghostty" || warn "Ghostty skipped"; }
need herdr "herdr (terminal workspace manager)" "curl -fsSL https://herdr.dev/install.sh | sh"
need uv    "uv (runs dash)"                   "brew install uv"
need gh    "GitHub CLI"                       "brew install gh"
need jq    "jq"                               "brew install jq"
need fresh "fresh (the editor ⌥e opens)"      "brew install fresh-editor"
command -v bunx >/dev/null || need npx "Node (npx runs ccusage for spend)" "brew install node"
ls ~/Library/Fonts/FiraCodeNerdFont* >/dev/null 2>&1 && ok "FiraCode Nerd Font" || { ask "FiraCode Nerd Font is missing (symbols in dash). Install it?" && run "brew install --cask font-fira-code-nerd-font" || true; }
if command -v claude >/dev/null; then ok "Claude Code"; else warn "Claude Code is missing: install it from https://claude.com/claude-code, then re-run"; fi
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
UV="$(command -v uv || echo uv)"; HERDR="$(command -v herdr || echo "$HOME/.local/bin/herdr")"

# ---------------------------------------------------------------- 2. dash plugin
say "Installing the dash plugin to ${MUSTER_DIR/#$HOME/~}"
run "mkdir -p '$MUSTER_DIR'"
# Files only: a test run leaves plugin/__pycache__, and cp on a folder fails the install under set -e.
run "find '$REPO/plugin' -maxdepth 1 -type f ! -name '*.pyc' -exec cp {} '$MUSTER_DIR'/ \\;"
run "sed -i '' 's#@UV@#$UV#' '$MUSTER_DIR/herdr-plugin.toml'"
run "chmod +x '$MUSTER_DIR'/*.sh '$MUSTER_DIR'/*.py"
record "dir $MUSTER_DIR"
if command -v herdr >/dev/null; then
  existing=$(herdr plugin list 2>/dev/null | grep -E '^- muster ' || true)
  if [ -n "$existing" ] && ! grep -q "local:$MUSTER_DIR" <<<"$existing"; then
    warn "a dash plugin is already linked from elsewhere ($existing); leaving it"
  else
    run "herdr plugin link '$MUSTER_DIR' >/dev/null" && ok "plugin linked" && record "plugin muster"
  fi
fi
run "mkdir -p '$HOME/.local/bin' && ln -sf '$REPO/bin/muster' '$HOME/.local/bin/muster'"
record "file $HOME/.local/bin/muster"

# ---------------------------------------------------------------- 2b. IDE: herdr plugins + fresh setup
say "IDE: file viewer, diff review, auto titles, fresh editor"
if command -v herdr >/dev/null; then
  installed=$(herdr plugin list 2>/dev/null || true)
  # Third-party code: pinned to reviewed commits (bump deliberately, after reading the diff).
  for spec in "herdr-file-viewer smarzban/herdr-file-viewer d89246d006e563f16b577468f04e13365d57fce6" \
              "persiyanov.reviewr persiyanov/herdr-reviewr 859dd5b11a5280fe282de56b52378b20a54fa10a" \
              "herdr.auto-title kryptamine/herdr-auto-title 8b2504514bb2aaa79ecbba6cb0e6c426652f4419"; do
    set -- $spec
    if grep -q "^- $1 " <<<"$installed"; then ok "$1 already installed"
    elif ! ask "Install the $1 plugin (github.com/$2 @ ${3:0:8}, MIT)?"; then warn "$1 skipped"
    elif run "herdr plugin install '$2' --ref '$3' --yes >/dev/null 2>&1"; then ok "$1 installed (github.com/$2 @ ${3:0:8}, MIT)"; record "ghplugin $1"
    else warn "$1 couldn't be installed: herdr plugin install $2 --ref $3"; fi
  done
fi
FR="$HOME/.config/fresh"; run "mkdir -p '$FR/themes'"
[ -e "$FR/themes/everforest-dark-hard.json" ] || { run "cp '$REPO/ide/fresh/themes/everforest-dark-hard.json' '$FR/themes/'"; record "file $FR/themes/everforest-dark-hard.json"; }
if [ -e "$FR/config.json" ]; then ok "fresh config exists: kept (Muster's is in ide/fresh/config.json)"
else run "cp '$REPO/ide/fresh/config.json' '$FR/config.json'"; ok "fresh config installed (VS Code keys, Everforest)"; record "file $FR/config.json"; fi
if [ -e "$FR/init.ts" ]; then ok "fresh init.ts exists: kept"
else run "cp '$REPO/ide/fresh/init.ts' '$FR/init.ts'"; ok "fresh: Markdown opens rendered"; record "file $FR/init.ts"; fi

# ---------------------------------------------------------------- 3. herdr keys (+ optional theme)
say "herdr key bindings"
HCONF="$HOME/.config/herdr/config.toml"
run "mkdir -p '$HOME/.config/herdr' && touch '$HCONF'"
backup "$HCONF"
added=0
python3 - "$REPO/herdr/keys.toml" "$HCONF" "$DRY" <<'EOF' && added=1 || true
import os, re, sys
src, dst, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
have = open(dst).read() if os.path.exists(dst) else ""  # a dry run never creates it
blocks = re.split(r"\n(?=\[\[keys\.command\]\])", open(src).read())
new = [b for b in blocks if b.startswith("[[keys.command]]") and re.search(r'command = "([^"]+)"', b).group(1) not in have]
taken = [k for b in new for k in re.findall(r'"(alt\+\w|prefix\+\w)"', b) if f'"{k}"' in have]
if taken:
    print("  ! these keys are already bound in your herdr config:", ", ".join(sorted(set(taken))), "- edit herdr/keys.toml and re-run"); sys.exit(1)
if new and not dry:
    open(dst, "a").write("\n# --- Muster (dash) ---\n" + "\n".join(new).rstrip() + "\n")
print(f"  \033[32m✓\033[0m {len(new)} binding(s) added" if new else "  \033[32m✓\033[0m bindings already present")
EOF
if [ $WITH_THEME -eq 1 ]; then
  if grep -q '^\[theme' "$HCONF"; then warn "herdr already has a [theme]; not changing it (see themes/README.md)"
  else run "cat '$REPO/themes/everforest-dark-hard/herdr.toml' >> '$HCONF'" && ok "Everforest theme added"; fi
fi
if command -v herdr >/dev/null && [ $DRY -eq 0 ]; then
  if herdr config check >/dev/null 2>&1; then herdr server reload-config >/dev/null 2>&1 || true; ok "herdr config valid and reloaded"
  else warn "herdr config check failed: restoring your previous config"; cp -p "$HCONF.bak-muster-$STAMP" "$HCONF"; fi
fi

# ---------------------------------------------------------------- 4. Claude Code: hooks, commands, status line
say "Claude Code hooks, commands and status line"
run "mkdir -p '$HOME/.claude/hooks' '$HOME/.claude/commands'"
for f in "$REPO"/claude/hooks/*.sh "$REPO"/claude/hooks/*.py; do
  dst="$HOME/.claude/hooks/$(basename "$f")"; tmp="$(mktemp)"
  sed "s#@MUSTER_DIR@#$MUSTER_DIR#g" "$f" > "$tmp"
  if [ -e "$dst" ] && ! cmp -s "$tmp" "$dst"; then backup "$dst"; fi
  run "cp '$tmp' '$dst' && chmod +x '$dst'"; rm -f "$tmp"; record "file $dst"
done
for f in "$REPO"/claude/commands/*.md; do
  dst="$HOME/.claude/commands/$(basename "$f")"
  if [ -e "$dst" ] && ! cmp -s "$f" "$dst"; then warn "/$(basename "$f" .md) already exists and differs: kept yours"; continue; fi
  run "cp '$f' '$dst'"; record "file $dst"
done
SL="$HOME/.claude/statusline-muster.sh"
run "sed 's#@MUSTER_DIR@#$MUSTER_DIR#g' '$REPO/claude/statusline.sh' > '$SL' && chmod +x '$SL'"; record "file $SL"
SETTINGS="$HOME/.claude/settings.json"
[ -e "$SETTINGS" ] || run "echo '{}' > '$SETTINGS'"
backup "$SETTINGS"
python3 - "$SETTINGS" "$HOME/.claude/hooks" "$SL" "$DRY" <<'EOF'
import json, os, sys
path, hooks, sl, dry = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
d = json.load(open(path)) if os.path.exists(path) else {}; h = d.setdefault("hooks", {})  # absent in a dry run
want = [("PostToolUse", "Edit|Write|MultiEdit", "verify-gate.sh record", 10), ("Stop", "", "verify-gate.sh stop", 400),
        ("PreToolUse", "Bash", "review-gate.sh", 15), ("PostToolUse", "Bash", "ci-autopilot.sh", 30)]
added = 0
for ev, matcher, cmd, timeout in want:
    full = f"{hooks}/{cmd}"
    if not any(x.get("command", "").endswith(cmd) for g in h.get(ev, []) for x in g.get("hooks", [])):
        h.setdefault(ev, []).append({"matcher": matcher, "hooks": [{"type": "command", "command": full, "timeout": timeout}]}); added += 1
msg = f"{added} hook(s) registered" if added else "hooks already registered"
if "statusLine" not in d:
    d["statusLine"] = {"type": "command", "command": sl}; msg += "; status line set"
elif sl not in json.dumps(d["statusLine"]):
    msg += f"; you already have a status line, kept it (to use dash's: set statusLine.command to {sl})"
changed = bool(added) or "status line set" in msg
if changed and not dry:  # leave the file byte-for-byte alone when nothing changed
    tmp = path + ".tmp"; json.dump(d, open(tmp, "w"), indent=2, ensure_ascii=False); os.replace(tmp, path)
print("  \033[32m✓\033[0m " + msg)
EOF
record "settings $SETTINGS"

# ---------------------------------------------------------------- 5. your settings
say "Your settings (~/.config/muster)"
CDIR="$HOME/.config/muster"
# Coming from the pre-Muster "dash" setup: carry settings, notes, recaps and shared-PR history over (copy, not move).
OLD="$HOME/.config/dash"
if [ -d "$OLD" ] && [ ! -d "$CDIR" ]; then
  run "mkdir -p '$CDIR' && cp -Rp '$OLD'/. '$CDIR'/"; ok "copied your existing settings and notes from ~/.config/dash"
fi
run "mkdir -p '$CDIR'"
if [ -e "$CDIR/config.toml" ]; then ok "config.toml exists: kept"
else
  org=$(gh api user/orgs --jq '.[0].login' 2>/dev/null || true)
  org=$(prompt "GitHub org for your PRs" "${org:-your-github-org}")
  root=$(prompt "Where your repos live" "~/Projects")
  chan=$(prompt "Slack channel id for PR posts (blank = off)" "")
  cname=$(prompt "That channel's name" "#your-team")
  if [ $DRY -eq 0 ]; then
    # Python, not sed: answers can contain any character (# / & quotes).
    python3 - "$REPO/config/config.example.toml" "$CDIR/config.toml" "$org" "$root" "$chan" "$cname" <<'EOF'
import json, sys
src, dst, org, root, chan, cname = sys.argv[1:]
s = open(src).read()
for key, default, val in (("orgs", '["your-github-org"]', json.dumps([org])), ("code_root", '"~/Projects"', json.dumps(root)),
                          ("share_channel_id", '""', json.dumps(chan)), ("share_channel_name", '"#your-team"', json.dumps(cname))):
    s = s.replace(f"{key} = {default}", f"{key} = {val}", 1)
open(dst, "w").write(s)
EOF
  fi
  ok "config.toml written (edit any time)"; record "file $CDIR/config.toml"
fi
TR="$CDIR/trusted-roots"
if [ ! -e "$TR" ] && [ $DRY -eq 0 ]; then
  root_dir=$(python3 -c "import sys; sys.path.insert(0, '$REPO/plugin'); from dashconf import load; print(load()['workspace']['code_root'])" 2>/dev/null || echo "$HOME/Projects")
  printf '# Folders where the verify gate may run build/tests (one per line). Add more: muster trust <dir>\n%s\n' "$root_dir" > "$TR"
  ok "verify gate trusts ${root_dir/#$HOME/~} (muster trust <dir> to add more)"; record "file $TR"
fi
if [ -e "$CDIR/.env" ]; then ok ".env exists: kept"
else run "cp '$REPO/config/.env.example' '$CDIR/.env' && chmod 600 '$CDIR/.env'"; ok ".env created (private, mode 600)"; record "file $CDIR/.env"; fi

# ---------------------------------------------------------------- 6. Ghostty
say "Ghostty"
G="$HOME/.config/ghostty/config"; run "mkdir -p '$(dirname "$G")'"
if [ $WITH_GHOSTTY -eq 1 ] || [ ! -s "$G" ]; then
  # No config yet (or asked for ours): install the full Muster config.
  backup "$G"
  run "sed 's#@HERDR@#$HERDR#' '$REPO/ghostty/config' > '$G'"; ok "Ghostty config installed (restart Ghostty)"; record "file $G"
elif ! grep -q '^macos-option-as-alt' "$G"; then
  # You have your own config: add only the one line the ⌥ keys need.
  backup "$G"
  run "printf '\n# Muster: left Option acts as Alt so ⌥d / ⌥e / ⌥n reach herdr\nmacos-option-as-alt = left\n' >> '$G'"
  ok "added macos-option-as-alt = left to your Ghostty config (restart Ghostty)"
else
  ok "your Ghostty config already sends Alt: kept as is"
fi

# ---------------------------------------------------------------- 7. check
say "Health check"
[ $DRY -eq 1 ] || "$HOME/.local/bin/muster" doctor --quick || true
cat <<EOF

Next:
  1. In Claude Code, connect the claude.ai connectors you want: Google Calendar, Atlassian (Jira), Slack.
  2. gh auth login   (if not already)
  3. Open Ghostty, start herdr, press ⌥d for dash, ⌥e for the editor, ⌥n for a fresh session.
  muster help · muster doctor · muster update      Docs: $REPO/docs/USAGE.md
EOF
