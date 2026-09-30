# Omacchiato: notes for Claude

Omacchiato is an omarchy-style tiling desktop for macOS 26: a status bar,
a gesture daemon, a workspace overview, themes and install scripts
around the OmniWM window manager. README.md describes the features and
CONTRIBUTING.md holds the design rules. This file holds what the code does not show.
Notes about one Mac go in CLAUDE.local.md, which git ignores.

## Repository

- Omacchiato is a fork of omacosy. `origin` is this fork,
  github.com/wicksipedia/omacchiato. `upstream` is paulsp94/omacosy. To
  take upstream work, run `git fetch upstream && git merge upstream/main`.
- Upstream still uses the omacosy names. Git follows the renamed files,
  but a new upstream file or line that says omacosy needs the rename by
  hand.
- `migrate-omacosy.sh` moves an omacosy install to the omacchiato names:
  agents, binaries, `~/.config` and `~/.local/state`, and the command
  names in `bar-plugins.conf` and the herdr config. `install.sh` and
  `uninstall.sh` run it first, so they know the new names only. The new
  signing identifiers need new TCC grants.
- `omacchiato-update` fast-forwards the local branch to the newest date
  tag on the branch that it tracks, then runs `install.sh` again.
  `--edge`, or a branch with no tags, takes the branch tip. At a tag,
  `install.sh` downloads the binaries of that GitHub release, and
  checks `SHA256SUMS` and the team ID in `RELEASE_TEAM`. It replaces
  a binary only when its CDHash changed. `OMACCHIATO_BUILD=1` forces a
  build.
- `config/requirements.conf` holds the minimum app versions that
  `bin/omacchiato-requirements` checks. Raise one when Omacchiato starts to
  write a setting that only a newer version of the app reads.
- The clone lives at `~/.local/share/omacchiato`, and configs are symlinked
  into it, so an edit to a symlinked config is live. A clone in
  `~/Documents`, `~/Desktop` or `~/Downloads` gets copies instead,
  because TCC blocks launchd agents from those folders.

## Commits and pushes

- Write the message to a file and use `git commit -F <file>`. In zsh, a
  `\` after a `<<'EOF'` marker joins the title line to the command, and
  the shell runs the title as a command.
- There is no interactive `git add -p`. To stage part of a file, filter
  `git diff -U0 <file>` to the hunks you want and pipe the result to
  `git apply --cached --unidiff-zero -`.
- End each message with the `Co-Authored-By: Claude` line. Do not add
  session links.
- Apply the stop-slop rules to commit messages, PR text, README text and
  comments.
- Ask before a force-push, and use `--force-with-lease`.

## Build and test

- `install.sh` is idempotent. It rebuilds only the binaries whose sources
  changed, reloads the launch agents, runs `macos-defaults.sh`, and
  copies the Karabiner and gesture configs. Do not run it to test one
  change: it restarts services.
- To rebuild only the bar:

  ```sh
  swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight -framework DisplayServices \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker helper/bar-info.plist \
    -o "$TMPDIR/omacchiato-bar" helper/bar/*.swift helper/ui/Sources/*/*.swift
  cp "$TMPDIR/omacchiato-bar" omacchiato-bar.app/Contents/MacOS/omacchiato-bar
  codesign -f -s "Apple Development" --identifier com.omacchiato.bar omacchiato-bar.app
  launchctl kickstart -k "gui/$(id -u)/com.omacchiato.bar"
  ```

- `bin/omacchiato-build <target> <out-path>` builds and signs one
  binary. `install.sh` and `bin/omacchiato-release` both use it.
- `bin/omacchiato-release` publishes `origin/main` as a GitHub release
  with a date version (`vYYYY.MM.DD`). It needs a clean tree, the Apple
  Development identity and `gh`. It reuses the gesture app of the last
  release while `helper/gesture/` is the same. The plan is in
  `docs/plans/2026-09-28-versioned-releases-design.md`.
- TCC keys a grant on the code signature. Sign with the same Apple
  Development identity and identifier every time, and the bar, overview
  and helper keep their grants across rebuilds.
- `omacchiato-gesture` is the exception. TCC pins its grant to the exact
  build, so every rebuild needs a new Accessibility grant. `install.sh`
  rebuilds it only when a file in `helper/gesture/` changed.
- `bin/omacchiato-test` runs every check that needs no screen: `bash -n`
  on the shell scripts, `python3 -m unittest discover -s tests`, and
  `swift test`. A GitHub Action runs it on every push. When you fix a
  logic bug, add a test for it.
- The bar's tests use Swift Testing, in `tests/bar/`. `Package.swift`
  exists only for them, and `install.sh` still builds the bar with
  `swiftc`. The tests `@testable import omacchiato_bar`, which holds
  `helper/bar/*.swift`. A test calls a function that takes plain
  values, so move the logic out of the AX, AppKit or subprocess code
  first, as `layoutOrder` and `shortcutText` do. The suite runs serially,
  because some tests set globals.
- The Python tests use `unittest`, in `tests/test_*.py`. `tests/loader.py`
  imports a script from `bin/`, so each script keeps its run code in
  `main()` behind `if __name__ == "__main__"`.
- For the look of the bar, rebuild, restart and look at it, for example
  with `screencapture -x -R0,0,3000,40 bar.png`.
- Logs: `/tmp/omacchiato-bar.log` (timings and `tlog` lines),
  `/tmp/omacchiato-bar.err`, `/tmp/omacchiato-gesture.log`,
  `/tmp/omacchiato-overview.log`, `/tmp/omacchiato-ws.log`.
- Launch agents: `com.omacchiato.bar` and `com.omacchiato.gesture`. Restart
  one with `launchctl kickstart -k "gui/$(id -u)/<label>"`.

## Tests on the user's screen

- Ask before a test that opens menus, posts clicks or moves the pointer.
  The user can be in a meeting or sharing the screen.
- Never post an Escape key event. It can reach the Claude Code terminal.
- If the macOS menu bar stays on screen over the bar, quit the app whose
  menu bar icon was last pressed through Accessibility. A restart of
  SystemUIServer, the Dock or the bar does not release it.

## The bar (`helper/bar/`)

- The bar, its popups and its OSDs are one process. `rightOrder` sets
  the pill order: `menubar`, then the plugin pills in file order, then
  the built-in pills.
- `~/.config/omacchiato/bar-pills.conf` holds `<pill> = <mode>` lines:
  `hide`, `icon`, `volume = muted`, `battery = time`,
  `media = <characters>`, `<pill>_panel = <design>`, and
  `volume_hud = off` and `volume_click = off` for the volume keys, and
  `mic_hud = off`. The mic watch runs with the mic pill hidden, so the
  mic HUD still shows. `keep_awake_display`, `keep_awake_jiggle`,
  `keep_awake_battery`, `keep_awake_lid` and `keep_awake_hud` tune keep
  awake.
- `Config.swift` watches `bar-pills.conf` and `bar-plugins.conf`, and
  their folder, because an editor saves by a rename and `echo >>` writes
  in place. When the text changes, `reloadConfig()` rereads both and
  rebuilds the pills in place: it stops and starts only the plugins that
  changed, and starts the provider of a pill that comes back. A
  provider is never stopped. A new setting that the bar reads once, at
  startup, does not reload: read it at the moment of use.
- "Omacchiato Settings…" in the Apple menu opens `Settings.swift`, a
  window that becomes key, so it uses system controls. It has a page
  for each pill and plugin, and every key of both files has a control.
  `builtinPills`, `pluginPrograms` and `pluginKinds`
  there say what each page offers: add a new pill mode or plugin script
  there too. A new panel design goes in `panelDesignNames` in
  `helper/ui/Sources/PanelDesigns`, which the previews read as well. A plugin's page knows it by its program,
  because a plugin prints no panel while its pill is empty. The AI
  usage page reads and writes the script's flags (`AIUsageOptions`,
  keep in sync with `main()` in `bin/omacchiato-ai-usage`). `confSet`,
  `iniSet` and `iniRemove` change one line or section and keep comments
  and order.
- A popup with designs shows them in the settings as thumbnails, each
  scaled to fit the whole panel. They are the real panels, drawn through
  the same `statusPanel`, `prPanel` and like functions in
  `helper/ui/Sources/PanelDesigns` as the popup, with the sample data in each module's `…Samples.swift`.
  Those samples build into the bar, not only into the Xcode previews.
  A sample that carries a read time is a computed `static var`, so its
  "Updated … ago" stays minutes old in a bar that runs for days.
- Every popup is a SwiftUI view in a `PanelHost`. `panelView(name)`
  picks it: a panel of its own, a plugin's `panel` object, or
  `RowsPanel`, which draws `popupRows(for:)` as a macOS menu. Only the
  Apple menu, the app menus and plugins with no `panel` use rows. The
  built-in panels take a report from `PopupRows.swift`.
  A panel whose data comes from a cache or a slow fetch (weather, AI
  usage, pull requests, updates) ends with `UpdatedStamp`, which shows
  the time of the last successful read, not of the last run, and turns
  orange past the panel's `staleAfter`. A click on it reads the data
  again: `updateWeather`, or `refreshPlugin`, whose next run sets
  `OMACCHIATO_REFRESH=1` so the script skips its cache down to a short
  floor (30 s for tokscale, 10 s for GitHub).
  `ControlSlider` and `ControlTile` in `StatusParts.swift` draw the
  Control Center slider and round button, by hand, because a system
  control draws grey in a window that is not key.
  `panelView` sets `panelSettings` in the environment for a pill with a
  Settings page, and `statusPanelBackground` then ends the panel with an
  "Omacchiato Settings" row that opens that page. A panel with a
  background of its own, such as the weather panel, has no such row.
  `panelRow` converts a `PopupRow`. The popup window never becomes key,
  so an event tap (`setPopupKeys`) gives a row popup its arrow keys,
  Return and Esc, and system controls there draw grey: draw them by hand.
- The bar itself draws with AppKit, not SwiftUI: it is on screen all
  the time, and a click lands only where a pill has ink.
  `helper/ui/Sources/BarPills` holds the workspace chips, the music pill,
  `Marquee`, `Ticker` and the text routines, as `StatusGauge` holds the
  gauge. They take plain values and colours, so Xcode previews them.
- `dur()` in the bar and in `overview.swift` returns 0 while Reduce
  motion is on. Pass every animation duration through it.
- The wi-fi popup lists the networks in range. A scan blocks for
  seconds, so it runs off the main thread and calls `refreshPopup`, and
  one answer serves for 20 s, because macOS throttles scans. The scan
  needs the same Location grant as the SSID. A click runs
  `networksetup -setairportnetwork`, which takes the password from the
  system keychain. Any output from it means the join failed, and the
  popup then opens the macOS wi-fi panel. A failed join leaves the
  current network up.
- The clock popup reads today's events with EventKit. It calls nothing
  in EventKit until the grant is `.fullAccess`, or a launchd agent
  raises the dialog with nothing on screen to explain it. The fetch runs
  off the main thread and calls `refreshPopup`, and one answer serves
  for 60 s. A week row opens Calendar over AppleScript, with a
  whole-day offset from today rather than a date string, because a date
  string parses in Calendar's locale. Midday holds the offset on the
  right day across a change of daylight saving.
- The wi-fi popup lists the iPhones that can share a hotspot.
  `SFRemoteHotspotSession` in the private `Sharing.framework` asks
  `sharingd` over XPC, which needs no entitlement and no grant:
  `setDelegate:`, `startBrowsing`, the delegate call
  `session:updatedFoundDevices:`, then
  `enableHotspotForDevice:withCompletionHandler:`. CoreWLAN holds the
  same calls (`startBrowsingForTetherDevicesAndReturnError:`), but
  `airportd` gates them behind `com.apple.wifi.tether.browse`, which
  only Apple's wi-fi agent carries. Every step gives up quietly, so a
  macOS that renames the class leaves the popup as it was.
- The completion of `enableHotspotForDevice:` hands over two plain
  strings, the network name and its password, although the type
  encoding of the block names `SFRemoteHotspotInfo` and `NSError`. Send
  either one a message and the bar dies on the XPC reply thread.
  Turning the hotspot on does not join it: the bar joins with
  `networksetup` and the password, and retries, because the network
  needs a few seconds to come up.
- Plugin pills come from `~/.config/omacchiato/bar-plugins.conf`. A command
  prints a label, or JSON with `label`, `color`, `icon` and `rows`. Row
  keys: `text`, `subtitle`, `detail`, `hero`, `dim`, `separator`,
  `slider`, `marker`, `bar`, `color`, `bar_color`, `url` and
  `terminal`. Labels
  are cut at 32 characters. The bar puts `~/.local/bin` and Homebrew
  first on `PATH` and sets `OMACCHIATO_PILL_ICON`. A row also takes `icon`,
  `icon_color`, `run` (a command with no window, then the plugin runs
  again) and `section` (`open`, `closed` or `end`). A row `url` may also
  use `x-apple.systempreferences:`. `foldSections`
  keys a section's open state by header text, because the detail changes.
  `parts` is a list of `icon`, `icon_color`, `label`, `label_color` and `under` that the pill
  draws after its own icon and label. `right_click` is a command that a
  right-click on the pill runs, then the plugin runs again. A `panel` object replaces the
  rows with a SwiftUI panel: `kind = ai-usage` for
  `helper/ui/Sources/AIUsagePanel`, `kind = github-prs` for
  `helper/ui/Sources/PRPanel`, and `airpods`, `keep-awake`, `updates`
  and `stats` for the panels of the same names. A plugin's panel calls
  back through `runPluginCommand` or `runInTerminal` in `Popups.swift`. `<pill>_panel` in `bar-pills.conf` picks
  the design. Plugin commands run with
  the bar's TCC grants.
- AppKit hit-tests a non-opaque window by alpha, so a pill background
  with zero alpha takes no clicks. `NSColor.clickable` raises zero alpha
  to 0.01.
- `main.swift` holds the code that runs at startup, in order. The other
  files hold the declarations, one topic a file: `bar.swift` (model,
  theme, plumbing), `Providers.swift` (the right-hand pills),
  `Plugins.swift`, `Popups.swift`, `PopupRows.swift` (the menus drawn as
  rows), `Menus.swift` (menu bar apps, app and Apple menus),
  `Calendar.swift`, `Network.swift`, `Permissions.swift`,
  `Cheatsheet.swift` and `BarView.swift`. Put a new global in one of
  them, where it starts when code first reads it. A global in `main.swift`
  starts when its line runs, and one that reads a later global there
  reads zero. `swiftc` accepts startup code only in a file named
  `main.swift`.
- The media pill reads Apple Music only (`com.apple.Music`, notification
  `com.apple.iTunes.playerInfo`). The artwork comes from osascript as
  `«data ...»` hex.
- If `~/.config/omacchiato/theme.conf` holds a `light:X,dark:Y` pair, the
  bar watches `NSApp.effectiveAppearance` and runs `theme-set` with the
  pair and `OMACCHIATO_APPEARANCE`.
- The native menu bar auto-hides (`_HIHideMenuBar`,
  `AutoHideMenuBarOption`), and the bar sits in its place.
- `demo = on` in `bar-pills.conf` makes `panelView` draw the popups
  that show private data (clock, weather, status, wi-fi, activity, menu
  bar apps, pull requests and AI usage) from the sample data, and hides the clock's
  event name and the user's name in the Apple menu. Use it for a screen recording that goes public.
- `omacchiato-popup <item> [display]` writes `/tmp/omacchiato-bar-popup`, and
  the bar opens that item's popup as a click would. It reads the file
  50 ms after a change, because a shell redirect empties the file first.
  Use it for screenshots instead of posted clicks.
- `Super+K` opens a cheatsheet built from the `[[hotkeys]]` in
  `~/.config/omniwm/settings.toml` and the Karabiner rules whose
  descriptions start with `omacchiato-omniwm:`.
- If OmniWM does not answer, the bar counts that as no window manager.
  It still draws on every screen with no workspace chips, and looks for
  OmniWM again every 5 s. If the bar is missing, read
  `/tmp/omacchiato-bar.err` and
  `launchctl print "gui/$(id -u)/com.omacchiato.bar"` (runs, last exit code).

## Quit on close (`QuitOnClose.swift`)

- An `AXObserver` per app with `.regular` activation policy. AX sends
  `kAXUIElementDestroyedNotification` only to the element that goes away,
  so each window gets its own, and `kAXWindowCreatedNotification` adds
  new ones. A second after a close, `shouldQuit` reads the windows.
- Count `AXStandardWindow` and `AXDialog`. OmniWM's parked windows are
  still in `AXWindows` as `AXStandardWindow`. Finder lists an
  `AXDesktop`, which does not count.
- Off unless `quit_on_close = on`, because a new user would not expect
  apps to quit.

## Menu bar apps pill

The design and the test results are in
`docs/plans/2026-09-14-menu-bar-apps-design.md`. The rules:

- Each app's status items come from its `AXExtrasMenuBar`. Skip
  `com.apple.*` apps and the bar itself. Set a short AX messaging
  timeout (0.25 s), because a hung app blocks the call.
- Never use `AXPress` on a status item. On an icon that the notch hides,
  a press keeps the macOS menu bar on screen until that app quits. On a
  visible icon, the menu opens and closes at once.
- The pill clicks for real. It moves the pointer to the top edge, waits
  until the menu bar window (CGWindowList layer 24) is on screen at
  y = 0, clicks the icon's centre, and moves the pointer back. The menu
  bar takes about 250 ms to slide in, and no setting shortens it.
- An icon that the notch hides has a frame with x < 0. The pill opens
  that app instead of a click.
- On a notched display, a point is clickable only inside
  `NSScreen.auxiliaryTopLeftArea` or `auxiliaryTopRightArea`.
- CGWindowList layers: 24 is the menu bar window, 25 holds the status
  items, and 101 holds pop-up menus.

## Themes (`bin/theme-set`)

- `theme-set <name>` or `theme-set light:<name>,dark:<name>`. A pair
  follows the macOS appearance, and `OMACCHIATO_APPEARANCE` overrides
  `AppleInterfaceStyle`. A theme name is a directory in `themes/`, and
  names with `/` or `..` are refused.
- It writes `~/.config/omacchiato/theme.conf` and links
  `~/.config/omarchy/current/theme`. The wallpaper changes only when the
  theme changes.
- Ghostty reloads through `omacchiato-helper ghostty-reload`: an Apple Event
  to `terminal 1` of the application. It skips `errAENoSuchObject`
  (no window open). A handler error comes back inside the reply, not as
  a thrown error.
- OmniWM's quake terminal reads the Ghostty config only when OmniWM
  reloads its `settings.toml`. So theme-set writes the Ghostty palette
  before it edits OmniWM's settings.
- Under a pair, OmniWM's `[appearance] mode` is `automatic`.
- OmniWM draws the focus border (`[borders]` in settings.toml). theme-set
  rebuilds every `[borders.*]` table from `themes/<name>/borders.sh`:
  `ACTIVE_COLOR` is the colour, `GRADIENT_COLOR` adds a gradient and
  `GLOW=1` a glow. A pair also writes `darkColor` and dark gradient
  endpoints. OmniWM has one glow switch for both appearances, so a pair
  glows only if both halves set `GLOW=1`. It keeps the user's `[borders]`
  on/off and width, glow radius and opacity, and gradient direction. The
  overview reads its accent from the same file.
- `theme-next` (`Super+Shift+T`) calls theme-set with one name, so it
  ends a light/dark pair.
- Runs of theme-set take turns under `lockf`, and a run that finds a
  newer switch queued behind it exits, so a burst of switches applies
  only the last. Every file that another program reloads is written to a
  temp file and renamed: Ghostty showed its Configuration Errors window
  when a reload read a half-written theme file. Each run logs to
  `/tmp/omacchiato-theme.log`.
- The bar and Karabiner start theme-set with launchd's PATH, where
  `python3` is the system's 3.9. Keep its Python to 3.9: `tomllib` (3.11)
  once stopped it before the `settings.toml` write, so OmniWM never
  reloaded and the quake terminal kept the old palette.
  `tests/test_theme_set.py` runs that step with `/usr/bin/python3`.

## OmniWM

- `config/omniwm/settings.toml` is a template. `install.sh` copies it
  once to `~/.config/omniwm/settings.toml` and never overwrites the copy.
  OmniWM and theme-set write the copy, and OmniWM reloads it live. Values
  for one desk, such as display pins by `displayUUID`, belong in the
  copy, never in the template.
- Nine workspaces in total, all Niri: 1–5 on the main display and 6–9 on
  the secondary display.
- Gestures: `fingerCount = 3` is the Niri column scroll, which focuses
  the column where it stops. `workspaceSwipeEnabled = false`, because
  `omacchiato-gesture` serves all four 4-finger swipes. `macos-defaults.sh` turns off the system's 3- and
  4-finger horizontal swipes.
- The trackpad taps on each fired swipe, under `haptic` in
  `gesture.json`. The tap comes at the commit, before the switch
  lands. `haptic_tap` opens the actuator for each tap: a handle that
  stays open goes quiet after some minutes and still reports success,
  which is why a tap worked only right after a restart. Pattern 6 is
  the strongest tap, and 15 and 16 give none.
- `followsMouse = false`, so focus follows clicks and keys only.
- OmniWM hotkeys cannot run shell commands.
  `bin/omacchiato-karabiner-omniwm install` adds Karabiner rules for those
  chords and replaces its own rules on each run. `install.sh` copies
  `config/karabiner/karabiner.json` over the live file, so it must add
  the OmniWM rules after that copy and after it writes `apps.conf`.
- The Karabiner rules, the bar and the overview run `omniwmctl` through
  `bin/omacchiato-omniwmctl`, which finds it in the Homebrew link, the
  release app or a dev build. `omacchiato-omni`
  (`helper/gesture/omnicli.c`) is a fast IPC client for the scripts.
  OmniWM rejects all IPC while its overview is open.
- OmniWM does not start while another window manager runs. It shows a
  "Conflicting Window Managers" dialog and does not check again, so
  launch it again after the other manager quits.
- A local OmniWM build shares the bundle ID `com.barut.OmniWM` with the
  Homebrew build. A grant can move between the two, and "Quit & Reopen"
  launches `/Applications/OmniWM.app`. Start a local build by its path.
- OmniWM's `make dev-install` puts `OmniWM Dev.app` in `~/Applications`,
  with the bundle ID `com.barut.OmniWM.dev` and the same IPC socket.
  Match OmniWM by bundle-ID prefix. An exact match once made the bar
  treat the dev build as no window manager.
- Screen Recording is optional for OmniWM.
- If OmniWM cannot use `settings.toml` at startup, it runs with its
  defaults, which turn IPC off. An explicit settings save then moves the
  file to `settings.toml.corrupt`. Check that file before you edit the
  defaults: OmniWM reloads a copied-back file live, and `omniwmctl` answers
  again once IPC is on. `settings.toml.pre-v3` is the byte copy from a
  schema upgrade. OmniWM's Health panel lists both files until they move.
- To work on upstream OmniWM (BarutSRB/OmniWM), run
  `./Scripts/dev-tools.sh setup` once. CI runs `make verify` (format,
  lint and build) and
  `LIBRARY_PATH="$(./Scripts/ghostty-preflight.sh print-library-dir)" swift test`.

## install.sh

- It copies `config/gesture/config.json` to
  `~/.config/omacchiato/gesture.json` on every run. The daemon serves
  all four directions. The horizontal ones need
  `workspaceSwipeEnabled = false` in `settings.toml`, or both engines
  answer the same swipe.
- It retires what older installs left behind. `migrate-omacosy.sh`
  stops the dwindle, borders and ffm agents and removes their binaries
  and links. The blocks after the bar build remove their config files
  and the AeroSpace config.
- While the previous window manager still runs, it warns and does not
  start OmniWM. Quitting a window manager strands the windows it parked
  off screen, so the user quits it.
- `uninstall.sh` removes only what the manifest
  (`~/.local/state/omacchiato/manifest`) lists. It runs
  `migrate-omacosy.sh` first, so it also removes the retired agents of an
  install that never ran a newer `install.sh`.

## Permissions (`bin/omacchiato-permissions`)

- TCC charges a request to the responsible process. A child that `popen`,
  `posix_spawn` or `Process` starts uses its parent's grants. A swipe
  starts the overview through the gesture daemon, so the overview uses
  that daemon's Screen Recording grant.
- `install.sh` runs `omacchiato-permissions` at the end.
  `omacchiato-update` runs it on every run except `--check`, also when
  there is nothing to pull.
- `omacchiato-permissions` starts each app with
  `open -n -W --stdout <file> <app> --args --request-permissions`.
  LaunchServices makes that copy responsible for itself. If you run the
  binary directly, it reports the terminal's grants.
- The switch runs before other startup code. In the bar it is the first
  line of `main.swift`. It always
  asks for Bluetooth, because a plugin command runs as a child of the bar
  and reads Bluetooth with the bar's grant, whatever `bar-pills.conf` says. In the
  gesture daemon it comes before the lock file, which the running daemon
  holds. It prints `<permission> granted|denied|unknown` lines, then
  `done`.
- `open -W` returns at once if the app exits before `open` finds it. So
  the script waits for the `done` line.
- `tccutil reset <Service> <bundle-id>` fails with `-10814` when
  LaunchServices does not know the bundle.
- `install.sh`, `uninstall.sh`, `omacchiato-update` and
  `omacchiato-permissions` run `bin/omacchiato-banner` first and export
  `OMACCHIATO_BANNER_SHOWN=1`, so a nested run prints no second banner.

## Pill scripts in `bin/`

- `omacchiato-github-prs [search qualifiers]` lists open PRs by
  `author:@me` through `gh`. An update is an unread GitHub notification.
  PRs that the user unsubscribed from are hidden. A swipe in the panel
  runs `--mark-read`, which stores the PR's `updatedAt` in
  `github-prs-read.json` and marks its notification read. The PR stays
  hidden until its `updatedAt` changes. It is not keyed on the
  notification, because GitHub marks that read when the user views the
  PR. Each PR carries one
  Nerd Font mark in `icon`, with `icon_color`, first match wins: a merge
  glyph for merged, an x for closed, a pencil for draft, a warning in
  red for a failed check or a merge conflict, a progress clock in yellow
  for a running check, a comment in yellow for changes requested or an
  unresolved thread from someone else, a green check for approved, and a
  muted clock for waiting. The sentence under a PR appears only when it
  says more than the mark: merged, closed, conflicts, a failed check,
  changes requested, or the number of threads to resolve.
- `omacchiato-keep-awake on | off | toggle | for <minutes>` writes
  `~/.local/state/omacchiato/keep-awake`: `on`, `off`, or an end time.
  `KeepAwake.swift` watches that folder and holds the assertion, so a
  crash of the bar ends keep awake. With no argument, the script prints
  the pill and leaves the bar's own assertion out of the holder list.
  With the lid option on, the bar runs `sudo -n pmset -a disablesleep`
  through the rule of `bin/omacchiato-lid-rule`. The marker file
  `keep-awake-lid` says the bar set it, so the bar undoes only its own
  setting and leaves another app's alone.
- `omacchiato-ai-usage --pill <id>[:<window>],... --panel <id>,...` reads
  plan usage from `tokscale usage --json` and the week from
  `tokscale graph`. `PROVIDERS` maps each id to a status page and a
  component name prefix. tokscale 4.17.0 reads the Claude Code token and
  never refreshes it, because a refresh races Claude Code and signs the
  user out. Check that again before you raise `TOKSCALE_VERSION`.
  `tokscale usage` has no provider filter and asks every provider on
  each run, so the script runs it at most every 5 minutes.
- `omacchiato-airpods` reads `device_productID` from
  `system_profiler SPBluetoothDataType -json` and finds the model in the
  `public.bluetooth-vendor-product-id` tags of
  `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/*/Contents/Info.plist`.
  Those tags start at `0x2014`, so `OLDER` holds `0x200A` and `0x200E`. A
  connected device can also have a BLE entry with the same name and no
  product ID. `system_profiler` reports no battery for AirPods Max, so the
  script fills the gaps from `omacchiato-helper bt battery`, which reads
  `batteryPercentSingle` and the per-side values from IOBluetooth.
  Nothing reports a charging state, so a row says the AirPods are on this
  Mac's USB: `ioreg -arc IOUSBHostDevice` lists them with the Bluetooth
  serial number. It is a row of its own, because a mark on one battery
  read as that side charging. `airpods-control` sets the noise mode through a
  private API, and `install.sh` builds it at a pinned version and SHA-256.
  It answers `no-device` while the cable carries the audio, because it
  controls a device only over Bluetooth.
- The AirPods panel draws Apple's product renders from the private
  `HeadphoneAssets` and `HeadphoneSettingsUI` frameworks, picked by the
  CoreTypes type identifier. If an image name goes away, the panel
  draws an SF Symbol.

## Security notes

`vulnerabilities.md` on upstream's `vulnerabilities` branch is a static
audit from 2026-08-17. Upstream fixed or removed its real findings.
Low items that remain: fixed `/tmp` log paths (a risk only on a Mac with
more than one account), `popen` of the `gesture.json` command strings,
and `omacchiato-karabiner-omniwm`, which sources `apps.conf` as shell.
