#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["textual>=1.0"]
# ///
"""Drives dash's keys and rendering with sample data: REVIEWS, Slack mentions, ticket briefs.
No fetching: nothing calls GitHub, Slack, herdr or Claude. Run by test_dash_ui.sh in a scratch HOME."""

import asyncio
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "plugin"))
import dash  # noqa: E402
from rich.text import Text  # noqa: E402

fail = 0


def expect(name, got, want):
    global fail
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f" (want {want!r}, got {got!r})"))
    fail |= not ok


class Quiet(dash.Dash):
    def on_mount(self):  # no timers, no fetches
        self.render_view()

    def fetch(self, what):
        pass

    def layout_panels(self, t, sections):
        out = super().layout_panels(t, sections)
        self.screen_text = out.plain  # what dash would draw, as plain text
        return out


def pr(n, **kw):
    base = dict(kind="review", number=n, title=f"change {n}", url=f"https://github.com/acme/svc/pull/{n}", draft=False,
                author="dev1", repo="acme/svc", method="SQUASH", asked=time.time() - 2 * 86400, head="abc1234" + "0" * 33,
                ok=3, fail=0, total=3, first_fail=None)
    return {**base, **kw}


async def main():
    now = time.time()
    notes = Path(os.environ["HOME"]) / ".cache" / "muster" / "notes"
    notes.mkdir(parents=True)
    dash.brief_path("ABC-1").write_text("# ABC-1: brief\n")
    dash.review_path("acme/svc", 7).write_text("# acme/svc#7: review\n\n_model · $0.08 · head abc1234" + "0" * 33 + "_\n")
    dash.review_path("acme/svc", 8).write_text("# acme/svc#8: review\n\n_model · $0.08 · head def5678" + "0" * 33 + "_\n")

    app = Quiet()
    async with app.run_test(size=(130, 80)) as pilot:
        app.updated = {k: now for k in ("prs", "reviews", "agents", "spend", "artifacts")}
        app.reviews = [pr(7), pr(8, draft=True), pr(9, fail=1, ok=2, first_fail="e2e")]
        app.comms = {"updated": now, "today": [], "errors": [],
                     "jira": [{"key": "ABC-1", "title": "fix export", "status": "To Do", "url": "https://x.atlassian.net/browse/ABC-1"},
                              {"key": "ABC-2", "title": "add retry", "status": "To Do", "url": "https://x.atlassian.net/browse/ABC-2"}],
                     "slack": [{"who": "Sam", "where": "#eng", "text": "can you look at the deploy?", "ts": now - 600,
                                "url": "https://acme.slack.com/archives/C1/p1"}]}
        app.render_view()
        s = app.screen_text
        expect("REVIEWS section shows", "REVIEWS" in s and "3 waiting on you · svc" in s, True)
        expect("review row: repo#number and author", "svc#7 change 7 @dev1" in s, True)
        expect("review waiting >1 day is shown", " 2d" in s, True)
        expect("ready review marked", "✎ review" in s, True)
        expect("Slack mention listed", "Sam" in s and "can you look at the deploy?" in s, True)
        expect("brief badge on the ticket that has one", s.count("✎ brief"), 1)

        def select(kind, pick=lambda it: True):
            app.sel = next(i for i, it in enumerate(app.items) if it["kind"] == kind and pick(it))
            app.render_view()

        select("review", lambda it: it["p"]["number"] == 7)
        expect("review hints: the three actions", app.items[app.sel]["hints"], "v read review · A approve + merge · o open")
        await pilot.press("A")
        expect("A asks before approving", (app.pending or {}).get("kind"), "approve_merge")
        expect("question names PR and method", (app.pending or {}).get("question"), "Approve svc#7 and merge when green (squash)?")
        await pilot.press("n")
        expect("n cancels", app.pending, None)

        select("review", lambda it: it["p"]["number"] == 8)
        expect("review of an older commit is flagged", app.review_state(app.items[app.sel]["p"]), "outdated")
        expect("  ...and offers a fresh one", app.items[app.sel]["hints"].startswith("v review again"), True)
        await pilot.press("A")
        expect("draft PR refused", (app.pending, app.flash), (None, "draft PR; not approving it"))
        select("review", lambda it: it["p"]["number"] == 9)
        await pilot.press("A")
        expect("red CI refused", app.pending is None and app.flash.startswith("CI is red"), True)

        select("review", lambda it: it["p"]["number"] == 7)
        await pilot.press("v")
        expect("v opens the review", app.viewing, dash.review_path("acme/svc", 7))
        await pilot.press("escape")
        expect("Esc goes back", app.viewing, None)

        select("jira", lambda it: it["j"]["key"] == "ABC-1")
        await pilot.press("v")
        expect("v on a ticket opens its brief", app.viewing, dash.brief_path("ABC-1"))
        await pilot.press("v")
        select("jira", lambda it: it["j"]["key"] == "ABC-2")
        await pilot.press("v")
        expect("no brief yet: says how to get one", (app.viewing, app.flash), (None, "no brief yet · b writes one"))

        select("slack_msg")
        expect("Slack mention hint", app.items[app.sel]["hints"], "o open the thread")

        t0 = 1_000_000.0
        aged = [pr(1, asked=t0 - 50 * 3600), pr(2, asked=t0 - 47 * 3600), pr(3, asked=t0 - 3600)]
        expect("48h limit drops older requests, oldest first", [p["number"] for p in dash.recent_reviews(aged, 48 * 3600, t0)], [2, 3])
        expect("no limit keeps all", len(dash.recent_reviews(aged, 0, t0)), 3)

        app.notes_started[str(dash.brief_path("ABC-2"))] = time.time()
        expect("a running brief shows as writing", app.note_state(dash.brief_path("ABC-2")), "writing")
        dash.brief_path("ABC-2").write_text(dash.FAILED + " boom\n")
        expect("a failed brief shows as failed", app.note_state(dash.brief_path("ABC-2")), "failed")


asyncio.run(main())
sys.exit(fail)
