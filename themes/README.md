# Themes

The setup has three layers that should look the same: **Ghostty** (the terminal), **herdr** (sidebar, tabs, borders) and **dash + the Claude status line** (drawn in the terminal's own palette).

dash and the status line use the terminal's ANSI palette, never fixed colours, so they always follow whatever Ghostty theme you pick. Only herdr needs a matching theme block.

## Included

| Theme | Ghostty | herdr |
|---|---|---|
| Everforest Dark Hard (default) | built in: `theme = Everforest Dark Hard` | `everforest-dark-hard/herdr.toml` |

## Switching theme

1. Pick any built-in Ghostty theme: `ghostty +list-themes`, then set `theme = <name>` in `~/.config/ghostty/config`.
2. For herdr, set `[theme] name = "<one of herdr's themes>"`, or copy `everforest-dark-hard/herdr.toml` and change the six hex colours under `[theme.custom]` to match: accent, sidebar background, active row, selection.
3. `herdr server reload-config`. dash and the status line need no change.

## Adding a theme to this repo

Create `themes/<name>/herdr.toml` with the same keys, add a row above, and send a PR with a screenshot.
