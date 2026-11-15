---
description: Send a message to another Claude agent running in herdr
argument-hint: "<agent: space, tab or label> <message>"
model: haiku
allowed-tools: Bash(herdr pane list:*), Bash(herdr workspace list:*), Bash(herdr tab list:*), Bash(herdr agent prompt:*), Bash(herdr pane read:*)
---

Request: $ARGUMENTS

The first word or quoted phrase names the target agent; the rest is the message.

1. Find Claude agents: `herdr pane list` (keep panes with `"agent": "claude"`), plus `herdr workspace list` and `herdr tab list` for space and tab names. Match the target, case-insensitive, against the space name, tab label, pane `label` and `terminal_title_stripped`. Skip your own pane ($HERDR_PANE_ID).
2. Exactly one match: continue. None or several: list the candidates (space · label) and stop; don't guess.
3. If the target's `agent_status` is `working`, still send it: Claude queues the message. If its input box already has typed text (check the line starting with `❯` in `herdr pane read <pane>`), stop and tell me, because sending would merge into that draft.
4. Send it: `herdr agent prompt <pane_id> "<message>"`. Put the message in the agent's own words as a request; add "(from <my space · my label>)" at the end so it knows who asked.
5. Reply with one line: "Sent to <space · label>."
