# omacosy: notes for Claude

omacosy is an omarchy-style tiling desktop for macOS 26: a status bar,
gesture and focus daemons, themes and install scripts around a tiling
window manager. OmniWM is the default window manager, and AeroSpace is
the alternative. README.md describes the features and CONTRIBUTING.md
holds the design rules. This file holds what the code does not show.
Notes about one Mac go in CLAUDE.local.md, which git ignores.

## Repository

- This repo is a fork. `main` tracks `fork/main`
  (github.com/wicksipedia/omacosy). `origin` is the upstream project,
  paulsp94/omacosy. To take upstream work, run
  `git fetch origin && git merge origin/main`.
- `omacosy-update` pulls the branch that the local branch tracks, then
  runs `install.sh` again.
- The clone lives at `~/.local/share/omacosy`, and configs are symlinked
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
    -o "$TMPDIR/omacosy-bar" helper/bar.swift
  cp "$TMPDIR/omacosy-bar" omacosy-bar.app/Contents/MacOS/omacosy-bar
  codesign -f -s "Apple Development" --identifier com.omacosy.bar omacosy-bar.app
  launchctl kickstart -k "gui/$(id -u)/com.omacosy.bar"
  ```

- TCC keys a grant on the code signature. Sign with the same Apple
  Development identity and identifier every time, and the bar, ffm,
  borders, overview and helper keep their grants across rebuilds.
- `omacosy-gesture` is the exception. TCC pins its grant to the exact
  build, so every rebuild needs a new Accessibility grant. `install.sh`
  rebuilds it only when a file in `helper/gesture/` changed.
- There is no test framework. Check shell scripts with `bash -n`.
  `bin/omacosy-github-prs --self-test` runs that script's asserts. For
  the bar, rebuild, restart and look at it, for example with
  `screencapture -x -R0,0,3000,40 bar.png`.
- Logs: `/tmp/omacosy-bar.log` (timings and `tlog` lines),
  `/tmp/omacosy-bar.err`, `/tmp/omacosy-gesture.log`,
  `/tmp/omacosy-overview.log`, `/tmp/omacosy-borders.log`,
  `/tmp/omacosy-ffm.err`, `/tmp/omacosy-ws.log`.
- Launch agents: `com.omacosy.bar`, `com.omacosy.borders`,
  `com.omacosy.gesture`, and `com.omacosy.ffm` (loaded only under
  AeroSpace). Restart one with
  `launchctl kickstart -k "gui/$(id -u)/<label>"`.

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
- `~/.config/omacosy/bar-pills.conf` holds `<pill> = <mode>` lines:
  `hide`, `icon`, `volume = muted`, `battery = time` and
  `media = <characters>`. The bar reads it once at startup.
- Plugin pills come from `~/.config/omacosy/bar-plugins.conf`. A command
  prints a label, or JSON with `label`, `color`, `icon` and `rows`. Row
  keys: `text`, `detail`, `hero`, `dim`, `separator`, `slider`,
  `marker`, `color` and `url` (https only). Labels are cut at 32
  characters. The bar puts `~/.local/bin` and Homebrew first on `PATH`
  and sets `OMACOSY_PILL_ICON`. Plugin commands run with the bar's TCC
  grants.
- AppKit hit-tests a non-opaque window by alpha, so a pill background
  with zero alpha takes no clicks. `NSColor.clickable` raises zero alpha
  to 0.01.
- Swift initialises top-level globals in order, and a global that reads
  a later global reads zero. Use a computed property instead, as
  `mediaArtSide` does.
- The media pill reads Apple Music only (`com.apple.Music`, notification
  `com.apple.iTunes.playerInfo`). The artwork comes from osascript as
  `«data ...»` hex.
- If `~/.config/omacosy/theme.conf` holds a `light:X,dark:Y` pair, the
  bar watches `NSApp.effectiveAppearance` and runs `theme-set` with the
  pair and `OMACOSY_APPEARANCE`.
- The native menu bar auto-hides (`_HIHideMenuBar`,
  `AutoHideMenuBarOption`), and the bar sits in its place.
- With no window manager, the bar still draws on every screen with no
  workspace chips, and looks for a manager again every 5 s. If the bar
  is missing, read `/tmp/omacosy-bar.err` and
  `launchctl print "gui/$(id -u)/com.omacosy.bar"` (runs, last exit code).

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
  follows the macOS appearance, and `OMACOSY_APPEARANCE` overrides
  `AppleInterfaceStyle`. A theme name is a directory in `themes/`, and
  names with `/` or `..` are refused.
- It writes `~/.config/omacosy/theme.conf` and links
  `~/.config/omarchy/current/theme`. The wallpaper changes only when the
  theme changes.
- Ghostty reloads through `omacosy-helper ghostty-reload`: an Apple Event
  to `terminal 1` of the application. It skips `errAENoSuchObject`
  (no window open). A handler error comes back inside the reply, not as
  a thrown error.
- OmniWM's quake terminal reads the Ghostty config only when OmniWM
  reloads its `settings.toml`. So theme-set writes the Ghostty palette
  before it edits OmniWM's settings.
- Under a pair, OmniWM's `[appearance] mode` is `automatic`.

## OmniWM

- `config/omniwm/settings.toml` is a template. `install.sh` copies it
  once to `~/.config/omniwm/settings.toml` and never overwrites the copy.
  OmniWM and theme-set write the copy, and OmniWM reloads it live. Values
  for one desk, such as display pins by `displayUUID`, belong in the
  copy, never in the template.
- Nine workspaces in total, all Niri: 1–5 on the main display and 6–9 on
  the secondary display.
- Gestures: `fingerCount = 3` is the Niri column scroll, which focuses
  the column where it stops. `workspaceSwipeFingerCount = 4` switches
  workspaces. `omacosy-gesture` keeps only the 4-finger vertical swipe
  for the overview. `macos-defaults.sh` turns off the system's 3- and
  4-finger horizontal swipes.
- `followsMouse = false`, so focus follows clicks and keys only.
- OmniWM hotkeys cannot run shell commands.
  `bin/omacosy-karabiner-omniwm install` adds Karabiner rules for those
  chords and replaces its own rules on each run. `install.sh` copies
  `config/karabiner/karabiner.json` over the live file, so it must add
  the OmniWM rules after that copy and after it writes `apps.conf`.
- `omniwmctl` is at `/opt/homebrew/bin/omniwmctl`. `omacosy-omni`
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
- To work on upstream OmniWM (BarutSRB/OmniWM), run
  `./Scripts/dev-tools.sh setup` once. CI runs `make verify` (format,
  lint and build) and
  `LIBRARY_PATH="$(./Scripts/ghostty-preflight.sh print-library-dir)" swift test`.

## install.sh and the window managers

- `WM=aerospace` if an AeroSpace process runs when `install.sh` starts,
  otherwise `WM=omniwm`. Quitting a running window manager strands the
  windows it parked off screen, so the install never replaces a running
  AeroSpace.
- Under OmniWM, the install leaves `com.omacosy.ffm` unloaded and copies
  `config/gesture/config.omniwm.json` to `~/.config/omacosy/gesture.json`.
- `omacosy-wm-switch` does the guarded handover. It records a snapshot,
  starts the new manager, waits for the grants, and then gives a
  90-second "yes" gate that reverts on anything else. It writes the apps
  it installs to the manifest (`~/.local/state/omacosy/manifest`), and
  `uninstall.sh` removes only what the manifest lists.

## Pill scripts in `bin/`

- `omacosy-github-prs [search qualifiers]` lists open PRs by
  `author:@me` through `gh`. An update is an unread GitHub notification.
  PRs that the user unsubscribed from are hidden. Marks, first match
  wins: 📝 draft, 💥 CI failed or merge conflicts, 🏗️ CI running,
  💬 changes requested or an unresolved thread from someone else,
  ✅ approved, ⏳ waiting for a review.
- `omacosy-claude-usage` reads the Claude Code OAuth token from the
  keychain and never refreshes it, because a refresh races Claude Code
  and signs the user out. A request that carries the token follows no
  redirect. The status row reads the "Claude Code" component of
  status.claude.com. The bars are coloured by pace against elapsed time.
  Without the token it uses the payload that `omacosy-claude-statusline`
  saves.

## Security notes

`vulnerabilities.md` on upstream's `vulnerabilities` branch is a static
audit from 2026-08-17. Upstream fixed or removed its real findings.
Low items that remain: fixed `/tmp` log paths (a risk only on a Mac with
more than one account), `popen` of the `gesture.json` command strings,
and `omacosy-karabiner-omniwm`, which sources `apps.conf` as shell.
