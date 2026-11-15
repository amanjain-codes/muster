---
description: Write a handoff note so this work can continue in a fresh session (⌥n does this, then /clear, then resumes)
argument-hint: "[path for the note]  (default: ~/.claude/handoffs/<date-time>.md)"
allowed-tools: Write, Bash(mkdir:*), Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git diff --stat:*)
---

Write a handoff note to: $ARGUMENTS (if empty: `~/.claude/handoffs/<YYYY-MM-DD-HHMM>.md`; create the folder if needed).

A fresh session will read only this note, so it must be enough to carry on without this conversation. Check `git status`, the branch and recent commits for anything you're unsure of. Under 45 lines, in this shape:

```
# Handoff: <one-line goal>
cwd: <absolute path>   branch: <branch>   PR/ticket: <links or none>

## Goal
<what we're trying to achieve and why, 1-3 lines, including any constraint I set>

## Done
- <finished and verified, with file paths>

## State now
- <uncommitted changes, what's half-done, what's running or waiting (CI, reviews)>

## Next
1. <the very next concrete step>
2. ...

## Watch out
- <decisions made and why, things that didn't work, rules I gave you, open questions for me>
```

Only facts from this session: mark anything unverified as such. Write the file, then reply with exactly one line: `handoff: <path>`.
