# Changelog

All notable changes to Muster. Versions follow [semantic versioning](https://semver.org): breaking changes bump the major, features the minor, fixes the patch.

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
