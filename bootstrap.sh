#!/bin/bash
# One-command install of Muster for anyone with access to this private repo:
#
#   gh api repos/amanjain-codes/muster/contents/bootstrap.sh -H "Accept: application/vnd.github.raw" | bash
#
# Clones (or updates) the repo into ~/.muster and runs the installer with safe defaults.
set -euo pipefail
SLUG="${MUSTER_REPO:-amanjain-codes/muster}"
DEST="${MUSTER_HOME:-$HOME/.muster}"

[ "$(uname)" = "Darwin" ] || { echo "Muster is macOS-only for now."; exit 1; }
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
command -v gh >/dev/null || brew install gh
gh auth status >/dev/null 2>&1 || gh auth login </dev/tty

if [ -d "$DEST/.git" ]; then
  echo "==> Updating $DEST"; git -C "$DEST" pull --ff-only --quiet
else
  echo "==> Downloading Muster to $DEST"; gh repo clone "$SLUG" "$DEST" -- --quiet
fi
exec "$DEST/install.sh" --yes "$@" </dev/tty
