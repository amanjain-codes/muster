# Architecture

```
Ghostty (terminal, theme, fonts)
└── herdr (spaces, tabs, panes, agent tracking, plugins, keys)
    ├── Claude Code agents (one per pane)
    │   ├── status line ── writes each session's context % ──────────────┐
    │   │                └ starts a background fetch every ≤30 min ──┐    │
    │   ├── hooks: verify-gate · review-gate · ci-autopilot          │    │
    │   └── commands: /watch-ci /writeup /tell /learn /handoff       │    │
    └── dash plugin (muster)                                      │    │
        ├── dash.py      the TUI (Textual), reads everything below   │    │
        ├── fetch.py  ◄──────────────────────────────────────────────┘    │
        ├── ci_watch.py  (started by the ci-autopilot hook)               │
        ├── recap.py · doctor.py · dashconf.py                            │
        └── toggle.sh (⌥d) · editor.sh (⌥e) · handoff.sh (⌥n)             │
                                                                          │
~/.cache/muster/ctx/<session>.json ◄────────────────────────────────────────┘
```

## Where each section's data comes from

| Section | Source | How |
|---|---|---|
| Agents | `herdr pane list` + `~/.cache/muster/ctx/<session>.json` | exact context % from the status line; falls back to tokens from the session log |
| Pull requests | `gh api graphql` | one search query with check rollups |
| Today, Jira | claude.ai connectors | `fetch.py` runs headless `claude -p` (Haiku) with **read-only** connector tools only → `~/.cache/muster/comms.json` |
| Slack | Slack app Dock badge | `lsappinfo`; the connector can't see read state |
| Artifacts | Claude Code session logs | incremental scan of `~/.claude/projects/*/*.jsonl` for Artifact tool calls |
| Spend | `ccusage` | local Claude Code logs |
| Clean up | git worktrees + `gh` merged-PR search | matched on repo **and** branch |
| Recap | today's prompts/replies in session logs | `recap.py` → Haiku, no tools |
| Doctor | `doctor.py --json` | 20 checks |

## Writes, and who does them

| Action | Done by |
|---|---|
| Post a PR to Slack (`s`) | headless `claude -p` with only `slack_send_message` allowed |
| Merge when green (`M`) | `gh pr merge --auto` with the repo's default method |
| Ticket → agent (`n`) | `herdr tab create` + `claude` + `herdr agent prompt` |
| CI fix rounds | `herdr agent prompt` to the agent that pushed |
| Clean up (`c`/`F`) | `git stash` (F) + `git worktree remove` + `git branch -d` |
| `C`, `x`, `/tell` | `herdr pane send-text` (C: no Enter) / `herdr agent prompt` |

## Files on your machine

| Path | What |
|---|---|
| `~/.local/share/muster/dash/` | the plugin (installed copy) |
| `~/.config/muster/config.toml`, `.env` | your settings and optional tokens |
| `~/.config/muster/todo.md`, `recaps/`, `shared-prs.json` | your notes, recaps, which PRs you shared |
| `~/.cache/muster/` | caches: comms, context %, CI state, artifact index (safe to delete) |
| `~/.claude/hooks/`, `~/.claude/commands/`, `~/.claude/statusline-muster.sh` | Claude Code parts |
| `~/.claude/handoffs/` | handoff notes |

## Design decisions worth knowing

- **Terminal palette, not hex colours**: dash and the status line follow the Ghostty theme automatically.
- **No zoom to move focus**: zooming resizes the Claude pane, which makes Claude Code redraw the whole conversation (looks like it scrolled). Focus moves by direction or `herdr agent focus`.
- **Fetch through Claude, not tokens**: Calendar/Jira use the connectors you already signed into; nothing to configure, nothing to leak.
- **Every write asks y/n**, and refuses when it would type over a draft or lose changes.
