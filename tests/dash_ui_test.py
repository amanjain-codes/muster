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
        expect("REVIEWS section names its sources", "REVIEWS" in s and "3 waiting on you · the team channel + svc" in s, True)
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
        expect("question names owner/repo, PR and method", (app.pending or {}).get("question"), "Approve acme/svc#7 and merge when green (squash)?")
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

        def node(n, **kw):
            base = dict(number=n, title=f"pr {n}", url=f"https://github.com/acme/svc/pull/{n}", isDraft=False, headRefOid="f" * 40,
                        createdAt="2026-01-01T00:00:00Z", state="OPEN", viewerDidAuthor=False, viewerLatestReview=None,
                        author={"login": "dev1"}, repository={"nameWithOwner": "acme/svc", "viewerDefaultMergeMethod": "SQUASH"},
                        timelineItems={"nodes": []}, commits={"nodes": []})
            return {**base, **kw}
        t0 = 1_800_000_000.0
        rows = dash.build_reviews(
            [node(1, timelineItems={"nodes": [{"createdAt": "2027-01-15T07:00:00Z"}]})],
            [(node(1), t0 - 3600), (node(2), t0 - 7200), (node(3, state="MERGED"), t0), (node(4, viewerDidAuthor=True), t0),
             (node(5, viewerLatestReview={"state": "APPROVED"}), t0), (None, t0), (node(6), t0 - 50 * 3600)],
            48 * 3600, t0)
        expect("team + direct: merged, mine, approved, missing and >48h dropped", [r["number"] for r in rows], [2, 1])
        expect("a PR in both lists is one row with both marks", sorted(next(r for r in rows if r["number"] == 1)["src"]), ["team", "you"])
        q, used = dash.team_query([{"url": "https://github.com/acme/svc/pull/7", "ts": 1}, {"url": "https://github.com/evil/x/pull/1", "ts": 1},
                                   {"url": 'https://github.com/acme/a"){x}/pull/1', "ts": 1}])
        expect("team query: only org PR links, parsed parts only", (len(used), 'owner: "acme", name: "svc"' in q, "evil" in q, "{x}" in q),
               (1, True, False, False))

        app.reviews = [dict(pr(21), src={"team"}), dict(pr(22), src={"you"}), dict(pr(23), src={"team", "you"})]
        app.render_view()
        line = {n: next(l for l in app.screen_text.splitlines() if f"svc#{n} " in l) for n in (21, 22, 23)}
        expect("row marks: # team, → you, #→ both", [line[21].lstrip("▸ ")[:2], line[22].lstrip("▸ ")[:2], line[23].lstrip("▸ ")[:2]], ["# ", "→ ", "#→"])

        app.notes_started[str(dash.brief_path("ABC-2"))] = time.time()
        expect("a running brief shows as writing", app.note_state(dash.brief_path("ABC-2")), "writing")
        dash.brief_path("ABC-2").write_text(dash.FAILED + " boom\n")
        expect("a failed brief shows as failed", app.note_state(dash.brief_path("ABC-2")), "failed")

        # --- A: approve only what you reviewed, and never hand the merge to GitHub's auto-merge ---
        dash.review_path("acme/svc", 10).write_text("# acme/svc#10: review\n\n_model · $0.08 · head 9999999" + "0" * 33 + "_\n")
        app.reviews = [pr(10)]
        app.render_view()
        select("review", lambda it: it["p"]["number"] == 10)
        await pilot.press("A")
        expect("outdated review: A refused", (app.pending, app.flash), (None, "the review is for an older commit · v review again first"))

        head = "abc1234" + "0" * 33
        calls: list[list[str]] = []

        def fake_run(cmd, **kw):
            calls.append(cmd)
            out = head + "\n" if cmd[:3] == ["gh", "pr", "view"] else ""
            return dash.subprocess.CompletedProcess(cmd, 0, out, "")

        real_run, dash.subprocess.run = dash.subprocess.run, fake_run
        try:
            await asyncio.to_thread(app.do_approve_merge, pr(7), "squash")
            await pilot.pause()
            approve = next((c for c in calls if c[:2] == ["gh", "api"]), [])
            expect("approve is pinned to the commit dash showed",
                   ("repos/acme/svc/pulls/7/reviews" in approve, f"commit_id={head}" in approve, "event=APPROVE" in approve), (True, True, True))
            merge = next((c for c in calls if c[:3] == ["gh", "pr", "merge"]), [])
            pinned = "--match-head-commit" in merge and merge[merge.index("--match-head-commit") + 1] == head
            expect("green: merges now, pinned to that commit", (pinned, "--squash" in merge), (True, True))
            expect("never uses GitHub auto-merge", any("--auto" in c for c in calls), False)
            expect("green: nothing queued", dash.read_queue(), [])

            calls.clear()
            await asyncio.to_thread(app.do_approve_merge, pr(11, ok=1, total=3, head=head), "squash")
            await pilot.pause()
            expect("CI running: approves, does not merge", ([c[:2] for c in calls if c[:2] == ["gh", "api"]], any(c[:3] == ["gh", "pr", "merge"] for c in calls)),
                   ([["gh", "api"]], False))
            q = dash.read_queue()
            expect("CI running: dash queues the merge for that commit", [(e["repo"], e["number"], e["head"], e["method"]) for e in q],
                   [("acme/svc", 11, head, "squash")])
            expect("queue file is private", oct(dash.MERGE_QUEUE.stat().st_mode & 0o777), "0o600")
            app.render_view()
            expect("REVIEWS header shows the queued merge", "1 to merge when green" in app.screen_text, True)
        finally:
            dash.subprocess.run = real_run

        e = dict(repo="acme/svc", number=11, head=head, method="squash", at=t0)
        n = lambda **kw: {**node(11, headRefOid=head), **kw}  # noqa: E731
        green = {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS", "contexts": {"nodes": [
            {"__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"}]}}}}]}
        red = {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE", "contexts": {"nodes": [
            {"__typename": "CheckRun", "name": "e2e", "status": "COMPLETED", "conclusion": "FAILURE"}]}}}}]}
        running = {"nodes": [{"commit": {"statusCheckRollup": {"state": "PENDING", "contexts": {"nodes": [
            {"__typename": "CheckRun", "name": "build", "status": "IN_PROGRESS", "conclusion": None}]}}}}]}
        step = lambda node_, now=t0 + 60: dash.merge_step(e, node_, now)[0]  # noqa: E731
        expect("queue: green on the same commit merges", step(n(commits=green)), "merge")
        expect("queue: still running waits", step(n(commits=running)), "wait")
        expect("queue: new commits after approval: dropped, not merged", step(n(commits=green, headRefOid="f" * 40)), "drop")
        expect("queue: red CI dropped", step(n(commits=red)), "drop")
        expect("queue: merged or closed elsewhere dropped", step(n(state="MERGED")), "drop")
        expect("queue: PR not readable right now waits", step(None), "wait")
        expect("queue: gives up after 3 days", step(n(commits=running), t0 + 4 * 86400), "drop")
        expect("queue: no checks yet waits", step(n(), t0 + 60), "wait")
        expect("queue: still no checks after 10 min: repo has no CI, merges", step(n(), t0 + 11 * 60), "merge")

        # --- TODAY: every meeting of the day; past ones dimmed, the current one marked ---
        hm = lambda off: time.strftime("%H:%M", time.localtime(now + off))  # noqa: E731
        app.comms = {**app.comms, "today": [
            {"start": hm(-7200), "end": hm(-5400), "title": "done one", "url": None},
            {"start": hm(-600), "end": hm(1200), "title": "in progress", "url": None},
            {"start": hm(3600), "end": hm(5400), "title": "later one", "url": None}]}
        if hm(-7200) < hm(5400):  # skip near midnight, when the times wrap
            app.render_view()
            s = app.screen_text
            row_of = lambda title: next(l for l in s.splitlines() if title in l)  # noqa: E731
            expect("TODAY lists past, current and later meetings", all(x in s for x in ("done one", "in progress", "later one")), True)
            expect("TODAY note counts them", "3 meetings · 2 left" in s, True)
            expect("past meeting marked done", "✓" in row_of("done one"), True)
            expect("current meeting marked now", "now" in row_of("in progress"), True)
            expect("later meeting unmarked", ("✓" in row_of("later one"), "now" in row_of("later one")), (False, False))
        app.comms = {**app.comms, "today": []}
        app.render_view()
        expect("empty day says so", "no meetings today" in app.screen_text, True)

        # --- an agent waiting on you (herdr "blocked": a permission prompt or question) is not idle ---
        def agent(pane, status, active, label):
            return dict(pane=pane, tab="t", ws_id="w", ws=f"ws{pane[1:]}", cwd=f"/code/{pane}", label=label, status=status,
                        pct=40, tokens=None, active=active)
        app.reviews = []
        app.agents = [agent("p1", "idle", now - 600, "idle one"), agent("p2", "working", now, "busy one"),
                      agent("p3", "blocked", now - 2 * 86400, "asks you"), agent("p4", "idle", now - 2 * 86400, "old one")]
        app.render_view()
        s = app.screen_text
        lines = [l for l in s.splitlines() if "ws" in l and ("one" in l or "asks" in l)]
        expect("AGENTS note counts who needs you", "4 · 1 needs you · 1 working · 2 idle · 1 stale (idle >1d)" in s, True)
        expect("header says someone needs you", "1 needs you" in s.splitlines()[0], True)
        expect("blocked agent listed first", "asks you" in lines[0], True)
        expect("blocked row says so", "needs you" in lines[0] and "idle" not in lines[0], True)
        expect("blocked is never stale, however long it waits", next(a for a in app.agents if a["pane"] == "p3")["stale"], False)
        select("agent", lambda it: it["a"]["pane"] == "p3")
        expect("blocked hint points at g", app.items[app.sel]["hints"].startswith("g answer it"), True)
        await pilot.press("x")
        expect("x refused on a blocked agent (would type into its prompt)", app.flash, "ws3 is waiting on you · g to answer it")
        await pilot.press("X")
        expect("X refused on a blocked agent", (app.pending, app.flash), (None, "ws3 is waiting on you · g to answer it"))
        app.say("")
        app.do_cleanup(dict(path="/code/p3", branch="b"))
        expect("clean-up refuses a worktree whose agent is waiting on you", app.flash, "its agent (ws3) is busy, waiting on you or has a draft; not cleaned up")


asyncio.run(main())
sys.exit(fail)
