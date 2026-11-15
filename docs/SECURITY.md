# Security and privacy

## What is never in this repo

Tokens, IDs of your Slack channels or groups, your GitHub org, folder paths, names, ticket data. Those live in `~/.config/muster/config.toml` and `~/.config/muster/.env` on your machine; `.gitignore` excludes both, and `.env` is created with mode `600`.

## No tokens by default

- GitHub: your `gh auth login` session.
- Jira, Google Calendar, Slack: the claude.ai connectors you already signed into in Claude Code.
- Spend: local Claude Code logs.

Optional tokens (e.g. `GH_TOKEN`) go in `.env` only.

## What background jobs can do

| Job | Model | Tools allowed |
|---|---|---|
| Calendar/Jira fetch | Haiku | read-only: list/search/get events, Jira search, Atlassian resources/user info |
| Recap | Haiku | none |
| Share a PR | Haiku | `slack_send_message` only, and only after you press `y` |

Headless runs are locked down three ways: `--tools ToolSearch` (no Bash, no file edits; ToolSearch only loads tool definitions), `--permission-mode dontAsk` (anything not pre-approved is refused), and `--allowedTools` (only the tools in the table). "Pre-approved" may also include allow rules in your own Claude settings, so keep broad MCP allow rules (for example a whole Slack or Jira server) out of `~/.claude/settings.json`. Verified: a locked fetch asked to run a shell command had no shell; asked to post to Slack, the call was refused.

## Untrusted input

Calendar events, Jira tickets and CI check names are written by other people, so Muster treats them as data:

| Where it shows up | How it's handled |
|---|---|
| Meeting titles in the status line | control characters, backslashes and `%` stripped before printing (no terminal escape injection) |
| Ticket → agent (`n`) | the agent gets only a validated key (`ABC-123`) and Jira link, never the ticket's text, and is told the ticket is information, not instructions |
| CI failures handed back to an agent | check names reduced to a safe character set, max 60 chars, labelled as data |
| `o` (open link) | only `https://` links and `slack://open`; never files or other app schemes |
| Background fetch | read-only tools only (above), so injected instructions in an event or ticket can't act |

## What leaves your machine

- Connector requests go through your Claude account, as when you use the connectors yourself.
- The recap sends today's trimmed prompts/replies (≤ 280 chars each, ≤ 30 per agent) to Claude to summarize.
- A shared PR posts its title, link, CI state and your configured mention to your configured channel; Slack adds "Sent using Claude".
- Nothing is sent anywhere else. No telemetry.

## What stays local

Caches (`~/.cache/muster/`): calendar titles and times, Jira keys/titles/statuses, context %, CI state, the artifact index (share keys `?sk=` are stripped and never stored).

## Gates

- **Verify gate** runs build/tests, which is the repo's own code, so it runs only in repos listed in `~/.config/muster/trusted-roots` (`muster trust` inside a repo adds it; the list starts empty). Exact repos, not parent folders: a clone or fork checkout dropped into your code folder never runs unasked. A worktree counts as its main repo only if that repo's own `git worktree list` includes it (a folder's `.git` file can point anywhere). Anywhere else it runs nothing and says so once per session. Capped at 3 rounds, can't loop. Trusting a repo trusts whatever branch is checked out in it, including someone else's PR.
- **`A` (approve + merge)** approves the exact commit dash showed (the review names that commit) and is refused when your Claude review is for an older commit. With CI green it merges at once with `--match-head-commit`, which GitHub checks at merge time. With CI still running, dash keeps the merge itself (`~/.cache/muster/merge-queue.json`) instead of GitHub auto-merge, which stays on when someone with write access pushes: it merges only when CI is green on that same commit, and drops the merge if new commits arrive or CI goes red.
- **Review gate** blocks an agent's `git push` until that exact commit is marked reviewed. It parses commands the way a shell does (chains, `cd`, `git -c/-C`, path-qualified git, `env`/`command` wrappers, `sh -c`, `eval`) and only exempts delete-only or tags-only pushes. If its parser goes missing it **blocks** pushes rather than allowing them. It never touches pushes you run yourself.
- **What the gates are not**: guardrails so checks and reviews aren't forgotten, not a sandbox against a deliberately misbehaving agent. An agent with shell access could write the review marker itself; the agent's own permission settings are the real boundary.

## Reporting

Found a problem? Open a private issue in this repo or contact the maintainer directly; don't post details publicly.
