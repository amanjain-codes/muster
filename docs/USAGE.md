# Using Muster

## Global keys (herdr)

Alt = the **left** Option key.

| Key | What it does |
|---|---|
| `⌥d` | Open `dash` as a split on the right; press again to close it and return focus |
| `⌥e` | Your editor (`fresh`) full screen in an `ide` tab; press again to go back to the tab you came from. `fresh` keeps running, unsaved edits survive |
| `⌥n` | Fresh session: the agent writes a handoff note, `/clear`s, and continues from the note. Only when the agent is idle and its input box is empty |
| `⌥f` | File viewer: tree, diffs, rendered Markdown (see IDE.md) |
| `⌥r` | Review the agent's diff beside the chat (see IDE.md) |

The Claude status line shows these as `⌥d dash  ⌥e ide  ⌥n fresh`, plus the model, folder, branch, context %, session cost, and `⏰ <meeting> in 12m` from 30 minutes before a meeting.

## dash keys

| Key | Where | What it does |
|---|---|---|
| `Tab` / `Shift+Tab` | anywhere | next / previous section |
| `↑↓` or `j k` | anywhere | move |
| `r` or `R` | anywhere | refresh everything, Slack mentions included (Calendar/Jira/Slack take ~30 s) |
| `q` | anywhere | close dash |
| `o` | any row with a link | open in the browser |
| `C` | any row | type a prompt about it into the Claude pane in this tab (**not sent**: you review and press Enter) |
| `a` `e` `space` `d` | TODO | add, edit, tick done, delete (after `y/n`) |
| `n` | JIRA | start a new agent on the ticket in its own tab and worktree (after `y/n`) |
| `b` / `v` | JIRA | write a brief on the ticket (repo, files, likely fix, size, open questions; reads only, ~1.5 min) / read it |
| `s` | PULL REQUESTS | post the PR to your team channel (after `y/n`; needs `slack.share_channel_id`) |
| `M` | PULL REQUESTS | merge when green, your PRs only (after `y/n`) |
| `v` | REVIEWS | Claude reviews the PR (verdict, summary, risky spots; ~25 s), then `v` again to read it |
| `A` | REVIEWS | approve and merge when green (after `y/n`; refused for drafts and red CI) |
| `c` / `F` | CLEAN UP | remove a merged PR's worktree; `F` first stashes uncommitted changes |
| `g` `x` `X` | AGENTS | go to the agent; send `/compact`; close it (after `y/n`, resumable) |
| `w` / `v` | RECAP | write today's recap / view it |

Every action that changes something asks `y/n` first and refuses when it's unsafe (agent busy, text in its input box, uncommitted changes).

## Sections

- **TODO**: notes in `~/.config/muster/todo.md` (plain markdown, edit it anywhere; shared by every dash).
- **TODAY / JIRA**: from your claude.ai connectors, fetched in the background (see SPECS.md for timing and cost).
- **PULL REQUESTS**: your open PRs in `github.orgs`, with CI state.
- **REVIEWS**: PRs in `github.review_repos` that wait on your review, oldest first, with how long they've waited. Hidden when `review_repos` is empty.
- **CLEAN UP**: shows only when a worktree's PR has merged.
- **ARTIFACTS**: your last 5 artifacts created, updated or opened from Claude Code.
- **SLACK**: the unread count from the Slack app's Dock badge, then who mentioned or DM'd you in the last 24 hours (bots and your own messages left out); `o` opens the thread.
- **AGENTS**: every Claude agent in herdr with its exact context %, working/idle, and idle time; stale (idle > 1 day) first.
- **SPEND**: today / week / month across all Claude sessions (ccusage; API-price estimates).
- **RECAP**: an end-of-day summary of what each agent did.
- **DOCTOR**: appears only when a health check fails, with the fix.

## Slash commands (any Claude session)

| Command | What it does |
|---|---|
| `/watch-ci [PR]` | watches CI, reports failures as soon as they appear, with the cause and a fix |
| `/writeup <who>` | a Slack-ready summary of the current work, ≤ 120 words; never posts without asking |
| `/tell <agent> <message>` | message another agent; the agent is matched by space name, tab or label |
| `/learn [rule] [global]` | turn a correction into a rule in the repo's `CLAUDE.md` (or your global one) |
| `/handoff [path]` | write a handoff note (⌥n uses it) |

## Gates (automatic, every session)

- **Verify gate**: when an agent tries to finish, the files it edited are checked: Go build + tests of touched packages, Python compile, TypeScript `tsc`, or your repo's own `.claude/verify.sh`. Failures go back to the agent; at most 3 rounds.
- **Review gate**: an agent can't `git push` a commit until that exact commit is marked reviewed (it runs the code-review skill first). Your own pushes in a shell are not affected.
- **CI autopilot**: after an agent's push lands on a branch with a PR, CI is watched in the background.

## Health

`muster doctor` checks hooks, keys, the plugin, commands, the status line, the fetcher and tools, and prints a fix for each failure. dash runs it every 10 minutes.
