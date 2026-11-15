#!/usr/bin/env python3
"""Fetch Calendar and Jira data for dash through headless Claude and the claude.ai connectors.

Writes ~/.cache/muster/comms.json (mode 600). On failure keeps the last good data and records the error.
The run gets read-only tools only: it cannot send, accept, edit or delete anything.
"""

from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

CACHE = Path.home() / ".cache" / "muster"
OUT = CACHE / "comms.json"
LOCK = CACHE / "fetch.lock"

sys.path.insert(0, str(Path(__file__).parent))
from dashconf import CFG  # noqa: E402  per-user settings: ~/.config/muster/config.toml

CAL, JIRA = CFG["connectors"]["calendar"], CFG["connectors"]["jira"]
READ_TOOLS = [CAL + "list_events", CAL + "search_events", CAL + "get_event", CAL + "list_calendars",
              JIRA + "getAccessibleAtlassianResources", JIRA + "atlassianUserInfo", JIRA + "searchJiraIssuesUsingJql"]
# Slack is not fetched here: dash reads the Slack app's Dock badge, the only true unread source.


def prompt() -> str:
    now = dt.datetime.now().astimezone()
    return f"""You are a data fetcher for a terminal dashboard. Now is {now.isoformat(timespec='minutes')} ({now.strftime('%A')}).
Use only the tools you have. Do not ask questions. Reply with ONE JSON object and nothing else, no prose, no code fence.

1. "today": my meetings for the rest of today, earliest first, at most 4. Call list_events on the primary calendar with a time range from now until 23:59 today, and read the event rows it returns. A response with only calendar metadata (summary, timeZone, accessRole) and no events means the day is empty: return [] and do not list it in errors. Only events I organized or accepted. Skip all-day events, events I declined or haven't answered, and events with no other attendees.
   Each: {{"start": "HH:MM" 24h local, "title": short title of at most 28 characters (drop prefixes like "Sync:" and filler words), "url": event html link or null}}.
2. "jira": Jira issues with JQL `{CFG['jira']['jql']}`, at most 6. Get the cloudId first with getAccessibleAtlassianResources.
   Each: {{"key": str, "title": short summary of at most 36 characters (drop bracketed tags like "[CTEM]"), "status": str (exactly as Jira shows it), "url": "https://<site>/browse/<key>"}}.
3. "errors": a list of short strings, one per part above that failed, else [].

Use null for a part you could not fetch, never invented data."""


def extract_json(text: str) -> dict:
    text = text.strip()
    try:
        return json.loads(text)
    except ValueError:
        m = re.search(r"\{.*\}", text, re.S)
        if not m:
            raise
        return json.loads(m.group(0))


def write(data: dict) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    os.chmod(tmp, 0o600)
    tmp.replace(OUT)


def main() -> int:
    CACHE.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # another fetch is already running

        old = json.loads(OUT.read_text()) if OUT.exists() else {}
        started = time.time()
        # The prompt goes on stdin: --allowedTools takes several values and would swallow a trailing prompt.
        cmd = ["claude", "-p", "--model", CFG["models"]["fetch"], "--output-format", "json",
               "--tools", "", "--permission-mode", "dontAsk", "--allowedTools", ",".join(READ_TOOLS)]
        try:
            r = subprocess.run(cmd, input=prompt(), capture_output=True, text=True, timeout=240, cwd=str(CACHE))
            if not r.stdout.strip():
                raise RuntimeError((r.stderr.strip().splitlines() or [f"exit {r.returncode}, no output"])[-1])
            envelope = json.loads(r.stdout)
            if envelope.get("is_error"):
                raise RuntimeError(str(envelope.get("result"))[:200])
            data = extract_json(envelope["result"])
            out = {
                "updated": time.time(),
                "took_s": round(time.time() - started, 1),
                "cost_usd": envelope.get("total_cost_usd"),
                "today": data.get("today") or [],
                "jira": data.get("jira") or [],
                "errors": data.get("errors") or [],
            }
            write(out)
            return 0
        except Exception as e:
            old["last_error"] = f"{type(e).__name__}: {e}"[:200]
            old["last_error_at"] = time.time()
            write(old)
            print(old["last_error"], file=sys.stderr)
            return 1


if __name__ == "__main__":
    sys.exit(main())
