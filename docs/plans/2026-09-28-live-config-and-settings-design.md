# Live config and a settings window

## Goal

1. When `bar-pills.conf` or `bar-plugins.conf` changes, the bar shows
   the change without a restart by hand.
2. The Apple menu gets an "Omacchiato Settings…" row. It opens a window
   where the user changes those settings, edits the files as text, and
   reveals the files in Finder.

## What the code does today

- `pillModes` (`bar.swift`) and `barPlugins` (`Plugins.swift`) are `let`
  globals. The bar reads both files once, when the process starts.
  `rightOrder` is computed from them, also once.
- `theme.conf` is the exception: the bar reads it again when it needs
  it.
- `watch(path:create:handler:)` in `main.swift` already watches one
  file and re-arms after a rename. Editors save by a rename, so a watch
  on a file's descriptor goes deaf after the first save unless it
  re-arms.
- The launch agent has `KeepAlive`. launchd starts the bar again when it
  exits, but it waits 10 s (`ThrottleInterval`) if the bar ran for less
  than 10 s.
- The bar is an agent app (`LSUIElement`). The popup windows never
  become key. The cheatsheet (`CheatWindow`) is the one window that
  does: it overrides `canBecomeKey` and calls `NSApp.activate`.

## Feature 1: reload on change

### Decision: reload in place

The bar rereads the files and rebuilds what depends on them, without a
restart. Nothing blanks, and the settings window stays open. A restart
would be less work, but it blanks the bar for about 1 s and closes the
settings window.

### What depends on the config

- `pillModes`: 20 reads in six files, 16 of them `pillModes[key]` at
  the moment of use. Those pick up a new value by themselves once the
  global changes.
- `rightOrder` (11 reads) and `iconOnly` (3) are derived from
  `pillModes` and `barPlugins`.
- `barPlugins` (5 reads). `startPlugins()` starts one repeating timer
  per plugin and keeps no handle to it, so a removed plugin would keep
  running.
- `main.swift` starts some providers only if their pill is in
  `rightOrder` at startup: the mic watcher, the Bluetooth watcher, the
  status timer and the weather timer.

### Plan

1. Make `pillModes`, `barPlugins`, `rightOrder` and `iconOnly` `var`.
   Put their computation in one `loadConfig()` that sets all four.
2. Keep each plugin's timer in `pluginTimers: [String: Timer]`. A
   reload stops the timers of plugins that went away or whose command
   or interval changed, and starts timers for new or changed plugins.
   The screen-lock observers read the current `barPlugins`, not a copy.
3. A reload drops `rightItems`, `pluginRows` and `pluginPanels` entries
   for pills that went away, and closes the open popup if its pill went
   away.
4. Move each "start if in `rightOrder`" block in `main.swift` into a
   function that starts the provider once. A reload calls it for pills
   that are new. A provider is not stopped when its pill goes away: a
   hidden provider costs little, and a stop path is code that must be
   right. A provider that is not started still costs nothing.
5. After the reload, `repaint()` every bar surface, and refresh an open
   popup.
6. Watch the folder `~/.config/omacchiato`, not the files. A folder
   watch sees a save by rename and a file that did not exist yet. Use
   the existing `watch()` on the folder.
7. On an event, wait 300 ms for more events, then hash the two files.
   Other files in that folder change all the time (the plugin caches,
   `theme.conf`), so compare the hash, not the event. Reload only if a
   hash changed, and log it with `tlog`.
8. Keep the parse permissive, as now: a bad line is skipped. So a half
   saved file cannot stop the bar.
9. Tests: `loadConfig` is split into a pure function from the two file
   texts to the four values, tested in the bar's test target, including
   `rightOrder` for opt-in pills and hidden pills. A second pure
   function takes the old and new plugin lists and returns the plugins
   to stop and to start.

## Feature 2: the settings window

### Where it opens

- A row "Omacchiato Settings…" in the Apple menu, in both
  `appleMenuRows()` (read from the app's AX menu) and the fallback
  `appleRows()`. Put it above "Theme".
- Optional: a `Super+,` chord through the Karabiner rules, as `Super+K`
  opens the cheatsheet.

### The window

- A normal titled window, centred, that can become key, like
  `CheatWindow`. The bar calls `NSApp.activate` so text fields take
  keys. Esc and ⌘W close it. On close, the app that was in front gets
  focus back, as the cheatsheet does.
- SwiftUI, in a new module `helper/ui/Sources/SettingsPanel`, with
  previews like every other panel.
- Tabs:
  1. **Pills.** One row per pill from `rightOrderAll` and the plugins:
     shown, icon only or hidden. Pickers for the modes that exist
     (`volume = muted`, `battery = time`, `media = <n>`) and for each
     `<pill>_panel` design. Gaps (`left_gap`, `right_gap`) as steppers.
  2. **Plugins** (later, not in the first version). One row per
     `[section]` of `bar-plugins.conf`: name, command, interval, icon.
     Add and remove.
  3. **Files.** Both files as plain text, with Save. Plugins are edited
     here in the first version. Each file has
     "Reveal in Finder" (`NSWorkspace.activateFileViewerSelecting`) and
     "Open in Editor".
- Apply writes the files. The watcher from feature 1 then reloads the
  bar, and the window stays open.

### Writing the files

- The files are also edited by hand, so the writer changes lines in
  place and keeps comments, blank lines and order. It replaces a
  `key = value` line, adds a new key at the end, and removes a line
  only when the user removes the setting.
- Keys the window does not know stay as they are, and the Files tab
  shows them.
- One table of known settings (name, allowed values, one-line help)
  drives the Pills tab. Keep it next to the code that reads each
  setting, so a new setting cannot be missed.
- Tests: the writer is a pure function over the file text. Test that it
  keeps comments and unknown keys, replaces a value, adds a key, and
  round-trips a file it did not change.

## Order of work

1. `loadConfig()` and the `var` globals, with tests. No behaviour
   change yet.
2. Plugin timers by name, and the plugin diff, with tests.
3. The folder watcher and the reload.
4. The config writer, with its tests.
5. The settings window: the Files tab first (it is the smallest, and it
   is useful alone), then the Pills tab.
6. The Apple menu row.

## Open questions

- The Plugins tab comes after the first version.
- `Super+,` to open the settings: yes or no.
