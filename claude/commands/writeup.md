---
description: Write up the current work as a short Slack-ready message for a person or team
argument-hint: "<who it's for, e.g. the platform team>"
model: sonnet
---

Write up the work from this conversation for: $ARGUMENTS

- At most 120 words, Slack mrkdwn (`*bold*`, `-` bullets, links as `<url|text>`).
- Order: one line on what changed and why it matters to them; then status (done / in review / blocked); then anything you need from them, as a direct ask with a name if there is one.
- Link the PR, ticket or doc when one exists. Use exact numbers and names from the conversation; never invent results, dates or commitments. If something is unverified, say so plainly.
- Plain words, no filler, no emoji, no "Hope this helps".

Output only the message. Don't post it. If I then say "post" or "send", save it as a Slack draft with the `slack-reply` skill or the Slack tools, and confirm the channel or person with me first.
