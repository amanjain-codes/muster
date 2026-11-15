---
description: Turn a correction into a permanent rule in CLAUDE.md, so no agent makes the same mistake again
argument-hint: "[the rule, or leave empty to use my last correction]  [global]"
model: sonnet
allowed-tools: Read, Edit, Write, Bash(git rev-parse:*), Bash(git status:*), Bash(git diff:*), Bash(ls:*)
---

Lesson: $ARGUMENTS

1. Work out the rule.
   - Given above: use it.
   - Empty: take the most recent thing I corrected or pushed back on in this conversation. If there isn't a clear one, ask me what the rule is and stop.
   - Write it as one imperative line an agent can follow without context, plus a short reason when it isn't obvious.
     Example: "- Run `make proto` after editing any `.proto` file; CI fails on stale generated code."
     Specific beats general: name the command, file, flag or service.
2. Pick where it goes.
   - The lesson says "global", or it is about how I like to work rather than this codebase: `~/.claude/CLAUDE.md`.
   - Otherwise: the current repo's root (`git rev-parse --show-toplevel`). Use `CLAUDE.md` there; if the repo has only `AGENTS.md`, use that. Create `CLAUDE.md` if neither exists.
   - In a git worktree, write to the worktree's copy, so the rule ships with the branch.
3. Read the file first. If the same rule (or one that already covers it) is there, say so and stop. If a rule there contradicts it, show both and ask which one wins.
4. Add the line under a `## Learned rules` heading at the end of the file, creating the heading if it's missing. Change nothing else in the file.
5. Reply in two lines: the rule as written, and the file it went into. Don't commit or push: I'll commit it with the rest of the work, or tell you to.
