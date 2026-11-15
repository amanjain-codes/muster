# Specifications

## Purpose

Let one developer run many Claude Code agents from a single terminal and stay oriented: what each agent is doing and how full its context is, what needs attention (tickets, PRs, CI, meetings, Slack), and what it costs, without switching apps or watching a feed.

## Requirements

| # | Requirement |
|---|---|
| R1 | Everything opens and closes with one key; the user's Claude pane is never resized by moving focus |
| R2 | Glanceable: one screen line per item, cut with `…`, never wrapped; text short by design |
| R3 | No streams or feeds: counts and states, not message bodies |
| R4 | Every write asks `y/n`; nothing types over a draft, discards changes or interrupts a working agent |
| R5 | One failing data source never blanks the others; stale data is labelled with its age |
| R6 | No secrets in the repo; default setup needs no tokens |
| R7 | Matches the terminal theme automatically |
| R8 | Agents prove their work: build/test before "done", review before push, CI watched after push |
| R9 | Install is idempotent, backs up what it touches, and can be fully undone |

## Non-goals

Not a Slack client, calendar editor or Jira form (those actions go through Claude with `C`); no agent controls beyond go / compact / close / message; macOS only.

## Refresh intervals (dash)

| Data | Every | Notes |
|---|---|---|
| Agents + Slack badge | 15 s | local, < 0.5 s |
| Pull requests + clean-up | 60 s | one GraphQL search |
| Artifacts | 60 s | incremental log scan |
| Calendar/Jira cache read | 30 s | fetch itself runs when the cache is > 10 min old |
| Spend | 5 min | ccusage |
| Health check | 10 min | `doctor --quick` |
| Spinner | 0.3 s | only while an agent is working |

The status line also starts a background Calendar/Jira fetch when the cache is > 30 min old (at most one start per 5 min, one fetch at a time).

## Measured performance and cost (Claude Code 2026-11, Apple Silicon)

| Operation | Time | Cost |
|---|---|---|
| Calendar + Jira fetch (Haiku, read-only tools) | 17–40 s | $0.01–0.02 per run (~$0.30 per active day) |
| End-of-day recap (Haiku, no tools) | ~27 s | ~$0.01 |
| Share a PR to Slack | ~10 s | ~$0.01 |
| `/watch-ci` on a failing PR (Sonnet) | ~22 s | ~$0.19 |
| `/learn` (Sonnet) | ~15 s | ~$0.16 |
| `⌥n` handoff → fresh session (Haiku agent) | ~15 s | depends on the agent's model |
| Artifact index, first scan / incremental | 3.2 s / 0.03 s | – |
| `muster doctor` (20 checks) | ~2 s | – |
| Status line render | 0.08 s | – |

## Limits (known)

- Context % for an agent appears after its next reply (until then: tokens from its log).
- Slack count = the Dock badge: unread DMs + mentions; thread replies count only if your Slack notification settings include them.
- Artifacts viewed only in the browser, or made on claude.ai, aren't in Claude Code's logs, so they don't show.
- Splits resize the neighbouring pane once on open/close; Claude Code redraws once. Unavoidable with splits.
- Verify gate knows Go, Python, TypeScript; other stacks need a repo `.claude/verify.sh`.
- Spend is ccusage's API-price estimate, not a subscription bill.

## Test coverage

`tests/run_all.sh`: 34 checks. Verify gate (8): pass, compile error, failing test, fixed, retry cap, Python syntax, repo override, untrusted folder skipped. Review gate (17, incl. bypass attempts): push variants, `cd`/`-C` chains, quoted text, delete/tags, non-repo, reviewed, new commit. CI watcher (4): green, two fix rounds, needs-you, stuck. CI hook (5): landed push, reaches green, non-push, failed push, delete.
