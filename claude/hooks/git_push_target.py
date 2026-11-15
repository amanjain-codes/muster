#!/usr/bin/env python3
"""Find a `git push` that needs a review in a shell command; print the repo directory it runs in.

Shared by review-gate.sh (block unreviewed pushes) and ci-autopilot.sh (watch CI after a push).
Prints nothing when the command contains no gated push. Usage: git_push_target.py <command> <cwd>

Handles: chains (&& || ; | newlines), `cd dir`, env assignments and wrappers (env, command, exec, nohup,
time, xargs), path-qualified git (/usr/bin/git), git global options (-C dir, -c k=v, --git-dir, --work-tree, ...),
and `sh/bash/zsh -c "..."` / `eval "..."` (parsed recursively).
Exempt: pushes that only delete refs (--delete / -d / :ref) or only push tags (--tags with no branch refspec).
This is a guardrail against forgetting review, not a sandbox: an agent determined to bypass it can.
"""

from __future__ import annotations

import os
import re
import shlex
import sys

WRAPPERS = {"env", "command", "exec", "nohup", "time", "xargs", "builtin", "noglob"}
SHELLS = {"sh", "bash", "zsh", "dash"}
GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}


OPERATORS = {"&&", "||", ";", "|", "&", "(", ")", ";;", "|&"}


def segments(cmd: str) -> list[list[str]]:
    """Split a command line into simple commands, respecting quotes (so `bash -c "a && b"` stays one word)."""
    lex = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    out, cur = [], []
    try:
        for tok in lex:
            if tok in OPERATORS:
                if cur:
                    out.append(cur)
                cur = []
            else:
                cur.append(tok)
    except ValueError:  # unbalanced quotes: fall back to a plain split
        return [s.split() for s in re.split(r"&&|\|\||;|\||\n", cmd)]
    if cur:
        out.append(cur)
    return out


def find(cmd: str, cwd: str, depth: int = 0) -> str | None:
    if depth > 3:
        return None
    d = cwd
    for t in segments(cmd):
        # Strip leading VAR=value assignments and wrappers (with their flags, e.g. `env -i`, `command -p`).
        while t and (re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", t[0]) or t[0] in WRAPPERS):
            wrapper = t[0] in WRAPPERS
            t = t[1:]
            while wrapper and t and t[0].startswith("-"):
                t = t[1:]
        if not t:
            continue
        head = os.path.basename(t[0])
        if head == "cd" and len(t) > 1:
            d = os.path.normpath(os.path.join(d, os.path.expanduser(t[1])))
        elif head in SHELLS and "-c" in t and t.index("-c") + 1 < len(t):
            hit = find(t[t.index("-c") + 1], d, depth + 1)
            if hit:
                return hit
        elif head == "eval" and len(t) > 1:
            hit = find(" ".join(t[1:]), d, depth + 1)
            if hit:
                return hit
        elif head == "git":
            gd, i = d, 1
            while i < len(t) and t[i].startswith("-"):
                opt = t[i].split("=", 1)[0]
                if opt == "-C" and i + 1 < len(t):
                    gd = os.path.normpath(os.path.join(gd, os.path.expanduser(t[i + 1])))
                if opt in GIT_OPTS_WITH_ARG and "=" not in t[i]:
                    i += 1
                i += 1
            if i < len(t) and t[i] == "push" and needs_review(t[i + 1:]):
                return gd
    return None


def needs_review(args: list[str]) -> bool:
    flags = [a for a in args if a.startswith("-")]
    positional = [a for a in args if not a.startswith("-")]
    if any(f in ("--delete", "-d") for f in flags):
        return False
    refspecs = positional[1:]  # positional[0] is the remote
    if refspecs and all(re.fullmatch(r":[^:]+", r) for r in refspecs):
        return False  # `git push origin :branch` deletes; a bare `:` or `+:` pushes matching branches, so it's gated
    if "--tags" in flags and not refspecs:  # tags only (--follow-tags also pushes the branch, so it isn't exempt)
        return False
    return True


if __name__ == "__main__":
    hit = find(sys.argv[1], sys.argv[2])
    if hit:
        print(hit)
