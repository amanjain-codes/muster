#!/bin/bash
# dash keys and rendering with sample data (REVIEWS, Slack mentions, briefs), in a scratch HOME. Needs uv, like dash.
set -u
D=$(cd "$(dirname "$0")" && pwd)
UV=$(command -v uv || echo "$HOME/.local/bin/uv")
[ -x "$UV" ] || { echo "  skip (uv not installed)"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.config/muster"
printf '[github]\norgs = ["acme"]\nreview_repos = ["acme/svc"]\n\n[slack]\nreview_channel_id = "C0TEAM"\n' > "$T/.config/muster/config.toml"
# Keep uv's real cache so the scratch HOME doesn't trigger a fresh download of textual.
UV_CACHE_DIR="${UV_CACHE_DIR:-$("$UV" cache dir)}" HOME="$T" MUSTER_CONFIG="$T/.config/muster/config.toml" \
  "$UV" run --quiet --script "$D/dash_ui_test.py"
