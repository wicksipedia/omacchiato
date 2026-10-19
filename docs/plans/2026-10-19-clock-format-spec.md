# Spec: Clock format

Source idea: `docs/ideas/clock-format.md`.

## Objective

The clock pill shows `EEE dd MMM  HH:mm`, and nothing can change it.
The user wants to pick the format and the 12/24-hour mode, and to show
seconds if they choose to.

Users: whoever runs Omacchiato and opens the clock page in Settings, or
edits `bar-pills.conf` by hand.

User stories:

- I pick a preset on the clock page, and the pill changes at once.
- I pick 12 or 24 hours, or let the pill follow macOS.
- I type my own pattern, see a live preview, and the pill uses it.
- I put seconds in my own pattern, and the pill ticks every second.
  Without seconds, the pill costs no more than it does today.

## Settings keys

Two new keys in `bar-pills.conf`. The existing `clock = hide | icon`
key does not change.

| Key            | Values                                   | Default |
|----------------|------------------------------------------|---------|
| `clock_format` | `full`, `short`, `date`, `iso`, or a pattern | `full` |
| `clock_hours`  | `auto`, `12`, `24`                       | `auto`  |

A value that is not a preset name is a `DateFormatter` pattern. An empty
value means `full`.

Each preset has a fixed pattern for each hour mode:

| Preset  | 24 hours             | 12 hours               |
|---------|----------------------|------------------------|
| `full`  | `EEE dd MMM  HH:mm`  | `EEE dd MMM  h:mm a`   |
| `short` | `HH:mm`              | `h:mm a`               |
| `date`  | `EEE dd MMM`         | `EEE dd MMM`           |
| `iso`   | `yyyy-MM-dd HH:mm`   | `yyyy-MM-dd h:mm a`    |

The presets do not go through
`DateFormatter.dateFormat(fromTemplate:options:locale:)`. A test on this
Mac showed that a template puts the fields in the locale's order, so
`iso` became `dd/MM/yyyy, h:mm a` in `en_AU`. This changes the plan in
the source idea.

With `auto`, the bar reads the macOS hour setting from
`DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent)`.
If the result contains `a`, the hours are 12. Otherwise they are 24.

`clock_hours` has no effect on a custom pattern, because the pattern
sets its own hours.

## Behaviour

- The label is capped at 32 characters, the same cap as plugin labels.
- If the pattern holds the seconds field `s` outside a quoted literal,
  the clock ticks on each second boundary. If not, it ticks on each
  minute boundary, as it does now.
- The one-second timer has a 0.1 s tolerance, so macOS can group the
  wakeups.
- While the displays sleep, the clock does not tick. On wake, it
  updates and starts its timer again.
- When the config reloads, the clock updates at once. If the pattern
  gains or loses seconds, the timer starts again at the new rate.
- The `DateFormatter` is cached and rebuilt only when the pattern
  changes.
- The event ticker does not change.

Known cost: until `docs/ideas/pill-redraw.md` lands, each tick redraws
the whole bar, 7 to 9 ms. With seconds, that is about 0.8% of one core.
This is accepted for now, and only users who choose seconds pay it.

## Settings page

The clock page gets an "Options" section:

- A "Format" menu picker: Full, Short, Date, ISO, Custom. Each title
  shows an example from the current time.
- A "Hours" segmented control: Auto, 12, 24. It is disabled while
  Custom is selected.
- With Custom selected, a text field for the pattern and a preview
  under it. The preview shows the saved pattern and ticks each second.
  The field writes the key on Return or when it loses focus,
  not on each key press, because each write reloads the config.
- A short help line under the field: `HH` hours, `mm` minutes, `ss`
  seconds, `EEE` day, `dd` date, `MMM` month.

## Tech stack

Swift 6 tools, Swift 5 language mode, macOS 26. AppKit for the bar,
SwiftUI for Settings. Swift Testing for the tests. No new dependencies.

## Commands

```sh
# All checks that need no screen (bash -n, Python tests, swift test)
bin/omacchiato-test

# The clock tests only
swift test --filter ClockFormatTests

# Rebuild and restart the bar only
swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight -framework DisplayServices \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker helper/bar-info.plist \
  -o "$TMPDIR/omacchiato-bar" helper/bar/*.swift helper/ui/Sources/*/*.swift
cp "$TMPDIR/omacchiato-bar" omacchiato-bar.app/Contents/MacOS/omacchiato-bar
codesign -f -s "Apple Development" --identifier com.omacchiato.bar omacchiato-bar.app
launchctl kickstart -k "gui/$(id -u)/com.omacchiato.bar"

# Look at the pill
screencapture -x -R0,0,3000,40 "$TMPDIR/bar.png"

# Open the clock popup without a click
omacchiato-popup clock
```

## Project structure

| File | Change |
|------|--------|
| `helper/ui/Sources/BarPills/ClockFormat.swift` | New. Plain functions: preset lookup, hour mode, seconds check, label cap. Settings and the bar both use them. |
| `helper/ui/Package.swift` | `SettingsPanel` depends on `BarPills`, for the live preview. |
| `helper/bar/Providers.swift` | `updateClock()` uses the cached formatter and the pattern from `ClockFormat`. |
| `helper/bar/main.swift` | `scheduleClock()` picks the minute or second boundary, and restarts on a reload or a wake. |
| `helper/bar/Config.swift` | `reloadConfig()` updates the clock and restarts its timer if needed. |
| `helper/ui/Sources/SettingsPanel/SettingsReport.swift` | `Pill` gets a `clock` field with the two values. |
| `helper/ui/Sources/SettingsPanel/SettingsView.swift` | The Options section for the clock. |
| `helper/bar/Settings.swift` | `settingsReport()` fills the `clock` field. |
| `tests/bar/ClockFormatTests.swift` | New. |
| `docs/bar.md`, `CLAUDE.md`, `AGENTS.md` | The two keys, in the `bar-pills.conf` notes. |

## Code style

Match the code around it: free functions that take plain values, short
names, and comments only for a non-obvious why. For example:

```swift
public let clockPresets: [(key: String, h24: String, h12: String)] = [
    ("full", "EEE dd MMM  HH:mm", "EEE dd MMM  h:mm a"),
    ("short", "HH:mm", "h:mm a"),
    ("date", "EEE dd MMM", "EEE dd MMM"),
    ("iso", "yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a"),
]

public func clockPattern(format: String?, hours: String?, systemIs24: Bool) -> String {
    let format = format.flatMap { $0.isEmpty ? nil : $0 } ?? "full"
    guard let preset = clockPresets.first(where: { $0.key == format }) else { return format }
    let is24 = hours == "24" || (hours != "12" && systemIs24)
    return is24 ? preset.h24 : preset.h12
}
```

Comments follow ASD-STE100 and the comment rules in CLAUDE.md.

## Testing strategy

Swift Testing, in `tests/bar/ClockFormatTests.swift`, on the plain
functions only:

- Each preset gives its 24-hour and 12-hour pattern.
- `auto` follows the system flag. `12` and `24` override it.
- A custom pattern comes back unchanged, whatever `clock_hours` says.
- An empty or missing format gives `full`.
- The seconds check finds `ss` and `s`, and ignores `'s'` in a quoted
  literal and `''` escapes.
- The label cap cuts at 32 characters.
- The system hour check gives 12 for `en_US` and 24 for `de_DE`.

The timer, the redraw and the Settings page are checked by hand on the
live bar, with the user's approval first.

## Boundaries

Always:

- Run `bin/omacchiato-test` before each commit.
- Deploy to the live bar and get the user's confirmation before a
  commit.
- Read `clock_format` and `clock_hours` at the moment of use, so a
  reload applies them.

Ask first:

- A test that opens popups, clicks or moves the pointer.
- A change to the redraw path (`set()`, `repaint()`, `BarView.draw`).
- A new dependency.

Never:

- Post an Escape key event.
- Run `install.sh` to test this change.
- Tick every second while the pattern has no seconds.

## Success criteria

- [ ] With no new keys, the pill shows `full` in the macOS hour mode.
      This Mac has 24-hour time off, so it shows `Mon 19 Oct  4:21 PM`.
- [ ] Each preset and hour mode shows its pattern from the table.
- [ ] A custom pattern shows in the pill within a second of the save.
- [ ] With `HH:mm:ss`, the seconds change once a second.
- [ ] Without seconds, `/tmp/omacchiato-bar.log` shows one clock item
      a minute, as today.
- [ ] A switch between a pattern with seconds and one without changes
      the tick rate without a bar restart.
- [ ] A 60-character custom pattern gives a label of 32 characters or
      fewer.
- [ ] On the clock page, the Hours control is disabled while Custom is
      selected, and the preview matches the pill.
- [ ] `bin/omacchiato-test` passes.

## Decisions

- The default is `auto`, so a user who has 24-hour time off in System
  Settings sees 12 hours after this change. The user chose this over a
  default of `24`, which would keep the old look.
