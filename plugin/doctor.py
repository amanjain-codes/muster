#!/usr/bin/env python3
"""muster doctor: check every moving part of the terminal setup and say what's broken and how to fix it.

  muster doctor          human report, exit 1 if anything failed
  muster doctor --json   [{"name","ok","detail","fix"}] for dash
  muster doctor --quick  skip the slow checks (ccusage)
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
HOOKS = HOME / ".claude" / "hooks"
SETTINGS = HOME / ".claude" / "settings.json"
PLUGIN = Path(__file__).resolve().parent  # works through the `muster doctor` command
CACHE = HOME / ".cache" / "muster"
HERDR = os.environ.get("HERDR_BIN_PATH") or shutil.which("herdr") or str(HOME / ".local/bin/herdr")
os.environ["PATH"] = os.pathsep.join([str(HOME / ".local/bin"), "/opt/homebrew/bin", os.environ.get("PATH", "")])

# Third-party herdr plugins that make up the IDE (all MIT), by plugin id -> GitHub repo.
IDE_PLUGINS = {"herdr-file-viewer": "smarzban/herdr-file-viewer", "persiyanov.reviewr": "persiyanov/herdr-reviewr",
               "herdr.auto-title": "kryptamine/herdr-auto-title"}

results: list[dict] = []


def check(name: str, ok: bool, detail: str = "", fix: str = "") -> None:
    results.append({"name": name, "ok": bool(ok), "detail": detail, "fix": "" if ok else fix})


def sh(cmd: list[str], stdin: str = "", timeout: int = 20) -> tuple[int, str]:
    try:
        r = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except OSError as e:
        return 127, str(e)


def hooks() -> None:
    try:
        cfg = json.loads(SETTINGS.read_text()).get("hooks", {})
    except (OSError, ValueError) as e:
        return check("settings.json readable", False, str(e), "Restore ~/.claude/settings.json from settings.json.bak-before-gates")
    want = [  # event, matcher, command suffix, smoke-test stdin
        ("PostToolUse", "Edit|Write|MultiEdit", "verify-gate.sh record", '{"session_id":"doctor","tool_input":{}}'),
        ("Stop", "", "verify-gate.sh stop", '{"session_id":"doctor-none","cwd":"/tmp"}'),
        ("PreToolUse", "Bash", "review-gate.sh", '{"cwd":"/tmp","tool_input":{"command":"git status"}}'),
        ("PostToolUse", "Bash", "ci-autopilot.sh", '{"cwd":"/tmp","tool_input":{"command":"git status"}}'),
    ]
    for event, matcher, suffix, smoke in want:
        name = f"hook {suffix.split()[0].replace('.sh', '')}" + (f" ({suffix.split()[1]})" if " " in suffix else "")
        registered = any(h.get("command", "").endswith(suffix) and g.get("matcher", "") == matcher
                         for g in cfg.get(event, []) for h in g.get("hooks", []))
        script = HOOKS / suffix.split()[0]
        if not registered:
            check(name, False, f"not registered under {event}", f"Re-add it to ~/.claude/settings.json hooks.{event} (matcher \"{matcher}\")")
            continue
        if not os.access(script, os.X_OK):
            check(name, False, f"{script} missing or not executable", f"chmod +x {script}")
            continue
        args = [str(script)] + suffix.split()[1:]
        rc, out = sh(args, smoke, timeout=15)
        check(name, rc == 0 and "error" not in out.lower(), f"smoke test exit {rc}" + (f": {out[:60]}" if rc else ""),
              f"Run it by hand to see the error: echo '{smoke}' | {' '.join(args)}")
    (CACHE.parent / "claude-verify").mkdir(parents=True, exist_ok=True)
    for f in (HOME / ".cache" / "claude-verify").glob("doctor*"):
        f.unlink(missing_ok=True)


def herdr() -> None:
    rc, out = sh([HERDR, "status", "server"], timeout=10)
    check("herdr server", rc == 0, "running" if rc == 0 else out[:60], "Start herdr, or run: herdr server reload-config")
    rc, out = sh([HERDR, "config", "check"], timeout=10)
    check("herdr config", rc == 0 and "ok" in out.lower(), out.splitlines()[0][:60] if out else "",
          "Fix ~/.config/herdr/config.toml (backups: config.toml.bak-before-*)")
    rc, out = sh([HERDR, "plugin", "list"], timeout=10)  # plain text: "- muster (dash) enabled [local:...]"
    line = next((l for l in out.splitlines() if l.strip().startswith("- muster ")), "")
    check("dash plugin linked", " enabled " in f" {line} ", line.split("[")[0].strip("- ").strip() or "not listed",
          f"herdr plugin link {PLUGIN} && herdr plugin enable muster")
    try:
        conf = (HOME / ".config" / "herdr" / "config.toml").read_text()
    except OSError:
        conf = ""
    for pid, repo in IDE_PLUGINS.items():
        here = next((l for l in out.splitlines() if l.strip().startswith(f"- {pid} ")), "")
        check(f"IDE plugin {pid}", " enabled " in f" {here} ", "", f"herdr plugin install {repo}")
    check("fresh editor", shutil.which("fresh") is not None, "", "brew install fresh-editor")
    for key, action in (("⌥d", "muster.toggle"), ("⌥e", "muster.editor"), ("⌥n", "muster.handoff"),
                        ("⌥f", "herdr-file-viewer.open-file-viewer"), ("⌥r", "persiyanov.reviewr.toggle")):
        check(f"key {key}", action in conf, action, f"Add a [[keys.command]] for {action} in ~/.config/herdr/config.toml, then herdr server reload-config")


def commands() -> None:
    missing = [c for c in ("watch-ci", "writeup", "tell", "learn", "handoff") if not (HOME / ".claude" / "commands" / f"{c}.md").exists()]
    check("slash commands", not missing, "missing: " + ", ".join(missing) if missing else "5 present",
          "Recreate the missing files in ~/.claude/commands/")


def statusline() -> None:
    sl = HOME / ".claude" / "statusline.sh"
    sample = json.dumps({"model": {"display_name": "Opus"}, "workspace": {"current_dir": str(HOME)},
                         "context_window": {"used_percentage": 10}, "cost": {"total_cost_usd": 1}})
    t = time.time()
    rc, out = sh(["bash", str(sl)], sample, timeout=10)
    took = time.time() - t
    check("status line", rc == 0 and "dash" in out and took < 1.5, f"{took:.2f}s", f"Run: echo '{sample}' | bash {sl}  (backup: statusline.sh.bak-before-dash)")
    ctx = list((CACHE / "ctx").glob("*.json"))
    fresh = [f for f in ctx if time.time() - f.stat().st_mtime < 86400]
    check("context % feed", bool(fresh), f"{len(fresh)} session(s) reported today", "The status line isn't writing ~/.cache/muster/ctx: check the block marked 'Share this session's exact context %'")


def fetcher() -> None:
    f = CACHE / "comms.json"
    if not f.exists():
        return check("calendar/jira fetch", False, "never ran", f"Run once: python3 {PLUGIN / 'fetch.py'}")
    d = json.loads(f.read_text())
    age = time.time() - d.get("updated", 0)
    failed = d.get("last_error_at", 0) > d.get("updated", 0)
    errs = d.get("errors") or []
    ok = not failed and age < 4 * 3600 and not [e for e in errs if "deprecated" not in e.lower()]
    detail = f"last ok {int(age // 60)}m ago" + (f"; last run failed: {d.get('last_error', '')[:50]}" if failed else "") + (f"; {errs[0][:50]}" if errs else "")
    check("calendar/jira fetch", ok, detail, f"Run by hand to see why: python3 {PLUGIN / 'fetch.py'}")


def tools(quick: bool) -> None:
    rc, out = sh(["gh", "auth", "status"], timeout=15)
    check("gh login", rc == 0, "logged in" if rc == 0 else out[:60], "gh auth login")
    check("claude CLI", shutil.which("claude") is not None, "", "claude must be on PATH for the fetcher, recap and share")
    check("uv", shutil.which("uv") is not None, "", "Install uv: dash runs with uv run --script")
    if not quick:
        rc, out = sh(["bunx", "ccusage@20.0.47", "--version"], timeout=60)
        check("ccusage (spend)", rc == 0, out[:30] if rc == 0 else out[:60], "bunx ccusage@20.0.47 --version  (needs bun on PATH)")
    rc, out = sh(["lsappinfo", "info", "-only", "StatusLabel", "Slack"], timeout=5)
    check("Slack app (unread badge)", "StatusLabel" in out, "running" if "StatusLabel" in out else "not running", "Open the Slack app")
    log = CACHE / "ci" / "autopilot.log"
    bad = log.exists() and "Traceback" in log.read_text(errors="ignore")[-4000:]
    check("CI autopilot", not bad, "no recent errors" if not bad else "errors in autopilot.log", f"tail -40 {log}")


def trust() -> None:
    # Since 0.3.2 the verify gate trusts exact repos only. An older folder entry (e.g. ~/Projects) now matches
    # nothing, so the gate would quietly stop checking the repos inside it: say so.
    path = HOME / ".config" / "muster" / "trusted-roots"
    try:
        lines = [l.strip() for l in path.read_text().splitlines()]
    except OSError:
        lines = []
    entries = [l for l in lines if l and not l.startswith("#")]
    folders = [e for e in entries if not (Path(os.path.expanduser(e)) / ".git").exists()]
    check("verify gate trust", not folders,
          f"{len(entries)} repo(s)" if not folders else f"not a repo: {', '.join(folders)[:50]}",
          f"Repos only now. Run 'muster trust' inside each repo you want checked, then remove the folder lines from {path}")


MANIFEST = HOME / ".local" / "share" / "muster" / "install-manifest.txt"  # written by install.sh, removed by uninstall


def main() -> int:
    quick = "--quick" in sys.argv
    if not MANIFEST.exists():
        # Without an install every check below fails, which reads like a broken machine. Say the real thing.
        repo = Path(__file__).resolve().parent.parent
        fix = f"{repo}/install.sh" if (repo / "install.sh").exists() else "the one-line install in the README"
        if "--json" in sys.argv:
            print(json.dumps([{"name": "Muster installed", "ok": False, "detail": "no install found", "fix": f"Run {fix}"}]))
        else:
            print(f" \033[31m✗\033[0m Muster isn't installed on this machine.\n   \033[33m→ Run {fix}\033[0m")
        return 1
    hooks(); trust(); herdr(); commands(); statusline(); fetcher(); tools(quick)
    if "--json" in sys.argv:
        print(json.dumps(results))
    else:
        bad = [r for r in results if not r["ok"]]
        for r in results:
            mark = "\033[32m✓\033[0m" if r["ok"] else "\033[31m✗\033[0m"
            print(f" {mark} {r['name']:<26} \033[90m{r['detail']}\033[0m")
            if not r["ok"]:
                print(f"   \033[33m→ {r['fix']}\033[0m")
        print(f"\n {len(results) - len(bad)}/{len(results)} OK" + (f", {len(bad)} need attention" if bad else ", all good"))
    return 1 if any(not r["ok"] for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
