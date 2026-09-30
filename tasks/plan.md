# Implementation plan: keep awake, lid closed, quit on close

## Overview

Move the last two Vorssaint features into Omacchiato: keep awake, with
the options that are set in Vorssaint now, and quit on close, with the
same exceptions. The design and the Vorssaint settings are in
`docs/plans/2026-09-30-keep-awake-and-quit-on-close-design.md`. Both
decisions there are A: the keep-awake cup always shows, and the Mac can
stay awake with the lid closed.

## Architecture decisions

- **The bar holds the state that must end with it.** The keep-awake
  assertion, the jiggle timer, the lid setting and the window watch all
  live in the bar. If the bar crashes, keep awake ends, and the next
  start resets the lid setting.
- **A state file connects the command to the bar.**
  `omacchiato-keep-awake on|off|toggle|for <minutes>` writes
  `~/.local/state/omacchiato/keep-awake`. The bar watches the file.
  Karabiner, the popup and a right-click all run the same command.
- **The plugin stays the view.** `omacchiato-keep-awake` still prints the
  pill and the panel. It reads the state file, so it can show the cup
  dimmed while off and the time left while on.
- **A plugin can ask for a right-click command.** The plugin JSON gets a
  `right_click` key. This is general, so the stale
  `on_click = omacchiato-keep-awake toggle` line in `bar-plugins.conf`
  can go.
- **Pure functions carry the logic,** as the bar's tests need: the
  keep-awake decision (state, time, battery, power source) and the
  quit decision (windows, bundle ID, exceptions).
- **Settings in `bar-pills.conf`,** as for the volume and mic:
  `keep_awake_display`, `keep_awake_jiggle`, `keep_awake_battery`,
  `keep_awake_hud`, `keep_awake_lid`, `quit_on_close`. Exceptions go in
  `~/.config/omacchiato/quit-on-close.conf`, one bundle ID per line.

## Dependency graph

```
T1 jiggle spike ──────────────────────────────┐
T2 state file + command + pill ─┬─ T3 assertion in bar ─┬─ T4 Super+Esc + HUD
                                │                       ├─ T6 popup controls
                                └─ T5 right-click ──────┤
                                                        ├─ T7 jiggle (needs T1)
                                                        ├─ T8 battery limit
                                                        └─ T9 settings + docs
T10 sudoers rule ─ T11 lid in bar (needs T3)
T12 AX spike ─ T13 quit decision ─ T14 window watch ─ T15 exceptions seed ─ T16 settings page
```

Keep awake (T1–T9) and quit on close (T12–T16) do not depend on each
other. The lid (T10–T11) depends only on T3.

## Task list

### Phase 1: keep awake works from the command line

- [x] T1: Spike: which posted event resets the idle time that Teams reads
- [x] T2: State file, command and always-on pill
- [x] T3: The bar holds the assertion from the state file

### Checkpoint A
- [ ] `bin/omacchiato-test` passes
- [ ] `omacchiato-keep-awake on` makes `pmset -g assertions` list
      "Omacchiato: keep the Mac awake"; `off` removes it
- [ ] `omacchiato-keep-awake for 1` ends by itself after 1 minute
- [ ] The cup shows dimmed while off and in the accent colour while on
- [ ] Review with the user

### Phase 2: every way in, and Vorssaint's options

- [x] T4: Super+Esc and the keep-awake HUD
- [x] T5: Right-click on a plugin pill
- [ ] T6: On/off and time buttons in the keep-awake popup
- [ ] T7: Mouse jiggle, paused while the screen is locked
- [ ] T8: Battery limit
- [ ] T9: Keep Awake settings page and docs

### Checkpoint B
- [ ] `bin/omacchiato-test` passes
- [ ] Super+Esc, a right-click and the popup all turn it on and off
- [ ] Teams stays "Available" after 10 minutes with no input
- [ ] Commit, push, release. The user turns off keep awake in Vorssaint
      (not the lid yet).

### Phase 3: lid closed

- [ ] T10: Sudoers rule in install.sh and uninstall.sh
- [ ] T11: The bar sets `disablesleep` with keep awake

### Checkpoint C
- [ ] The Mac stays awake with the lid closed while keep awake is on,
      and sleeps with it off
- [ ] Killing the bar and starting it again leaves `SleepDisabled 0`
- [ ] Commit, push, release. The user removes Vorssaint's lid setting.

### Phase 4: quit on close

- [ ] T12: Spike: AX windows of an app with windows parked by OmniWM
- [ ] T13: The quit decision as a pure function
- [ ] T14: Watch windows and quit the app
- [ ] T15: Seed the exceptions from Vorssaint
- [ ] T16: Quit on Close settings page and docs

### Checkpoint D
- [ ] `bin/omacchiato-test` passes
- [ ] TextEdit quits when its last window closes; Finder does not; an
      app with unsaved work asks; an app with a window on another
      workspace stays
- [ ] Commit, push, release. The user turns off quit on close in
      Vorssaint, and can then remove Vorssaint.

## Tasks

### T1: Spike: which posted event resets the idle time that Teams reads

**Description:** Find the smallest input that keeps Teams and Slack from
showing "Away". Post a mouse-moved event at the pointer's position from
a scratch program, and read `ioreg -c IOHIDSystem` `HIDIdleTime` and
`CGEventSourceSecondsSinceLastEventType` before and after. If a
zero-distance move does not reset them, try a 1-point move and back.

**Acceptance criteria:**
- [ ] One method is chosen, with the readings that show it resets the
      idle time
- [ ] The pointer does not visibly move

**Verification:**
- [ ] Manual check, with the user's permission: the idle time drops to
      near 0 after the event

**Dependencies:** None. **Files:** scratch only. **Scope:** XS

### T2: State file, command and always-on pill

**Description:** `omacchiato-keep-awake` takes `on`, `off`, `toggle` and
`for <minutes>`, and writes the state file (`on`, or an end time as a
Unix time). With no argument, it prints the pill as now, plus: a dimmed
cup while off, the accent cup while on, the time left for a timed run,
`right_click` set to its own `toggle`, and `on` and `until` in the
panel object. Remove the dead `on_click` line from this Mac's
`bar-plugins.conf`.

**Acceptance criteria:**
- [ ] Each argument writes the right state; an end time in the past
      reads as off
- [ ] The pill shows while off, dimmed
- [ ] The existing holder list still works

**Verification:**
- [ ] `python3 -m unittest tests/test_keep_awake.py`
- [ ] `bin/omacchiato-test`

**Dependencies:** None
**Files:** `bin/omacchiato-keep-awake`, `tests/test_keep_awake.py`
**Scope:** S

### T3: The bar holds the assertion from the state file

**Description:** A new `helper/bar/KeepAwake.swift` watches the state
file, holds `PreventUserIdleSystemSleep` while it reads on, and
releases it when it reads off or the end time passes. A pure function,
`keepAwakeNow(state:now:)`, decides. With `keep_awake_display = on`, it
also holds `PreventUserIdleDisplaySleep`. The bar starts it in
`main.swift`.

**Acceptance criteria:**
- [ ] The assertion follows the file within 1 second
- [ ] A timed run ends at its end time and writes `off`
- [ ] Quitting the bar releases the assertion

**Verification:**
- [ ] `swift test` with a new `KeepAwakeTests`
- [ ] Manual: Checkpoint A

**Dependencies:** T2
**Files:** `helper/bar/KeepAwake.swift`, `helper/bar/main.swift`,
`tests/bar/KeepAwakeTests.swift`
**Scope:** M

### T4: Super+Esc and the keep-awake HUD

**Description:** A Karabiner rule runs `omacchiato-keep-awake toggle` on
Super+Esc. The bar shows a glass HUD, "Keeping Awake" (with the end
time for a timed run) or "Sleep Allowed", in the shared HUD window when
the state changes. `keep_awake_hud = off` turns it off.

**Acceptance criteria:**
- [ ] Super+Esc turns keep awake on and off, and the cheatsheet lists it
- [ ] The HUD shows on each change, from any source
- [ ] Xcode previews show both HUD states

**Verification:**
- [ ] `swift build`, `bin/omacchiato-test`
- [ ] Manual: press Super+Esc twice

**Dependencies:** T3
**Files:** `bin/omacchiato-karabiner-omniwm`,
`helper/ui/Sources/KeepAwakePanel/KeepAwakeOSD.swift`,
`helper/ui/Sources/KeepAwakePanel/KeepAwakePreviews.swift`,
`helper/bar/KeepAwake.swift`
**Scope:** M

### T5: Right-click on a plugin pill

**Description:** `BarView` gets `rightMouseDown`. On a plugin pill whose
last JSON had `right_click`, the bar runs that command through
`runPluginCommand`. Other pills ignore a right-click, as now.

**Acceptance criteria:**
- [ ] A right-click on the cup turns keep awake on and off
- [ ] A right-click on other pills does nothing
- [ ] `right_click` is listed with the other plugin keys in CLAUDE.md

**Verification:**
- [ ] `swift build`, `bin/omacchiato-test`
- [ ] Manual: right-click the cup twice

**Dependencies:** T2
**Files:** `helper/bar/BarView.swift`, `helper/bar/Plugins.swift`,
`CLAUDE.md`
**Scope:** S

### T6: On/off and time buttons in the keep-awake popup

**Description:** `KeepAwakeReport` gets `on` and `until`. The panel gets
a toggle and buttons for 30 minutes, 1 hour, 2 hours and "Until turned
off", drawn by hand because the popup is never key. They run the
command through `runPluginCommand`. The holder list stays, and names the
bar's own assertion "Omacchiato".

**Acceptance criteria:**
- [ ] Each button sets the state, and the panel shows the time left
- [ ] Previews show off, on, and a timed run

**Verification:**
- [ ] `swift test` (report parsing), `bin/omacchiato-test`
- [ ] Manual: each button

**Dependencies:** T2, T3
**Files:** `helper/ui/Sources/KeepAwakePanel/*.swift`,
`helper/bar/Popups.swift`
**Scope:** M

### T7: Mouse jiggle, paused while the screen is locked

**Description:** While keep awake is on, the bar posts the event chosen
in T1 every `keep_awake_jiggle` minutes (default 1, `off` turns it
off). It posts nothing while `screenLocked` is true.

**Acceptance criteria:**
- [ ] `pmset -g assertions` shows the `UserIsActive` entry each interval
- [ ] No events while locked or while keep awake is off

**Verification:**
- [ ] Manual: Teams check at Checkpoint B

**Dependencies:** T1, T3
**Files:** `helper/bar/KeepAwake.swift`
**Scope:** S

### T8: Battery limit

**Description:** On battery, at or below `keep_awake_battery` percent
(default 20), the bar writes `off` and shows the HUD with "Battery low".
`keepAwakeNow` takes the battery level and power source, so the tests
cover it.

**Acceptance criteria:**
- [ ] Turns off at the limit on battery; stays on while charging
- [ ] `keep_awake_battery = off` turns the limit off

**Verification:**
- [ ] `swift test` cases for the limit

**Dependencies:** T3, T4
**Files:** `helper/bar/KeepAwake.swift`, `tests/bar/KeepAwakeTests.swift`
**Scope:** S

### T9: Keep Awake settings page and docs

**Description:** The Keep Awake page in Settings gets: display sleep,
jiggle interval, battery limit and HUD. README and CLAUDE.md describe
the command, the state file, the keys and Super+Esc.

**Acceptance criteria:**
- [ ] Each control writes its key, and the bar reads it at the moment
      of use
- [ ] The Settings preview shows the page

**Verification:**
- [ ] `swift build`, `bin/omacchiato-test`
- [ ] Manual: change each control and check its effect

**Dependencies:** T4, T7, T8
**Files:** `helper/bar/Settings.swift`,
`helper/ui/Sources/SettingsPanel/SettingsPreviews.swift`, `README.md`,
`CLAUDE.md`
**Scope:** M

### T10: Sudoers rule in install.sh and uninstall.sh

**Description:** `install.sh` writes
`/etc/sudoers.d/omacchiato-keep-awake`, which lets the user run only
`/usr/bin/pmset -a disablesleep 0` and `... 1` with no password. It
checks the file with `visudo -cf` before it moves it into place, asks
for the admin password once, and adds the file to the manifest.
`uninstall.sh` removes it and runs `pmset -a disablesleep 0`.

**Acceptance criteria:**
- [ ] `sudo -n /usr/bin/pmset -a disablesleep 0` runs with no prompt
- [ ] No other command runs with no password
- [ ] A second `install.sh` run asks for nothing

**Verification:**
- [ ] `bash -n` through `bin/omacchiato-test`
- [ ] Manual: the user runs `install.sh`, then `sudo -n -l`

**Dependencies:** None
**Files:** `install.sh`, `uninstall.sh`
**Scope:** S

### T11: The bar sets `disablesleep` with keep awake

**Description:** With `keep_awake_lid = on` (on by default), the bar
runs `sudo -n pmset -a disablesleep 1` when keep awake starts, and `0`
when it ends and when the bar starts. If `sudo -n` fails, the bar logs
it and keeps the assertion. The Settings page gets a lid switch.

**Acceptance criteria:**
- [ ] `pmset -g` shows `SleepDisabled 1` only while keep awake is on
- [ ] Bar restart resets it to 0

**Verification:**
- [ ] Manual: Checkpoint C

**Dependencies:** T3, T10
**Files:** `helper/bar/KeepAwake.swift`, `helper/bar/Settings.swift`
**Scope:** S

### T12: Spike: AX windows of an app with windows parked by OmniWM

**Description:** With a Finder window on another workspace, read
`kAXWindowsAttribute` and each window's subrole and minimized state
from a scratch program. Also check what a sheet, a settings window and
a tabbed window report.

**Acceptance criteria:**
- [ ] Parked windows are in the list, or the plan changes to count them
      another way
- [ ] The subroles to count are known

**Verification:**
- [ ] The readings are noted in the design doc

**Dependencies:** None. **Files:** scratch, design doc. **Scope:** XS

### T13: The quit decision as a pure function

**Description:** `shouldQuit(windows:bundleID:exceptions:everShowedWindow:)`
returns quit or keep, from T12's rules: count standard windows,
minimized ones too; never quit an exception, an app that never showed a
window, Omacchiato's own apps or OmniWM.

**Acceptance criteria:**
- [ ] Tests cover each rule

**Verification:**
- [ ] `swift test` with a new `QuitOnCloseTests`

**Dependencies:** T12
**Files:** `helper/bar/QuitOnClose.swift`, `tests/bar/QuitOnCloseTests.swift`
**Scope:** S

### T14: Watch windows and quit the app

**Description:** An `AXObserver` per `.regular` app, for window created
and destroyed. After a window closes, wait 1 second, read the windows,
ask `shouldQuit`, and call `terminate()`. Launch and quit notifications
add and remove apps. The exceptions come from `quit-on-close.conf`,
which the config watcher reloads. `quit_on_close = off` stops it.

**Acceptance criteria:**
- [ ] The Checkpoint D cases pass
- [ ] Turning it off stops all quits at once

**Verification:**
- [ ] Manual: Checkpoint D
- [ ] `/tmp/omacchiato-bar.log` has one line per quit

**Dependencies:** T13
**Files:** `helper/bar/QuitOnClose.swift`, `helper/bar/main.swift`,
`helper/bar/Config.swift`
**Scope:** M

### T15: Seed the exceptions from Vorssaint

**Description:** If `quit-on-close.conf` does not exist, `install.sh`
writes it from `defaults read com.vorssaint.utils autoQuitExceptions`,
or from a default list (Finder, Music, Raycast). It sets
`quit_on_close = off` if Vorssaint had it off.

**Acceptance criteria:**
- [ ] On this Mac, the file holds the 7 Vorssaint apps
- [ ] An existing file is never changed

**Verification:**
- [ ] `bash -n`; manual: run the block on this Mac

**Dependencies:** T14
**Files:** `install.sh`
**Scope:** S

### T16: Quit on Close settings page and docs

**Description:** A Settings page with the on/off switch and the
exceptions list: add one of the running apps, remove one. This needs a
new list control in `SettingsReport` and `SettingsView`. README and
CLAUDE.md describe the feature and the file.

**Acceptance criteria:**
- [ ] Adding and removing apps writes the file, and the bar reloads it
- [ ] Previews show the page with the 7 apps

**Verification:**
- [ ] `swift build`, `bin/omacchiato-test`
- [ ] Manual: add and remove an app

**Dependencies:** T14, T15
**Files:** `helper/bar/Settings.swift`,
`helper/ui/Sources/SettingsPanel/*.swift`, `README.md`, `CLAUDE.md`
**Scope:** M

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| A posted event does not reset the idle time that Teams reads | High | T1 checks this first. The fallback is a 1-point move and back. |
| Vorssaint and Omacchiato both run keep awake, quit on close or Super+Esc | Medium | Turn each one off in Vorssaint at its checkpoint. Super+Esc fires twice until then. |
| The sudoers rule allows more than `pmset disablesleep` | High | Only the two exact commands. `visudo -cf` before the move. |
| `SleepDisabled 1` is left on after a crash | Medium | The bar sets 0 at start. `uninstall.sh` sets 0. |
| Quit on close quits an app with work in progress | High | `terminate()` is a polite quit, so apps ask about unsaved work. The 1-second wait and the exceptions cover the rest. |
| OmniWM's parked windows are missing from AX | High | T12 checks this before any quit code exists. |
| The window watch costs CPU with many apps | Low | One observer per app, events only; no polling. |

## Open questions

- None that block Phase 1.
