# Clock format

## Problem statement

How might we let the user choose what the clock pill shows, without
making them learn `DateFormatter` syntax?

## Recommended direction

Add two keys to `bar-pills.conf`. `clock_format` takes a preset name or
a custom `DateFormatter` pattern. `clock_hours` takes `12`, `24` or
`auto`, and `auto` follows the 12/24-hour setting of macOS. With no keys,
the pill shows `full` with `auto` hours. The clock Settings page gets a
preset picker, a 12/24-hour control, and a "Custom" entry that shows a
text field and a live preview.

Each preset holds its hour as the template symbol `j`. The bar puts `H`
for 24 hours or `h` for 12 hours in its place, then passes the template
to `DateFormatter.dateFormat(fromTemplate:options:locale:)`, which adds
the AM/PM mark where the locale puts it.

| Preset  | 24 hours           | 12 hours             |
|---------|--------------------|----------------------|
| `full`  | Mon 19 Oct  16:21  | Mon 19 Oct  4:21 PM  |
| `short` | 16:21              | 4:21 PM              |
| `date`  | Mon 19 Oct         | Mon 19 Oct           |
| `iso`   | 2026-10-19 16:21   | 2026-10-19 4:21 PM   |

A custom pattern sets its own hours, so the 12/24-hour control does not
apply to it, and Settings disables the control while "Custom" is on.

Seconds are available only through a custom pattern. If the pattern
contains `s`, the clock ticks every second. If not, it keeps the
current tick on the minute boundary, so a user who does not show
seconds pays nothing extra.

A tick redraws only the clock pill, not the whole bar. Today a clock
update takes 7 to 9 ms, because it redraws the whole bar on every
display. At one tick a second that is about 0.8% of one core.
`pill-redraw.md` covers the fix for every pill.

## Key assumptions to validate

- [ ] A one-second timer with `tolerance` keeps Energy Impact low on
      battery. Compare Activity Monitor with seconds on and off.
- [ ] Users who want a custom pattern can write one with the live
      preview. If not, add more presets.

## MVP scope

In:

- `clock_format` with the four presets and a custom pattern.
- `clock_hours` with `12`, `24` and `auto` for the presets.
- A preset picker, a 12/24-hour control, and a custom field with a
  live preview on the clock Settings page, in `builtinPills`.
- A cached `DateFormatter`, and a one-second timer with `tolerance`
  only while the pattern contains seconds.
- The clock redraws only its own pill. This depends on the per-pill
  redraw in `pill-redraw.md`.
- No ticks while the displays sleep or the screen is locked.
- A cap on the label length, so a long pattern cannot push out the
  other pills.
- A test for the preset lookup and the seconds check, as plain
  functions.

Out: everything in the next section.

## Not doing (and why)

- A two-line layout. The bar has no room for two readable lines.
- A second time zone. Not needed.
- A flashing colon. It costs the same as seconds and shows less.
- A seconds preset. Seconds cost wakeups, so they stay an explicit
  choice in a custom pattern.
- The date on hover. A click on the pill opens the popup, so hover is
  a poor place to hide information.

## Open questions

- How does the event ticker sit next to a long custom label? Truncate
  the label, or the ticker?
- Does `reloadConfig()` need to restart the clock timer when the
  pattern gains or loses seconds?
