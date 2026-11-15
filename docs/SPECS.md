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
| Reviews | 2 min | one GraphQL search, only when `review_repos` is set |
| Artifacts | 60 s | incremental log scan |
| Calendar/Jira cache read | 30 s | fetch itself runs when the cache is > 10 min old |
| Slack mentions | 30 min | part of the fetch; `r` forces it (`MUSTER_SLACK_EVERY` to change) |
| Spend | 5 min | ccusage |
| Health check | 10 min | `doctor --quick` |
| Spinner | 0.3 s | only while an agent is working |

The status line also starts a background Calendar/Jira fetch when the cache is > 30 min old (at most one start per 5 min, one fetch at a time).

## Measured performance and cost (Claude Code 2026-11, Apple Silicon)

| Operation | Time | Cost |
|---|---|---|
| Calendar + Jira + Slack fetch (Haiku, read-only tools) | 25–45 s | ~$0.01 per run |
| Ticket brief, `b` (Sonnet, reads code + Jira) | ~1.5 min | ~$0.28 |
| PR review, `v` in REVIEWS (Sonnet, no tools) | ~25 s | ~$0.08 for a 1,300-line diff |
| End-of-day recap (Haiku, no tools) | ~27 s | ~$0.01 |
| Share a PR to Slack | ~10 s | ~$0.01 |
| `/watch-ci` on a failing PR (Sonnet) | ~22 s | ~$0.19 |
| `/learn` (Sonnet) | ~15 s | ~$0.16 |
| `⌥n` handoff → fresh session (Haiku agent) | ~15 s | depends on the agent's model |
| Artifact index, first scan / incremental | 3.2 s / 0.03 s | – |
| `muster doctor` (20 checks) | ~2 s | – |
| Status line render | 0.08 s | – |

Every background Claude call runs with `--tools ToolSearch`. With `--tools ""` Claude Code sends every connector's tool
schema up front (~420k tokens, ~$0.40 even for a one-word reply) and deferred connector tools can fail to load.
ToolSearch only loads definitions; `--permission-mode dontAsk` still refuses any tool not in `--allowedTools`.

## Limits (known)

- Context % for an agent appears after its next reply (until then: tokens from its log).
- Slack count = the Dock badge: unread DMs + mentions; thread replies count only if your Slack notification settings include them.
- Slack mentions are "last 24 hours", not "unread": the connector can't see read state.
- Artifacts viewed only in the browser, or made on claude.ai, aren't in Claude Code's logs, so they don't show.
- Splits resize the neighbouring pane once on open/close; Claude Code redraws once. Unavoidable with splits.
- Verify gate knows Go, Python, TypeScript; other stacks need a repo `.claude/verify.sh`.
- Spend is ccusage's API-price estimate, not a subscription bill.

## Test coverage

`tests/run_all.sh`: 97 checks. Verify gate (8): pass, compile error, failing test, fixed, retry cap, Python syntax, repo override, untrusted folder skipped. Review gate (17, incl. bypass attempts): push variants, `cd`/`-C` chains, quoted text, delete/tags, non-repo, reviewed, new commit. CI watcher (4): green, two fix rounds, needs-you, stuck. CI hook (5): landed push, reaches green, non-push, failed push, delete. Notes (22, incl. a fake end marker, escape codes and the recorded head commit): bad keys refused, brief limited to Read/Grep/Glob in the code folder + read-only Jira, review gets no acting tools, diff and PR text kept inside markers, big diffs cut, failures leave a note. Fetch clean-up (18, incl. forged Jira/Calendar links): links must be Slack permalinks, control characters stripped, caps, only the search tool. dash UI (23, incl. reviews of an older commit and the age limit): REVIEWS and Slack rows render, `A` asks first and refuses drafts and red CI, `v` opens briefs and reviews.
