# Herdr hotkey

## Problem Statement

How might we open the herdr session in Ghostty with one key, and focus
the same window on each press after that, instead of opening a new one?

## Recommended Direction

Add `Super+A` (A for agents) through a Karabiner rule in
`bin/omacchiato-karabiner-omniwm`. The rule runs a new script,
`bin/omacchiato-herdr`. If the window that the script opened last is
still in `omacchiato-omni query windows`, the script focuses it with
`omacchiato-omni focus-window`. If not, it opens a new Ghostty window that
runs `herdr`, and writes the id of that window to
`~/.local/state/omacchiato/herdr-window`.

The window is an ordinary tiled window, on the workspace where it opened.
A press focuses it and goes to its workspace. A second press does nothing.
`Super+Return` still opens a plain shell.

The id comes from the window list: the script compares the Ghostty window
ids before and after the launch, with the `wait-window` wait that
`omacchiato-spawn` uses.

## Key Assumptions to Validate

- [ ] `open -na Ghostty --args --command=herdr` opens one window that runs
      herdr, and the window closes when herdr exits. Test: run it by hand.
- [ ] A Ghostty window keeps its `windowId` when OmniWM moves it to another
      workspace or display. Test: move it, then query again.
- [ ] `omacchiato-omni focus-window` goes to a window on an inactive
      workspace. Test: focus it from another workspace.

## MVP Scope

In: the script, the Karabiner rule, a cheatsheet entry (from the rule
description), and a manifest entry in `install.sh`.
Out: everything in the list below.

## Not Doing (and Why)

- Toggle or hide on a second press: focus only is enough.
- Summon to the current workspace: the window stays where it opened.
- A general focus-or-launch command for any app: one user, one app.
  Generalize when a second app needs it.
- Find a herdr window that the user opened by hand: herdr attaches to the
  same session, so a second window does no harm.
- Put herdr in the quake terminal: the herdr window is a tiled window.

## Open Questions

- Does the window open with the omarchy split side, as Super+Return does?
  If so, run the launch through `omacchiato-spawn`, which then needs to take
  arguments.
