# Changelog

All notable changes to Muster. Versions follow [semantic versioning](https://semver.org): breaking changes bump the major, features the minor, fixes the patch.

## 0.3.1 (2026-11-15)

- `install.sh --dry-run` changes nothing (it created `~/.local/share/muster`) and no longer crashes on a machine without `~/.claude/settings.json` or a herdr config.
- `muster doctor` on a machine without Muster says so in one line, with the install command, instead of listing every check as failed.

## 0.3.0 (2026-11-15)

- REVIEWS can follow a Slack channel: `slack.review_channel_id` adds every open PR posted there (any repo in `github.orgs`), marked `#`, next to direct requests in `review_repos`, marked `→`. Merged, closed, your own and already-approved PRs are hidden. Links must be github.com PRs in your orgs.

## 0.2.2 (2026-11-15)

- `github.review_max_age_hours`: REVIEWS shows only requests made within that many hours (0 = all).
- Installer copies plugin files only (a test run's `__pycache__` broke the install) and leaves `settings.json` untouched when nothing changed.

## 0.2.1 (2026-11-15)

Security fixes from a review of 0.2.0:
- `A` approves only the commit dash showed: it checks the PR's live head first and merges with `--match-head-commit`, so commits pushed in between are never approved or merged unseen. A review written for an older commit is marked and `v` writes a fresh one.
- PR reviews wrap the PR's text in a random marker per run, so a PR can't fake the end of its data block to steer the verdict.
- Jira and Calendar rows from the background fetch are now checked like Slack rows (real ticket keys, Atlassian/Google Calendar links only), since one run reads all three.
- Terminal control characters are stripped from briefs and reviews.

## 0.2.0 (2026-11-15)

- **REVIEWS** section: PRs in `github.review_repos` waiting on your review, oldest first. `v` Claude review (verdict, summary, risky spots), `A` approve and merge when green (asks first; refuses drafts and red CI), `o` open.
- **Ticket brief** (`b` on a JIRA row): repo, likely files, fix, size and open questions, written by a Claude that can only read your code folder and Jira. `v` reads it.
- **Slack mentions**: who mentioned or DM'd you in the last 24 hours, under the unread count. Refreshed every 30 minutes; links must be Slack permalinks.
- **Background Claude calls are ~50x cheaper**: they now run with `--tools ToolSearch` instead of `--tools ""`, which sent every connector's tool schema (~420k tokens) on each call. A Calendar/Jira fetch went from ~$0.62 to ~$0.01. Allowed tools are unchanged.
- Briefs and reviews show their model and cost at the bottom.

## 0.1.0 (2026-11-15)

First release.

- **dash** dashboard on `⌥d`: TODO, today's meetings, Jira (stories and bugs), your PRs with CI, merged-worktree clean-up, recent artifacts, Slack unread, agents with exact context %, spend, end-of-day recap, and a health section that appears only when something breaks.
- **`⌥e`** editor in its own tab and **`⌥n`** fresh session with context carried over.
- **Gates**: verify gate (build/test what the agent changed) and review gate (no push of an unreviewed commit).
- **CI autopilot**: watches CI after an agent's push; red goes back to the agent (2 rounds), green notifies you.
- **Ticket → agent → worktree → clean-up**, and one-key PR sharing to a Slack channel.
- **Slash commands**: `/watch-ci`, `/writeup`, `/tell`, `/learn`, `/handoff`.
- **`muster` CLI**: `doctor`, `update`, `config`, `install`, `uninstall`, `test`, `version`.
- One-command install; safe, idempotent installer with backups and full uninstall.
- **IDE**: fresh editor setup (VS Code keys, Everforest, Markdown rendered), file viewer (`⌥f`) and diff review (`⌥r`) plugins, auto-titled tabs.
- **Security**: headless Claude runs locked to their exact tools; untrusted calendar/Jira/CI text sanitized; verify gate runs only in trusted folders (`muster trust`); review gate parses commands like a shell and fails closed.
- Local test suite (see `muster test`).
