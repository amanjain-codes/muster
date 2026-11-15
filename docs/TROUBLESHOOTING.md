# Troubleshooting

**Start with `muster doctor`.** It checks every part and prints the exact fix for each failure. dash shows `⚠ N` in its header when something is broken.

| Symptom | Cause | Fix |
|---|---|---|
| `⌥d` / `⌥e` / `⌥n` type a character instead | Ghostty isn't sending Alt | `macos-option-as-alt = left` in Ghostty config; use the **left** Option key |
| A key does something else | clash with your herdr bindings | change it in `~/.config/herdr/config.toml` (and the label in `statusline-muster.sh`), `herdr server reload-config` |
| Claude session jumps/scrolls when dash opens | the split resizes the pane; Claude Code redraws once | expected once per open/close; keep dash open and close it with `q` when needed |
| TODAY/JIRA say "stale" or "couldn't read" | the background fetch failed | `python3 ~/.local/share/muster/dash/fetch.py` to see why; check connectors in Claude Code (`/mcp`) |
| JIRA empty but you have tickets | connector tool names differ | set `[connectors] jira = "<your prefix>"` in config.toml (see `/mcp`) |
| Slack says "app not running" | the count comes from the Slack app's badge | open the Slack app |
| An agent shows "196k tokens" instead of % | it hasn't replied since the status line was installed | send it anything; the % appears after its next reply |
| PULL REQUESTS: `error: …` | `gh` not logged in, or wrong org | `gh auth login`; check `github.orgs` |
| SPEND: error | `bunx`/`npx` missing | `brew install node` (or install Bun) |
| `s` says "set slack.share_channel_id" | sharing is off | add the channel id (Slack → channel → About → Channel ID) |
| Agent can't push: "review-gate: commit … hasn't been reviewed" | working as intended | the agent runs a review, marks the commit, pushes again |
| Agent keeps getting "verify-gate: checks failed" | its change breaks build/tests | it fixes them; after 3 rounds it's allowed to stop and tells you |
| Want it all gone | – | `./uninstall.sh` (add `--purge` to remove your settings and notes too) |
