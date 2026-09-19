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
- `omacchiato-update` pulls the branch that the local branch tracks, then
  runs `install.sh` again.
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
    -o "$TMPDIR/omacchiato-bar" helper/bar.swift
  cp "$TMPDIR/omacchiato-bar" omacchiato-bar.app/Contents/MacOS/omacchiato-bar
  codesign -f -s "Apple Development" --identifier com.omacchiato.bar omacchiato-bar.app
  launchctl kickstart -k "gui/$(id -u)/com.omacchiato.bar"
  ```

- TCC keys a grant on the code signature. Sign with the same Apple
  Development identity and identifier every time, and the bar, overview
  and helper keep their grants across rebuilds.
- `omacchiato-gesture` is the exception. TCC pins its grant to the exact
  build, so every rebuild needs a new Accessibility grant. `install.sh`
  rebuilds it only when a file in `helper/gesture/` changed.
- There is no test framework. Check shell scripts with `bash -n`.
  `bin/omacchiato-github-prs --self-test` runs that script's asserts. For
  the bar, rebuild, restart and look at it, for example with
  `screencapture -x -R0,0,3000,40 bar.png`.
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

## The bar (`helper/bar.swift`)

- The bar, its popups and its OSDs are one process. `rightOrder` sets
  the pill order: `menubar`, then the plugin pills in file order, then
  the built-in pills.
- `~/.config/omacchiato/bar-pills.conf` holds `<pill> = <mode>` lines:
  `hide`, `icon`, `volume = muted`, `battery = time` and
  `media = <characters>`. The bar reads it once at startup.
- `popup = glass` puts the popup on an `NSGlassEffectView`, which then
  holds the scroll view, so `refreshPopup` resizes the window's content
  view and the glass content view, not a cast to `NSScrollView`.
  `PopupView.draw` skips its background fill in that mode, and Reduce
  transparency turns the mode off.
- `dur()` in `bar.swift` and `overview.swift` returns 0 while Reduce
  motion is on. Pass every animation duration through it.
- The wi-fi popup lists the networks in range. A scan blocks for
  seconds, so it runs off the main thread and calls `refreshPopup`, and
  one answer serves for 20 s, because macOS throttles scans. The scan
  needs the same Location grant as the SSID. A click runs
  `networksetup -setairportnetwork`, which takes the password from the
  system keychain. Any output from it means the join failed, and the
  popup then opens the macOS wi-fi panel. A failed join leaves the
  current network up.
- Plugin pills come from `~/.config/omacchiato/bar-plugins.conf`. A command
  prints a label, or JSON with `label`, `color`, `icon` and `rows`. Row
  keys: `text`, `detail`, `hero`, `dim`, `separator`, `slider`,
  `marker`, `bar`, `color`, `url` and `terminal`. Labels
  are cut at 32 characters. The bar puts `~/.local/bin` and Homebrew
  first on `PATH` and sets `OMACCHIATO_PILL_ICON`. A row also takes `icon`,
  `icon_color`, `run` (a command with no window, then the plugin runs
  again) and `section` (`open`, `closed` or `end`). A row `url` may also
  use `x-apple.systempreferences:`. `foldSections`
  keys a section's open state by header text, because the detail changes.
  `parts` is a list of `icon`, `icon_color` and `label` that the pill
  draws after its own icon and label. Plugin commands run with
  the bar's TCC grants.
- AppKit hit-tests a non-opaque window by alpha, so a pill background
  with zero alpha takes no clicks. `NSColor.clickable` raises zero alpha
  to 0.01.
- Swift initialises top-level globals in order, and a global that reads
  a later global reads zero. Use a computed property instead, as
  `mediaArtSide` does.
- The media pill reads Apple Music only (`com.apple.Music`, notification
  `com.apple.iTunes.playerInfo`). The artwork comes from osascript as
  `«data ...»` hex.
- If `~/.config/omacchiato/theme.conf` holds a `light:X,dark:Y` pair, the
  bar watches `NSApp.effectiveAppearance` and runs `theme-set` with the
  pair and `OMACCHIATO_APPEARANCE`.
- The native menu bar auto-hides (`_HIHideMenuBar`,
  `AutoHideMenuBarOption`), and the bar sits in its place.
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
- Ctrl+F8 (move focus to status menus) needs `.maskSecondaryFn` on the
  event, because F8 is a function key.
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
- The switch runs before other startup code. In the bar it comes right
  after `pillModes`, so it can read only the globals above it. It always
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
  PRs that the user unsubscribed from are hidden. Marks, first match
  wins: 📝 draft, 💥 CI failed or merge conflicts, 🏗️ CI running,
  💬 changes requested or an unresolved thread from someone else,
  ✅ approved, ⏳ waiting for a review.
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
  Nothing reports a charging state, so the plug mark means the AirPods are
  on this Mac's USB: `ioreg -arc IOUSBHostDevice` lists them with the
  Bluetooth serial number. `airpods-control` sets the noise mode through a
  private API, and `install.sh` builds it at a pinned version and SHA-256.
  It answers `no-device` while the cable carries the audio, because it
  controls a device only over Bluetooth.

## Security notes

`vulnerabilities.md` on upstream's `vulnerabilities` branch is a static
audit from 2026-08-17. Upstream fixed or removed its real findings.
Low items that remain: fixed `/tmp` log paths (a risk only on a Mac with
more than one account), `popen` of the `gesture.json` command strings,
and `omacchiato-karabiner-omniwm`, which sources `apps.conf` as shell.
