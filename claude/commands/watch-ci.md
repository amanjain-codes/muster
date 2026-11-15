---
description: Watch CI for a PR, commit or the current branch until it finishes, then report what failed and why
argument-hint: "[PR number | commit sha | branch]  (default: this branch's PR)"
model: sonnet
allowed-tools: Bash(gh:*), Bash(git:*)
---

Watch CI for: $ARGUMENTS

1. Resolve the target. A number is a PR. A sha or branch: find its PR with `gh pr list --search <sha-or-branch> --state all`, else watch its runs with `gh run list --commit <sha>` / `--branch <branch>`. Nothing given: the current branch's PR (`gh pr view --json number,url`).
2. Check the current state first with `gh pr checks <n>` (or `gh run list`). If any check has already failed, go straight to step 3 and report it: don't wait for the pending ones.
   Otherwise wait with `gh pr checks <n> --watch --fail-fast --interval 30` (or `gh run watch <id>`), in the background if it may outlast your command timeout. Give up after 30 minutes with no change and report which checks are stuck pending.
3. When it finishes, fails, or gets stuck:
   - All green: one line, e.g. "#412 CI green (12/12)".
   - Something failed: for each failed job, read the log (`gh run view <run-id> --log-failed | tail -120`) and give the job name, the root cause in one sentence with the key log line quoted, and the fix you propose.
4. Don't push fixes or re-run jobs unless I ask. If the failure looks flaky (network, timeout, runner), say so and offer `gh run rerun <id> --failed`.

Keep the report short: no narration of the waiting.
