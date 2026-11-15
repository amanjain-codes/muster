# Improving Muster

## Layout of the code

| File | Change it to… |
|---|---|
| `plugin/dash.py` | add or change a section, key, or action |
| `plugin/dashconf.py` | add a setting (and add it to `config/config.example.toml` + `.env.example`) |
| `plugin/fetch.py` | fetch more from claude.ai connectors (keep tools read-only) |
| `plugin/doctor.py` | add a health check |
| `plugin/ci_watch.py`, `claude/hooks/ci-autopilot.sh` | change CI autopilot behaviour |
| `claude/hooks/*.sh` | change a gate |
| `claude/commands/*.md` | add or change a slash command |
| `claude/statusline.sh` | change the status line |

## Develop against your own install

```bash
MUSTER_DIR=~/.local/share/muster/dash
cp plugin/* "$MUSTER_DIR"/          # then ⌥d twice to reload dash
tests/run_all.sh                  # before every commit
muster doctor                       # after changing hooks, keys or config
```

## Add a dash section

1. Write a loader `load_<thing>() -> list[dict]` near the others in `dash.py`. It runs in a worker thread; it may be slow, must not touch the UI, and should raise on failure (the section then shows `error: …`, the rest of dash keeps working).
2. Add `"<thing>"` to `refresh_all()` and a `set_interval(...)` in `on_mount()`; store the result on `self` in `_fetch()`.
3. In `render_view()`: `section("NAME", "note")`, then `row(dict(sec="NAME", kind="<thing>", url=...), Text(...), "key hints")` per item. Add `"NAME"` to `SECTIONS` for Tab order.
4. Actions: a `Binding`, an `action_*` that checks `self.current()["kind"]`, and for anything that writes, set `self.pending = dict(kind=..., question=...)` and handle it in `action_confirm`.

## Add a health check

In `doctor.py`, call `check(name, ok, detail, fix)` inside one of the groups (or a new function called from `main()`). The `fix` must be a command or exact instruction. Slow checks go behind `if not quick`.

## Conventions (please keep)

- **Colours**: terminal palette names only (`green`, `cyan`, `bright_black`…), never hex.
- **One line per item**, short text, numbers first (e.g. `45% ▰▰▰▱▱▱  label`).
- **Every write asks `y/n`** and refuses when unsafe (agent working, draft in its input box, uncommitted changes).
- **Never zoom panes to move focus**; use `herdr agent focus`, `plugin pane focus` or direction focus.
- **Background Claude calls use the smallest model that works** and only the tools they need (`--allowedTools`); prompt on stdin (`--allowedTools` takes several values and swallows a trailing prompt).
- **zsh scripts**: don't name variables `path` or `status` (special in zsh). **bash scripts**: macOS ships bash 3.2 (no `mapfile`, careful with `set -u` and empty arrays). **Python**: must run on 3.9 (`from __future__ import annotations`; no `tomllib` without the fallback).
- **No personal or company values in code**: they go in `config.toml` / `.env`.

## Ideas not built yet

- Prompt to share a PR when CI autopilot sees it go green.
- Per-repo `.claude/verify.sh` templates for common stacks.
- Quick-capture TODO popup from anywhere; a morning view (yesterday's open items + today).
- Linux support (replace `lsappinfo`, `osascript`, macOS paths).
