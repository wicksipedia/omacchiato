# Keep awake and quit on close: design

Date: 2026-09-30. Status: approved, with A for both decisions. The task
breakdown is in `tasks/plan.md`.

## Problem

Two Vorssaint features still run on this Mac: keep awake and quit on
close. The goal is to move both into Omacchiato, with the options that
Vorssaint has set now, and then turn them off in Vorssaint.

## What Vorssaint does now

Read from `defaults read com.vorssaint.utils`, `pmset -g` and
`pmset -g assertions` on 2026-09-30.

Keep awake:

| Setting | Value | Meaning |
|---|---|---|
| `keepAwakeShortcut` | `control+option+command:53` | Super+Esc turns it on or off. |
| `defaultDurationMinutes` | 0 | On until turned off. |
| `keepAwakeAllowDisplaySleep` | 1 | Only the system stays awake. The display still sleeps. |
| `keepAwakeMouseJiggleEnabled` | 1 | It posts a small mouse event, so apps do not show "Away". |
| `keepAwakeMouseJiggleIntervalMinutes` | 1 | One event every minute. |
| `batteryLimitPercent` | 20 | It turns off below 20% on battery. |
| `clamshellPreferred` | 1 | The Mac stays awake with the lid closed. |
| `keepAwakeRightClickToggle` | 1 | A right-click on its menu bar icon turns it on or off. |
| `keepAwakeIconTint` | pink | The colour of the icon while on. |

While on, Vorssaint holds a `PreventUserIdleSystemSleep` assertion
named "Vorssaint: keep the Mac awake". For the lid, it sets
`SleepDisabled 1` (`pmset -a disablesleep 1`), through a rule in
`/etc/sudoers.d/vorssaint-clamshell`. The jiggle shows in
`pmset -g assertions` as a `UserIsActive` assertion from IOHIDSystem.

Quit on close:

| Setting | Value |
|---|---|
| `autoQuitEnabled` | 1 |
| `autoQuitExceptions` | Finder, Phone, OrbStack, 1Password, Claude, Music, Raycast |

When the last window of an app closes, Vorssaint quits the app, except
for the apps in the list.

## What Omacchiato has now

- `bin/omacchiato-keep-awake` is a plugin. It reads `pmset -g
  assertions` and shows a cup while a user process holds the Mac awake.
  Its popup lists the holders. It cannot turn keep awake on or off.
- The pill hides while nothing holds the Mac awake.
- `bar-plugins.conf` on this Mac has `on_click = omacchiato-keep-awake
  toggle`. The bar has no `on_click` key, and the script has no
  `toggle`, so this line does nothing. Remove it.
- The bar already has Accessibility, a `screenLocked` flag, the battery
  level, an event tap, and a HUD window.

## Part 1: keep awake

### Design

The bar holds the assertion. A crash of the bar then ends keep awake,
so the Mac never stays awake by mistake.

- **State:** `~/.local/state/omacchiato/keep-awake` holds `on`, or an
  end time for a timed run. The bar watches the file, as `Config.swift`
  watches the config.
- **Command:** `omacchiato-keep-awake on | off | toggle | for <minutes>`
  writes the state file. With no argument, the script prints the pill
  as now. The Karabiner rule and the popup both run the command.
- **Assertion:** `IOPMAssertionCreateWithName` with
  `kIOPMAssertionTypePreventUserIdleSystemSleep`, named "Omacchiato:
  keep the Mac awake". If `keep_awake_display = on`, the bar also holds
  `PreventUserIdleDisplaySleep`. The default is off, as in Vorssaint.
- **Jiggle:** every `keep_awake_jiggle` minutes (default 1, `off` turns
  it off), the bar posts a mouse-moved event at the pointer's current
  position. The pointer does not move. It stops while the screen is
  locked. A mouse-moved event at the pointer's own position, posted to
  `kCGHIDEventTap`, resets both idle counters and does not move the
  pointer. Test on 2026-09-30: `HIDIdleTime` went from 12.32 s to
  0.30 s, and `CGEventSourceSecondsSinceLastEventType` from 12.23 s to
  0.31 s. Teams is still to check, at Checkpoint B.
- **Battery limit:** on battery, at or below `keep_awake_battery`
  percent (default 20), the bar turns keep awake off and shows the HUD.
- **Timer:** a timed run ends at its end time, and the HUD says so.
- **HUD:** a glass HUD, "Keeping Awake" or "Sleep Allowed", in the
  shared HUD window. `keep_awake_hud = off` turns it off.
- **Shortcut:** a Karabiner rule for Super+Esc runs
  `omacchiato-keep-awake toggle`.
- **Popup:** the keep-awake panel gets a toggle and time buttons: 30
  minutes, 1 hour, 2 hours and "Until turned off". It still lists the
  other holders. When the bar holds the only assertion, the list shows
  "Omacchiato", with the time left.
- **Settings:** the Keep Awake page gets these controls: display sleep,
  jiggle and its interval, the battery limit, the HUD, and the lid
  (below).

### Lid closed (decision 2)

`pmset -a disablesleep 1` needs root. Vorssaint installs a sudoers rule
for it. Omacchiato would do the same:

- `install.sh` asks once for the admin password and writes
  `/etc/sudoers.d/omacchiato-keep-awake`. The rule lets the user run
  only `/usr/bin/pmset -a disablesleep 0` and
  `/usr/bin/pmset -a disablesleep 1`, with no password.
- `visudo -cf` checks the file before it is moved into place.
- The bar sets `disablesleep 1` when keep awake turns on, unless
  `keep_awake_lid = off`, and sets 0 when keep awake ends. A marker file
  records that the bar set it, so the bar undoes only its own setting.
  After a crash, the next start reads the state file and the marker and
  sets 0 if keep awake is off.
- `omacchiato-lid-rule` checks for its own file, not with `sudo -n -l`,
  because `sudo -l` lists a command for any admin, password or not.
- `uninstall.sh` removes the rule and sets `disablesleep 0`.

Risk: with `SleepDisabled 1`, a Mac in a bag stays awake and gets hot.
The battery limit covers part of that risk.

### Pill when off (decision 1)

The pill hides while nothing holds the Mac awake. With the pill hidden,
there is nothing to click to turn keep awake on. See decision 1.

### Tests

- Python: the state file (`on`, `off`, `for 30`, an end time in the
  past), and the command's argument parsing.
- Swift: a pure function that takes the state, the time, the battery
  level and the power source, and returns on, off, or "turn off, battery
  low". The timer and the battery limit use it.
- On the screen, with the user's permission: Super+Esc, the HUD, the
  assertion in `pmset -g assertions`, Teams status after 10 minutes
  idle, and the lid.

## Part 2: quit on close

### Design

The bar watches windows through Accessibility and quits an app when its
last window closes.

- **Watch:** for each running app with `.regular` activation policy,
  an `AXObserver` for `kAXUIElementDestroyedNotification` on its
  windows, and `kAXWindowCreatedNotification` on the app to watch new
  windows. `NSWorkspace` launch and quit notifications add and remove
  apps.
- **Decision:** after a window closes, wait 1 second. Then read
  `kAXWindowsAttribute`. Count only windows with the subrole
  `AXStandardWindow` or `AXDialog`, and count minimized windows as open. If the count
  is 0, the app is not in the exceptions, and the app is not frontmost
  with a sheet or dialog open, call `NSRunningApplication.terminate()`.
  That is a normal quit, so an app with unsaved work still asks.
- **Wait:** the 1-second wait covers an app that closes one window and
  opens another, for example a settings window that becomes a main
  window.
- **Never quit:** apps that were launched with no window and never
  showed one, the bar and other Omacchiato apps, OmniWM, and every
  `com.apple.*` system agent that has no Dock icon.
- **OmniWM:** OmniWM parks windows off screen on other workspaces. They
  are still in `kAXWindowsAttribute`, so they count as open. Test on
  2026-09-30: Outlook, Teams and Safari, each on a workspace that was
  not on screen, each listed one `AXStandardWindow` at x = 1799, the
  parking spot. Finder listed only an `AXDesktop` window, which must not
  count. So count `AXStandardWindow` and `AXDialog` (a settings window
  that stays open means the app is in use), minimized ones too, and not
  `AXDesktop` or floating panels.
- **Exceptions:** `~/.config/omacchiato/quit-on-close.conf`, one bundle
  ID per line, with `#` comments. The first install writes the
  Vorssaint list, if Vorssaint has one, else a default list: Finder,
  Music and Raycast.
- **Switch:** `quit_on_close = off` in `bar-pills.conf` turns it off. It
  is on after the first install only if Vorssaint had it on.
- **Settings:** a Quit on Close page with the switch and the exceptions
  list: add an app from the running apps, remove one. The config
  watcher already reloads a changed file.

### Tests

- Swift: a pure function that takes the app's windows (subrole,
  minimized), the bundle ID, the exceptions and whether the app ever
  showed a window, and returns quit or keep.
- On the screen, with the user's permission: close the last window of
  TextEdit (quits), of Finder (stays), of an app with an unsaved
  document (asks), and of an app with windows on another workspace
  (stays).

## Order of work

1. Keep awake without the lid: state file, command, assertion, jiggle,
   battery limit, timer, HUD, Super+Esc, popup, settings.
2. The lid: the sudoers rule in `install.sh` and `uninstall.sh`, and
   `disablesleep` in the bar.
3. Quit on close.
4. Turn off keep awake, the mic shortcut and quit on close in Vorssaint.

Each step is one commit and can ship alone.

## Decisions

1. **Keep-awake pill while off.** (A) Always show the cup, dimmed while
   off, so a click can turn keep awake on. A right-click turns it on or
   off, as in Vorssaint. The bar takes no right-click on a pill yet, so
   `BarView` needs `rightMouseDown`. (B) Hide it while off, and turn keep awake on
   with Super+Esc only. Recommended: A.
2. **Lid closed.** (A) Build it, with the sudoers rule above. (B) Leave
   it out, so the Mac sleeps when the lid closes. Recommended: A,
   because it is on in Vorssaint now.
