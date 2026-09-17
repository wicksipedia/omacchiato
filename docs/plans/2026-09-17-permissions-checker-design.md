# Permissions checker: design

Date: 2026-09-17. Status: approved.

## Problem

`omacchiato-bar` and `omacchiato-gesture` need privacy permissions that you
switch on one at a time in System Settings. `install.sh` lists the steps as
text. A rebuild of `omacchiato-gesture` drops its Accessibility grant, and you
find out when swipes stop working. No command tells you which Omacchiato
permission is missing or opens the page where you fix it.

## Scope

In scope: the permissions that `omacchiato-bar` and `omacchiato-gesture` hold,
and a banner for the commands that you run by hand.

Out of scope: the permissions of Karabiner-Elements, OmniWM, Ghostty and the
terminal. `omacchiato-overview` and `omacchiato-helper` get no switch, because
macOS charges their requests to the program that starts them.

## What you see

- `omacchiato-permissions` prints the banner and a table with one row for each
  permission, marked ✅ or ❌.
- For each ❌, it names the switch to turn on, opens that page in System
  Settings and waits for Enter. Then it restarts the app and checks again.
- If the switch is on and the check still fails, it offers to run
  `tccutil reset <Service> <bundle-id>`. That clears an entry that an older
  build left behind. Then it asks again.
- If stdin is not a terminal, it prints the table and a Settings link for each
  ❌, and exits 1.
- `install.sh` runs it at the end. `omacchiato-update` runs it on every run
  except `--check`: through `install.sh` after a pull, and directly when there
  is nothing to pull.
- `install.sh`, `uninstall.sh`, `omacchiato-update` and
  `omacchiato-permissions` print the banner first when you run them in a
  terminal. The banner prints once for each run, so `omacchiato-update` does
  not print it again when it starts `install.sh`.

The banner. The cup and the wordmark use the accent colour of the current
theme, and the steam and the foam use the terminal's text colour:

```
   ░ ░ ░       ▄▄▄▄  ▄▄   ▄▄  ▄▄▄▄   ▄▄▄▄▄  ▄▄▄▄▄ ▄▄  ▄▄ ▄▄  ▄▄▄▄  ▄▄▄▄▄▄  ▄▄▄▄
 ▗▄▒▒▒▒▒▄▖    ██  ██ ██▀▄▀██ ██  ██ ██     ██     ██  ██ ██ ██  ██   ██   ██  ██
 ▐███████▌▜▖  ██  ██ ██ ▀ ██ ██▀▀██ ██     ██     ██▀▀██ ██ ██▀▀██   ██   ██  ██
  ▜█████▛▗▘   ▀█▄▄█▀ ██   ██ ██  ██ ▀█▄▄▄▄ ▀█▄▄▄▄ ██  ██ ██ ██  ██   ██   ▀█▄▄█▀
 ▀▀▀▀▀▀▀▀▀       omakase + macOS + macchiato
```

## How it works

### Which process holds a grant

TCC charges a permission request to the responsible process. launchd and
LaunchServices start a process that is responsible for itself. A child that
`popen` or `posix_spawn` starts inherits the responsible process of its parent.
For Omacchiato that means:

- launchd starts the bar and the gesture daemon, so each holds its own grants.
- A swipe starts `omacchiato-overview` through the gesture daemon, so the
  gesture daemon holds the Screen Recording grant that the overview uses.
- The bar runs `theme-set` on an appearance change, and `theme-set` runs
  `omacchiato-helper ghostty-reload`. So the bar holds the Automation grant
  for Ghostty.

If Ghostty runs an app binary directly, macOS charges the request to Ghostty.
So the checker starts each app with
`open -n -W --stdout <file> <app> --args --request-permissions`. LaunchServices
makes that copy responsible for itself.

### `--request-permissions`

The switch runs before the app starts its normal work. It asks for each
permission, prints one `<permission> granted|denied|unknown` line for each, and
exits. It does not draw the bar or start the event tap.

| App | Permission | Request | Check |
|---|---|---|---|
| `omacchiato-bar` | Accessibility | `AXIsProcessTrustedWithOptions`, prompt on | `AXIsProcessTrusted` |
| | Bluetooth | create a `CBCentralManager` and wait for its state callback | `CBManager.authorization` |
| | Location | `CLLocationManager.requestWhenInUseAuthorization` | `authorizationStatus` |
| | Automation: Music, System Events, Ghostty | `AEDeterminePermissionToAutomateTarget`, `askUserIfNeeded` on | the same call |
| `omacchiato-gesture` | Accessibility | as for the bar | as for the bar |
| | Screen Recording | `CGRequestScreenCaptureAccess` | `CGPreflightScreenCaptureAccess` |

- The bar skips a permission when `bar-pills.conf` hides the pill that uses
  it: Bluetooth for `bluetooth` and Location for `wifi`. The bar already
  avoids the Bluetooth grant for a hidden pill. The media pill cannot hide,
  so the bar always asks for Music.
- The gesture daemon does not ask for Input Monitoring. On macOS 27 it reads
  raw touches, and Input Monitoring has no entry for it.
- `AEDeterminePermissionToAutomateTarget` returns `procNotFound` when the
  target app is not running. The switch reports `unknown`, and the checker
  tells you to open that app and run the check again. It never opens Music
  for you.
- Screen Recording shows its prompt once. After a "no", only System Settings
  can change the answer.
- After each step, the checker restarts the app with
  `launchctl kickstart -k gui/<uid>/com.omacchiato.<app>`, because a grant
  can apply only at the next launch.
- On macOS 27 the Accessibility request shows a dialog with "Open System
  Settings" and "Deny". The checker opens the page either way.
- `open -W` can print "Unable to block on application" when the app exits
  before `open` finds it. The checker reads the output file and ignores the
  exit status of `open`.

### Settings links

`x-apple.systempreferences:com.apple.preference.security?Privacy_<pane>`, with
the panes `Accessibility`, `ScreenCapture`, `Bluetooth`, `Automation` and
`LocationServices`. Apple does not document these links. Each one opened the
right page on macOS 27. macOS 27 names the Accessibility page "Device Control
and Data Access" and the Screen Recording page "Screen & System Audio
Recording". So the walk-through says "the page that opens" and names no page.

### Stale entries

`tccutil reset Accessibility|ScreenCapture <bundle-id>` runs without root.
The bundle IDs are `com.omacchiato.bar` and `com.omacchiato.gesture`. The
checker asks before it runs a reset. `tccutil` looks up the bundle ID in
LaunchServices and fails with `-10814` for a bundle that LaunchServices does
not know. LaunchServices knows both apps on this Mac.

### Banner

`bin/omacchiato-banner` exits at once when stdout is not a terminal or when
`OMACCHIATO_BANNER_SHOWN` is set. It reads `ACCENT` (`0xAARRGGBB`) from
`~/.config/omarchy/current/theme/sketchybar.sh` and prints 24-bit colour. It
prints no colour when that file is missing or `NO_COLOR` is set. Each caller
exports `OMACCHIATO_BANNER_SHOWN=1` after it runs the banner. The cup needs
79 columns, so a narrower terminal gets the wordmark only. The script reads
the width with `stty size </dev/tty`, because `tput cols` in a command
substitution reports 80 for any width. The script targets `/bin/bash` 3.2.

## Tests run on 2026-09-17 (macOS 27.0)

1. A child inherits its parent's grants. A probe binary that Ghostty started
   saw Ghostty's Accessibility and Screen Recording grants. The same probe,
   spawned with `responsibility_spawnattrs_setdisclaim`, saw none. Screen
   Recording lists `omacchiato-gesture.app`, switched off, and has no entry for
   `omacchiato-overview`. So a swipe-started overview shows no previews today,
   and the README is wrong about which program holds the grant.
2. `open -n -W --stdout` captured the output of a test app. The app saw its
   own grants, not Ghostty's.
3. The Accessibility request showed a dialog.
4. All six Settings links opened the right page.
5. After the build, the walk-through ran while both daemons ran, and it
   worked as designed. The rebuilt `omacchiato-gesture`, signed with the
   Apple Development identity, kept its Accessibility grant.

## Risk

- A check-only `AXIsProcessTrusted` call from a new binary added a
  switched-off entry to the Accessibility list. The switch adds no new
  entries for the bar and the gesture daemon, because both already have
  entries.
- Input Monitoring for `omacchiato-gesture` was checked on macOS 27 only. On
  macOS 26 the daemon may still need it, and the checker does not ask.

## Build order

1. `bin/omacchiato-banner`, then call it from `install.sh`, `uninstall.sh` and
   `omacchiato-update`.
2. `--request-permissions` in `helper/bar.swift`. Rebuild the bar. It keeps
   its grants.
3. `--request-permissions` in `helper/gesture/main.m`. Rebuild the gesture
   daemon.
4. `bin/omacchiato-permissions`.
5. `install.sh` runs `omacchiato-permissions` at the end. Remove the
   "Waiting for accessibility" warning, because the checker covers it.
6. Update the permissions table in `README.md`: the gesture daemon holds
   Screen Recording for the overview, and needs no Input Monitoring on
   macOS 27. Add the checker to the notes in `CLAUDE.md`.

## Not in this design

- Permissions of Karabiner-Elements, OmniWM, Ghostty and the terminal.
- Switches on `omacchiato-overview` and `omacchiato-helper`.
- A bar pill or popup that shows permission state.
- The banner on `theme-set` and the other quick commands.

## Testing

- `bash -n` on each new and changed script, then a run under `/bin/bash`.
- `omacchiato-permissions </dev/null` prints the table and the links, and exits
  1 when a permission is missing.
- `omacchiato-permissions | cat` prints no banner.
- Rebuild the gesture daemon, run the walk-through, and confirm that swipes
  work after it.
- `omacchiato-update` in a terminal prints one banner.
