#!/usr/bin/env python3
"""End-of-day recap: what each Claude agent did today, written by headless Claude (Haiku, no tools).

Reads only today's prompts and replies from each session log, trimmed short, and writes
~/.config/muster/recaps/YYYY-MM-DD.md. Run by dash on R.
"""

from __future__ import annotations

import datetime as dt
import fcntl
import glob
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
OUT_DIR = HOME / ".config" / "muster" / "recaps"
LOCK = HOME / ".cache" / "muster" / "recap.lock"
MODEL = os.environ.get("MUSTER_RECAP_MODEL", "claude-haiku-5-5")
PER_MSG, PER_AGENT, MAX_AGENTS = 280, 30, 20


def herdr_labels() -> dict[str, str]:
    """session id -> 'space · tab label', for the agents herdr knows about."""
    try:
        h = os.environ.get("HERDR_BIN_PATH", "herdr")
        panes = json.loads(subprocess.run([h, "pane", "list"], capture_output=True, text=True).stdout)["result"]["panes"]
        spaces = {w["workspace_id"]: w["label"] for w in
                  json.loads(subprocess.run([h, "workspace", "list"], capture_output=True, text=True).stdout)["result"]["workspaces"]}
    except Exception:
        return {}
    out = {}
    for p in panes:
        sid = (p.get("agent_session") or {}).get("value")
        if sid:
            out[sid] = f"{spaces.get(p['workspace_id'], '?')} · {p.get('label') or ''}"
    return out


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""


def today_messages(path: str, day: str) -> list[str]:
    msgs = []
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            if day not in line:  # cheap pre-filter on the timestamp
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("entrypoint") == "sdk-cli":
                return []  # a headless `claude -p` run (fetcher, recap), not an agent
            if d.get("isSidechain") or not str(d.get("timestamp", "")).startswith(day):
                continue
            m = d.get("message") or {}
            role = m.get("role") if isinstance(m, dict) else None
            text = " ".join(text_of(m.get("content")).split()) if role else ""
            if not text or text.startswith("<"):  # skip tool output and system-injected blocks
                continue
            msgs.append(f"{'ME' if role == 'user' else 'AGENT'}: {text[:PER_MSG]}")
    return msgs[-PER_AGENT:]


def main() -> int:
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        today = dt.date.today()
        # Session logs store UTC timestamps; today's local work can start on the previous UTC date.
        days = {today.isoformat(), dt.datetime.now(dt.timezone.utc).date().isoformat()}
        start_of_day = dt.datetime.combine(today, dt.time()).timestamp()
        labels = herdr_labels()
        logs = [p for p in glob.glob(str(HOME / ".claude/projects/*/*.jsonl")) if os.path.getmtime(p) >= start_of_day]
        logs.sort(key=os.path.getmtime, reverse=True)
        blocks = []
        for path in logs[:MAX_AGENTS]:
            sid = Path(path).stem
            msgs = [m for day in sorted(days) for m in today_messages(path, day)][-PER_AGENT:]
            if not any(m.startswith("ME:") for m in msgs):
                continue  # no prompt from me today: background or subagent noise
            name = labels.get(sid) or Path(path).parent.name.split("-")[-1]
            blocks.append(f"### {name}\n" + "\n".join(msgs))
        if not blocks:
            body = "No agent activity today."
        else:
            prompt = ("Below are today's messages from each of my Claude Code agents (ME = my prompts, AGENT = replies, trimmed).\n"
                      f"There are exactly {len(blocks)} agents; write exactly {len(blocks)} sections, one per agent, using each "
                      "agent's ### name verbatim as a `## ` heading, and no other headings or sections. Under each heading, at most 2 bullets of what got done "
                      "and 1 bullet starting 'Left:' for what is open or blocked. Plain words, no filler, under 350 words total. "
                      "Only state what the messages show.\n\n" + "\n\n".join(blocks))
            r = subprocess.run(["claude", "-p", "--model", MODEL, "--output-format", "json", "--tools", "ToolSearch", "--permission-mode", "dontAsk"],
                               input=prompt, capture_output=True, text=True, timeout=300)
            envelope = json.loads(r.stdout)
            if envelope.get("is_error"):
                print(envelope.get("result"), file=sys.stderr)
                return 1
            body = envelope["result"].strip()
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        out = OUT_DIR / f"{today.isoformat()}.md"
        out.write_text(f"# Recap {today.strftime('%a %d %b')} · {time.strftime('%H:%M')}\n\n{body}\n")
        return 0


if __name__ == "__main__":
    sys.exit(main())
