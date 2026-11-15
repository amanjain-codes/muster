"""Per-user settings for dash, read from ~/.config/muster/config.toml (see config.example.toml).

Every person- or company-specific value lives here, never in the code. Works on Python 3.9+:
uses tomllib when available, else a small reader for the flat TOML this file uses.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

PATH = Path(os.environ.get("MUSTER_CONFIG", str(Path.home() / ".config" / "muster" / "config.toml")))

DEFAULTS = {
    "github": {"orgs": []},
    "workspace": {"code_root": "~/Projects", "worktree_glob": "{code_root}/*.worktrees/*",
                  "new_agent": "direct"},  # "direct": dash starts claude; "autoclaude": a herdr plugin does
    "slack": {"share_channel_id": "", "share_channel_name": "", "share_mention": ""},
    "jira": {"jql": "assignee = currentUser() AND issuetype in (Story, Bug) AND statusCategory != Done ORDER BY updated DESC"},
    "connectors": {"calendar": "mcp__claude_ai_Google_Calendar__", "jira": "mcp__claude_ai_Atlassian_MCP__"},
    "models": {"fetch": "claude-haiku-5-5", "recap": "claude-haiku-5-5", "share": "claude-haiku-5-5"},
}


def _parse_min(text: str) -> dict:
    """Subset of TOML: [section], key = "str" | 'str' | number | true/false | ["a", "b"]."""
    out: dict = {}
    cur = out
    for raw in text.splitlines():
        line = raw.split(" #", 1)[0].strip()
        if not line or line.startswith("#"):
            continue
        m = re.fullmatch(r"\[([A-Za-z0-9_.-]+)\]", line)
        if m:
            cur = out.setdefault(m.group(1), {})
            continue
        if "=" not in line:
            continue
        k, v = (s.strip() for s in line.split("=", 1))
        if v.startswith("["):
            cur[k] = [a or b for a, b in re.findall(r'"([^"]*)"|\'([^\']*)\'', v)]
        elif v[:1] in "\"'":
            cur[k] = v[1:-1]
        elif v in ("true", "false"):
            cur[k] = v == "true"
        else:
            try:
                cur[k] = int(v)
            except ValueError:
                cur[k] = v
    return out


ENV_PATH = PATH.parent / ".env"

# MUSTER_* environment variables (or lines in ~/.config/muster/.env) override config.toml.
ENV_KEYS = {
    "MUSTER_GITHUB_ORGS": ("github", "orgs"),            # comma-separated
    "MUSTER_CODE_ROOT": ("workspace", "code_root"),
    "MUSTER_WORKTREE_GLOB": ("workspace", "worktree_glob"),
    "MUSTER_NEW_AGENT": ("workspace", "new_agent"),
    "MUSTER_SHARE_CHANNEL_ID": ("slack", "share_channel_id"),
    "MUSTER_SHARE_CHANNEL_NAME": ("slack", "share_channel_name"),
    "MUSTER_SHARE_MENTION": ("slack", "share_mention"),
    "MUSTER_JIRA_JQL": ("jira", "jql"),
    "MUSTER_MODEL_FETCH": ("models", "fetch"),
}


def load_env() -> None:
    """Read ~/.config/muster/.env (KEY=value lines) into the environment without overriding real env vars.
    Tokens such as GH_TOKEN can live here too: child tools (gh, claude) inherit them."""
    if not ENV_PATH.exists():
        return
    for raw in ENV_PATH.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = (s.strip() for s in line.removeprefix("export ").split("=", 1))
        if v[:1] in "\"'" and v[-1:] == v[:1]:
            v = v[1:-1]
        if v:
            os.environ.setdefault(k, v)


def load() -> dict:
    load_env()
    data: dict = {}
    if PATH.exists():
        text = PATH.read_text()
        try:
            import tomllib  # Python 3.11+
            data = tomllib.loads(text)
        except ImportError:
            data = _parse_min(text)
    cfg = {sec: {**vals, **data.get(sec, {})} for sec, vals in DEFAULTS.items()}
    for key, (sec, name) in ENV_KEYS.items():
        if os.environ.get(key):
            v = os.environ[key]
            cfg[sec][name] = [x.strip() for x in v.split(",") if x.strip()] if name == "orgs" else v
    ws = cfg["workspace"]
    ws["code_root"] = os.path.expanduser(ws["code_root"])
    ws["worktree_glob"] = os.path.expanduser(ws["worktree_glob"].replace("{code_root}", ws["code_root"]))
    return cfg


CFG = load()
