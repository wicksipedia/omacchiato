# Pill redraw

## Problem statement

How might we make a pill that changes redraw only itself, so that a
pill with a fast tick does not cost a redraw of the whole bar?

## What happens today

- `set()` in `Plugins.swift` calls `repaint()` for every pill change.
  Thirteen other places call `repaint()` too.
- `repaint()` calls `display()` on every surface. `display()` draws at
  once, so three pills that change in one run loop pass give three full
  redraws.
- `BarView.draw(_:)` builds the whole bar each time: the Apple pill, the
  workspace chips, the app pill, the media pill and every right pill. It
  measures the text, gets the icons and makes the hit rects again.
- A clock update takes 7 to 9 ms in `/tmp/omacchiato-bar.log`. Most of
  that is work for pills that did not change.
- `Ticker` and `Marquee` are already layer-backed subviews that animate
  without a redraw of the bar. They show that the bar can hold parts
  that update on their own.

## Recommended direction

Keep one `draw(_:)`, and make it draw only what is dirty.

1. `repaint()` sets `needsDisplay` and does not call `display()`. AppKit
   then draws once for each run loop pass, however many pills changed.
2. `draw(_:)` keeps the layout of the last full pass: each pill's rect
   and hit rect. A partial pass reuses that layout and draws only the
   pills that intersect `dirtyRect`.
3. `set()` measures the new pill. If its width is the same, it marks
   only the pill's rect dirty. If the width changed, it marks the span
   from the left edge of the right cluster to the pill's right edge,
   because the right cluster lays out from the screen edge inwards and
   only the pills to its left move.
4. A change that moves pills elsewhere, such as a config reload, a
   display change or a workspace change, still calls `repaint()` and
   gets a full pass.

When this lands, add a rule to CONTRIBUTING.md: a pill change redraws
only that pill's rect, and `repaint()` is only for a change that moves
pills.

## Alternative: one view for each pill

Each right pill becomes its own layer-backed `NSView`, as `Ticker` is.
AppKit then tracks the dirty areas, and a pill's draw code cannot touch
another pill. This gives the cleanest result, but it is a large
refactor: the layout, the hit areas and the alpha hit test all move into
the subviews. Choose it only if the dirty-rect approach turns out to be
too fragile.

## Key assumptions to validate

- [ ] A partial pass for the clock costs well under 1 ms. Time it with
      `tlog`.
- [ ] A clip to the pill's rect redraws the background under it with no
      seams at the pill's rounded edges. Check with `screencapture`.
- [ ] Clicks still land after a partial pass, because the hit rects of
      the full pass stay valid. Check by clicking pills after a clock
      tick.
- [ ] The ticker slides in and out the same as before.

## MVP scope

In:

- `repaint()` without `display()`.
- A layout cache and a `draw(_:)` that skips pills outside `dirtyRect`.
- A `set()` that marks only the dirty span.
- `tlog` timings for partial and full passes.
- A test for the dirty-span calculation, as a function that takes
  rects and widths.

Out:

- The left cluster (chips, app pill, media). A workspace change moves
  most of it anyway.
- One view for each pill. See the alternative above.

## Open questions

- Does a pill's background colour change (`fillPill`) need anything
  more than its rect marked dirty?
- Does the dirty span need to include half of the gap on each side, to
  cover the clickable hit area?
