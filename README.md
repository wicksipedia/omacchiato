# omacosy

omakase + macOS + cosy. An [omarchy](https://omarchy.org)-style setup
for macOS: tiling window management on [OmniWM](https://github.com/BarutSRB/OmniWM)
with a real Super key, niri columns and Hyprland's dwindle layout, a
status bar built for it (bar, popups, sliders and screen dimming in one
process), trackpad workspace swipes, a Mission-Control-style workspace
overview with live previews, and one theme switch that covers
everything down to the wallpaper. All of it installs from this one
repo.

**The theme follows macOS light and dark mode.** Set a pair once, with
`theme-set light:catppuccin-latte,dark:catppuccin`. When macOS changes
appearance, the bar, OmniWM's focus border, the terminal colours and
the wallpaper change with it. See [Light and dark](#light-and-dark).

![The omacosy desktop — themed bar over the osaka-jade wallpaper](docs/screenshots/desktop.jpg)

The whole environment idles at about **293MB** of memory under OmniWM.
Numbers per process in [Memory use](#memory-use).

Most of it is five small signed binaries (Swift and C) built by the
installer, because several of the existing tools are broken on macOS
26. The details are under [What's inside](#whats-inside).

> Built for macOS 26 (Tahoe), and used daily on macOS 27, on one desk:
> a MacBook Pro plus two external displays. It tries to generalize (display roles instead of
> hardware names, per-display notch detection), but so far it has only
> run on this machine. The permission setup is real work. Issues and
> PRs welcome; support promises are not made.

## Fresh Mac

```sh
git clone https://github.com/wicksipedia/omacosy.git ~/.local/share/omacosy &&
cd ~/.local/share/omacosy && ./install.sh
```

The clone location matters. Configs are symlinked into the repo, and
macOS privacy (TCC) blocks launchd services from reading `~/Documents`,
`~/Desktop` and `~/Downloads`. If you clone there anyway, the installer
falls back to copying configs; that still works, but edits then need an
`install.sh` re-run to apply.

The installer is idempotent. It installs Homebrew if missing, runs
`brew bundle`, compiles the helper binaries, symlinks configs (backing
up anything it would replace), copies OmniWM's settings template once,
adds Karabiner rules for your app choices, hides the native menu bar,
applies the default theme, and starts the services.

See [Permissions](#permissions) for the grants it asks of you, what
each one is used for, and what breaks without it. Karabiner-Elements
also asks you to approve its driver extension.

## Updating

```sh
omacosy-update          # pull, then re-run the installer
omacosy-update --check  # just say whether there is anything new
```

`install.sh` rebuilds only the binaries whose sources changed and
restarts their agents, so an update is a pull plus a re-run, and this
command wraps both. It refuses a clone with local edits, and refuses
one whose branch has diverged, rather than deciding either for you. It
pulls the remote branch that your branch tracks, so a clone of a fork
updates from the fork.

There is no background update check. By default the bar makes one network
call (the weather), and a daemon polling GitHub on a timer would
quietly make that two. Nothing here contacts the network unless you
run it.

## Permissions

A window manager needs broad permissions, so here is the whole list:
every grant, which binary asks, what it is used for, and what you lose
by refusing it. Everything is refusable; the parts that depend on a
grant hide themselves rather than half-work.

| Grant | Who asks | What it does | Without it |
|---|---|---|---|
| **Accessibility** | OmniWM, `omacosy-gesture`, `omacosy-bar` (reads the focused app's menus for the app-pill popup, and reads and clicks other apps' menu bar icons for the menu bar apps pill) | Move, resize and focus other apps' windows. This is the tiling itself, and it is the broadest permission here. | Nothing tiles. Not optional in practice. |
| **Input Monitoring** | Karabiner-Elements, `omacosy-gesture`, and OmniWM | Karabiner reads keys to remap Caps Lock; `omacosy-gesture` reads raw trackpad contacts, because macOS 26 stopped carrying touch data in normal events. | No Super key, no swipe gestures. |
| **Screen Recording** | `omacosy-overview`; OmniWM (optional) | Captures a thumbnail per window for the overview cards, including windows the window manager has stashed offscreen. A screenshot of the visible screen could not see those. OmniWM uses it for its own overview thumbnails, the image of a window you drag, and Hidden Bar icons. | Cards fall back to app icons and titles. OmniWM starts without it. |
| **Bluetooth** | `omacosy-bar` | Reads adapter power and the paired-device list for the bluetooth pill and its menu. | The pill hides itself. |
| **Location** | `omacosy-bar` | Reads **only** the wi-fi network's name, which macOS classes as location data. No coordinate is ever requested; the authorisation itself is what unlocks `CWInterface.ssid()`. | The wi-fi popup's title row reads "wi-fi" instead of your network's name. Everything else is unaffected. |
| **Automation** | `omacosy-bar`, `theme-set`, and the terminal that runs `install.sh` | Apple Events to **Music** (the current track at startup, and its artwork, for the media pill), to **Ghostty** (reloading its colours after a theme change) and to **System Events** (sleep, lock and restart from the Apple menu; setting the wallpaper; adding OmniWM as a login item). | The media pill has no artwork; those menu rows do nothing; OmniWM does not start at login until you add it in System Settings > General > Login Items. |
| **Files and Folders** | `omacosy-bar` | Only if your clone lives in `~/Documents`, `~/Desktop` or `~/Downloads`. The bar reads its palette from the theme directory inside the repo, and macOS walls launchd agents off from those folders. | The bar **hangs at startup** waiting on the prompt. Clone to `~/.local/share/omacosy` and this never comes up. |
| **Keychain** | `omacosy-claude-usage`, only if you add the Claude pill | Reads the Claude Code sign-in token from your login keychain with `security`, to ask Anthropic for your usage. It never writes to the keychain and never refreshes the token. If macOS asks, allow `security` to read the item. | The pill falls back to the statusline payload, which has only the five-hour and weekly windows. |
| **Allow in the Background** | `install.sh` (launch agents for the bar and the gesture daemon) | macOS lists the agents under System Settings > General > Login Items & Extensions. They start at login and restart if they quit. | The parts whose switch is off do not run. |

More on **Location**, because it sounds worse than it is: it buys
exactly one string. The bar requests authorisation and then reads
`ssid()`. It never asks for a position, holds no coordinate and starts
no location updates. Two things are required and neither alone is
enough: measured on macOS 26.3, an unbundled binary reads `nil` however
it is authorised, which is why the bar ships inside a minimal `.app`.
Refuse the grant and you lose the name, nothing else.

### What it does not do

- **No telemetry, no analytics, no crash reporting.** Nothing is sent
  anywhere about you or this machine.
- **One network call by default**: `https://wttr.in/?format=j1` on a
  long timer, for the weather pill. wttr.in infers your city from the IP
  the request arrives on; no coordinates are gathered or sent, and the
  bar holds no location API. Delete the weather pill and nothing leaves
  the machine. The example pills that you can add in `bar-plugins.conf`
  contact more hosts: the Claude pill calls `api.anthropic.com` and
  `status.claude.com`, and the GitHub pill calls `api.github.com`
  through `gh`.
- **omacosy's own binaries never run as root.** `install.sh` uses no
  sudo, installs no LaunchDaemon, and every helper it builds runs as
  you, in your login session.
- **Karabiner-Elements does run as root, and you should know that
  before installing.** It is a Homebrew dependency here, purely to turn
  Caps Lock into Super. It ships a DriverKit system extension plus
  daemons that run as root (`Karabiner-VirtualHIDDevice-Daemon`,
  `Karabiner-Core-Service`); that is what the driver-extension approval
  during install is. It is the most privileged thing this repo puts on
  your Mac, and it is third-party. Skip it if that trade is wrong for
  you; you lose the Super key and keep everything else.
- **Nothing here reads your keystrokes.** No omacosy binary opens a
  keyboard event tap. Only Karabiner sees keys, which is inherent to
  remapping one. `omacosy-gesture`'s event tap is gesture-only and
  listen-only (`1 << NSEventTypeGesture`, `kCGEventTapOptionListenOnly`),
  so it cannot see or alter a keystroke. Debug logs
  (`/tmp/omacosy-*.log`) carry window titles, app names and workspace
  numbers, never input. The menu bar apps pill posts mouse clicks and
  one key chord (Ctrl+F8), and reads no keys.

Grants are tied to a binary's code signature. With an Apple Development
identity present, `install.sh` signs every helper with a stable
identifier so rebuilds keep their grants; without one, macOS treats
each rebuild as a new app and you re-grant after every install.

## App choices

Keybindings launch apps defined in `config/apps.conf`. Defaults are
Ghostty, Safari, Spotify, Slack (terminal, browser, music, messenger).
Override any of them in `config/apps.local.conf` (gitignored), then
re-run `install.sh`:

```sh
# config/apps.local.conf — your picks win over apps.conf
TERMINAL=Korren
BROWSER=Arc
```

The music app only sets what `Super+shift+m` opens. The media pill
reads Apple Music whichever app you pick.

Your personal shell config belongs in `~/.zshrc.local`; the repo's
`zshrc` wires the CLI stack and sources it. Put an alias or setting
that must override the CLI stack in `~/.zshrc.after`, which `zshrc`
sources last.

## What's inside

| Piece | Tool | Config |
|---|---|---|
| Tiling WM | [OmniWM](https://github.com/BarutSRB/OmniWM) | `config/omniwm/settings.toml` (a template, copied once to `~/.config/omniwm/settings.toml`) |
| Super key | [Karabiner](https://karabiner-elements.pqrs.org) (Caps Lock → cmd+ctrl+alt) | `config/karabiner/` (copied, not symlinked — TCC) |
| App and script chords | Karabiner rules, because OmniWM's hotkeys cannot run commands | `bin/omacosy-karabiner-omniwm` |
| Status bar, popups, shade | `omacosy-bar` (self-compiled launchd agent, one process draws all of it) | `helper/bar.swift` |
| Focus border | OmniWM's own, coloured by `theme-set` | `[borders]` in `config/omniwm/settings.toml` |
| Trackpad gestures | OmniWM's swipes for workspaces and columns; `omacosy-gesture` (self-compiled launchd agent; engine absorbed from [aerospace-swipe](https://github.com/acsandmann/aerospace-swipe), MIT) for the overview swipe | `config/omniwm/settings.toml`, `helper/gesture/`, `config/gesture/` (live copy: `~/.config/omacosy/gesture.json`) |
| Workspace overview | `omacosy-overview` (self-compiled resident daemon) | `helper/overview.swift` |
| Dwindle split direction | OmniWM's native dwindle, plus a preselect in `omacosy-spawn` (omarchy's right/below insertion) | `bin/omacosy-spawn`, `helper/gesture/omnicli.c` |
| Workspace navigation | `omacosy-ws` and the Karabiner chords, riding `omacosy-omni`, a held-socket IPC client | `bin/`, `helper/gesture/omniwm.c` |
| Terminal look & spawn size | Ghostty (hidden titlebar; new windows spawn small so tiling never flashes full-screen) | `config/ghostty/config` |
| Park/restore the stack | `omacosy-toggle` | `bin/omacosy-toggle` |
| System glue | `omacosy-helper` (self-compiled) | `helper/main.swift` |
| Prompt | starship | `config/starship.toml` |
| Shell | zsh | `zsh/zshrc` + your `~/.zshrc.local` and `~/.zshrc.after` |
| CLI stack | fzf, eza, zoxide, ripgrep, bat, lazygit, btop | wired in `zsh/zshrc` |

Why so much of it is self-built:

- **aerospace-swipe** broke because CGEvent taps stopped carrying
  multi-touch data on macOS 26.3. We fixed it (raw MultitouchSupport
  frames) and offered the fixes upstream as
  [#29](https://github.com/acsandmann/aerospace-swipe/pull/29) and
  [#30](https://github.com/acsandmann/aerospace-swipe/pull/30); once
  the daemon carried more of our patches than upstream commits, the
  engine moved in-tree as `omacosy-gesture` (MIT notice kept).
- **Mission Control** cannot see OmniWM's workspaces, which are not
  Spaces, so a workspace overview cannot be had any other way than
  `omacosy-overview` capturing them itself.
- **`omacosy-helper`** covers wallpaper setting (System Events
  scripting half-broke in macOS 14+), CoreAudio output switching,
  IOBluetooth control, cursor position and per-display notch
  detection.
- **`omacosy-bar`** holds the window model in memory and subscribes to
  the system's own publishers: SkyLight for window churn, IOBluetooth
  for connects, SCDynamicStore for the network, IOPS for battery,
  CoreAudio for volume, DisplayServices for brightness, Apple Music's own
  broadcast for the track. It polls for nothing macOS announces; its
  only timers are the weather fetch and the clock. A workspace switch
  repaints in 2.5 ms because it asks no one anything; the shell bar it
  replaced took 164 ms to answer the same event.

## The bar

One process draws all of it: bar, popups and sliders are surfaces of
`helper/bar.swift`. Transparent bar, everything a flat radius-4 pill.
A popup stays open while the pointer is anywhere in the bar or the
popup, and closes when it is in neither. OmniWM keeps a strip at the
top of each display free for the bar (`[gaps.outer] top`), and
fullscreen windows keep out of it too (`fullscreenUsesOuterGaps`), so
the bar stays on screen.

With no window manager running, the bar hides itself when a window
takes the whole display, and comes back if you put the pointer on the
very top edge, so brightness and volume stay reachable mid-film
without leaving fullscreen. The climb happens only when a fullscreen
window actually covers the bar — otherwise the top edge belongs to the
auto-hidden native menu bar, which reveals ABOVE the bar and stays
clickable (app menus were unreachable before that fix). It drops back
behind everything when the pointer leaves.

If the native menu bar ever gets stuck revealed over the bar (a
Tahoe bug, most often poked by a Focus mode's menu-bar icon),
`killall SystemUIServer` resets it.

### Choosing pills

`~/.config/omacosy/bar-pills.conf` sets what each right-cluster pill does,
one `<name> = <mode>` per line. The names are `menubar`, `weather`,
`wifi`, `bluetooth`, `brightness`, `volume`, `mic`, `battery`, `clock` and
`activity`.
The modes are `hide` and `icon`. `volume` also takes `muted`, and `battery`
takes `time`. Lines starting with `#` are comments.

```
weather = hide
battery = icon
```

`hide` also skips the pill's provider, so hiding `weather` stops the
wttr.in fetches and hiding `bluetooth` never touches the Bluetooth grant.
`icon` drops the label and keeps the glyph; it is ignored on a pill with no
icon, because the weather pill keeps its glyph in the label. `volume =
muted` draws the volume pill only while the output device is muted or at
zero, as a red icon, the same way the microphone pill works.

`battery = time` shows only the battery icon on AC power. On battery it adds
the time left: whole hours, rounded down, or minutes when less than an hour
remains.

`media = <characters>` sets how much of the track title the music pill
shows before the title scrolls. The default is 28. A display with a notch
uses five sevenths of the number, so 20 by default.

The file is read once at startup, so restart the bar to apply an edit:

```sh
launchctl kickstart -k "gui/$(id -u)/com.omacosy.bar"
```

### Adding pills

`~/.config/omacosy/bar-plugins.conf` adds pills without a rebuild. Each
`[name]` section takes a `command`, run by `/bin/sh -c`, whose first line
of stdout becomes the label. `interval` is the gap between runs in seconds
(minimum 1, default 30) and `icon` is an optional glyph.

```
[cpu]
command = ps -A -o %cpu | awk '{s+=$1} END {printf "%.0f%%", s/8}'
interval = 5
```

Plugin pills sit at the left of the right cluster, in file order. Clicking
one runs its command again straight away. A name that matches a built-in
pill is ignored, and so is a section with no `command`. Labels are cut at
32 characters, because the cluster is laid out from the right edge inwards
and a long one would push the other pills off screen.

The command is passed to `sh` as an argument, never spliced into a shell
string. It runs with `~/.local/bin` and the Homebrew prefixes ahead of
`PATH`, so a plugin can name a script or a `brew` binary directly. Like the
rest of this file it is read once at startup.


A command that prints a JSON object instead of a line can also set the
pill's colour and give it a popup:

```json
{
  "label": "10% - 2h 6m",
  "color": "green",
  "rows": [
    {"text": "Claude usage", "hero": true},
    {"separator": true},
    {"text": "Session", "detail": "10%"},
    {"text": "5-hour window", "slider": 0.1, "marker": 0.58},
    {"text": "Resets in 2h 6m", "dim": true}
  ]
}
```

`color` is one of `accent`, `label`, `muted`, `red`, `green` or `yellow`,
resolved from the current theme, and tints both the icon and the label. A
row takes the same `color` names, and a row with an `https` `url` opens it
when clicked. A row with a `terminal` command opens your terminal on that
command instead, the way the activity pill opens btop; it runs with the same
trust as the plugin command that printed it. A
colour emoji draws its own colours and ignores the icon tint, which is why
the label carries it too. `icon` overrides the config. A `slider` between 0
and 1 draws a progress track, and on a slider row `text` is a short
right-aligned readout rather than a label, so put the label on the row
above. On a slider row, `color` sets the fill. A `marker` between 0 and 1
draws a tick across the track. The
Claude pill uses it to show how far through each usage window you are. Give a pill rows and clicking it opens the popup instead of
re-running the command.

A pill draws nothing while its label and its icon are both empty, which is
how a pill reports a state worth no space at all. Send `"icon": ""` to hide
one, because an absent `icon` falls back to the glyph the config names.

`omacosy-claude-usage` ships as an example. It colours the pill by how far
into the five-hour window you are, and opens a popup with that window, the
weekly one, each per-model weekly window, and any extra usage credits.
Each bar has a tick at the share of its window that has passed, and its
colour compares the two. It is green at or near an even pace, yellow more
than 5 points ahead, and red more than 20 points ahead or at 90% used.

The first row reports the status of the Claude Code component on
status.claude.com and opens the status page when clicked. It ignores the
page's overall rating, which also drops when another Claude product has a
problem. When an open incident affects Claude Code, the rows below it show
the incident's title, its state and the time of its latest update. A click
on those rows opens the incident page.

The last row opens `tokscale` in a terminal with `npx tokscale`, which
breaks your token use down by model, day and month.

It reads Anthropic's OAuth usage endpoint with the Claude CLI's own token,
caching the answer for five minutes, because only that endpoint carries the
per-model and credit figures. It never refreshes the token and never writes
to the credential store: a third party rewriting the CLI's own credentials
can race Claude Code and log you out.

When the token is expired or the network is gone it falls back to the
statusline payload saved by `omacosy-claude-statusline`, which needs
neither. That payload has only the five-hour and weekly windows, and after
a window rolls over with no session running it reports `--` rather than a
percentage for a window that no longer exists.

To save that payload, make `omacosy-claude-statusline` the statusline
command in `~/.claude/settings.json`, followed by the statusline command
you already use. With nothing after it, the script only saves the
payload.

```json
"statusLine": {
  "type": "command",
  "command": "$HOME/.local/share/omacosy/bin/omacosy-claude-statusline ~/.claude/statusline.sh"
}
```

### GitHub pull requests pill

`omacosy-github-prs` lists the open pull requests you authored. It needs
the GitHub CLI, signed in with `gh auth login`. The pill shows how many
PRs are open and adds `!` when one of them has an update. The popup groups
the PRs by repository. Each PR row starts with a mark for its state, and
the line under it says what the PR waits for. A PR whose base branch is
another PR in the list sits under that one, indented and marked `↳`.
Clicking either line opens the PR. To drop a PR from the list,
unsubscribe from its notifications on GitHub.

```
[github]
command = omacosy-github-prs -repo:owner/bots
interval = 120
```

Arguments are extra GitHub search qualifiers. `-repo:owner/name` leaves
out a repository of automated PRs, and `org:name` keeps one organisation.
For the icon, the Nerd Font pull request glyph is U+F407.

Each PR gets one mark, for what it needs next. When more than one
applies, the first in this list wins:

- 📝 a draft
- 💥 CI failed, or the branch has merge conflicts
- 🏗️ CI is running
- 💬 feedback to resolve: changes requested, or a review thread from
  someone else that nobody has resolved
- ✅ ready to merge: approved, with passing checks and no conflicts
- ⏳ waiting for a review

The pill turns red while CI fails on any open PR.

An update is an unread GitHub notification on the PR. GitHub marks the
notification read when you open the PR, so the `!` goes at the next run
after you look. A PR merged (🟣) or closed (⚫) in the last week stays in
the list while its notification is unread.

To find those notifications the script reads every page of your unread
inbox, about half a second per 50, while the search runs. When GitHub is
out of reach, the popup keeps the last list and says when it was fetched.

### Microphone and Keep Awake pills

`omacosy-keep-awake` is another example pill. It shows a cup while
something is deliberately keeping the Mac awake, and hides otherwise. It
names no particular app: it reads the power assertions, and ignores the
ones held from the system's own directories, because powerd, coreaudiod
and sharingd hold one as a matter of course. It also ignores an assertion
held by a coding agent, which is a short lease on the machine rather than
a setting you left on. Reading the assertion rather than an app's saved
setting means it still reports the truth after the app holding it quits.
Clicking it lists what is holding the Mac awake and how long each has held
it.

The microphone pill is not a plugin. It is built in, because CoreAudio
costs about 65 ms to open in a fresh process and the bar already holds it
open for the volume pill. It shows a struck-through microphone while the
default input device is muted and nothing at all otherwise, and it follows
a property listener, so it changes the moment the microphone does rather
than at the next poll. For the same on the output side, set
`volume = muted` in `bar-pills.conf`.

### Workspace icons

You can set workspace icons in the optional
`~/.config/omacosy/workspace-icons.conf` file. Each non-comment line has one
workspace name, an equals sign, and either one Unicode scalar or a reverse-DNS
application bundle identifier.

```
1 = ★
14 = ◆

4 = com.apple.Safari
```

The bar first uses a configured icon. It then shows the icons of up to three
apps on that workspace, fanned like a hand of cards, with the app in the
leftmost window in front. Otherwise it shows the workspace's last digit.
Exact workspace names win. In this example, workspace `14` uses `◆`, not the `4` shorthand.
The shorthand applies only to multi-digit, all-numeric workspace names ending
in `1` through `9` when they have no valid exact declaration.

The bar reads the file once at startup. To apply an edit, restart it with:

```sh
launchctl kickstart -k "gui/$(id -u)/com.omacosy.bar"
```

Malformed lines are logged and ignored. A well-formed bundle identifier that
does not resolve to an installed app is unavailable. It blocks shorthand for
that exact workspace, then the bar falls back to the app icons or the digit.
Image paths are unsupported because the bar resolves configured app icons at
startup and does no config-file or image-file I/O while it draws.

- **Apple menu**: the REAL one, read over Accessibility — About This
  Mac, System Settings, Recent Items (drills in, with app and
  file-type icons resolved locally since AX exposes none), Force Quit,
  the power verbs — plus omacosy's Next Theme at the bottom. Hidden
  hold-Option duplicates are collapsed; falls back to a hand-rolled
  list without the Accessibility grant.
- **App menus**: clicking the front-app pill drops that app's actual
  menu bar into a popup — File/Edit/… drill into their real items,
  nested submenus included, and clicking a leaf performs it directly
  via AXPress with no native menu ever appearing. Shortcuts sit
  right-aligned; enabled-state is not rendered because apps validate
  menu items only when a menu opens, so closed-menu reads lie. Menus
  taller than the screen scroll. The one thing the auto-hidden native
  bar still owned, gone.
- **Workspaces**: one segmented capsule per monitor showing only that
  monitor's workspaces; an accent dot under the one on show; click to jump.
- **Media**: album art + artist and track (Apple Music). A title too
  long for the pill scrolls, moved by Core Animation so the bar redraws
  nothing. Click to open Music. Centered on flat displays, left cluster
  on notched ones (per-display notch detection via
  `NSScreen.safeAreaInsets`), hidden when Music isn't running.
- **Menu bar apps**: the grid pill lists the third-party apps that have an
  icon in the hidden macOS menu bar. A click on a row gives that icon a real
  click: the pointer moves to the top edge so the menu bar slides in (about
  0.25 s), the bar clicks the icon, and the pointer moves back. An icon that
  the notch hides has nowhere to click, so its row says `opens app` and opens
  the app instead. `Show menu bar ⌃F8` shows the menu bar with keyboard focus
  on its icons. The bar does not use Accessibility's `AXPress` here: a press
  on an icon behind the notch left the menu bar stuck on screen until that
  app quit.
- **Bluetooth**: device menu (click to connect/disconnect), power
  toggle.
- **WiFi**: the pill is the icon alone; the popup names the network and
  adds ip and router, signal with a verdict, link rate and security
  generation, channel with its band and width. The name is in the popup
  because an SSID can be arbitrarily wide, and on a notched display a
  long one pushed the right cluster under the notch. The name needs the
  Location grant (see [Permissions](#permissions)).
- **Weather**: wttr.in, cached details popup.
- **Volume**: scroll adjusts, click opens slider + output-device menu,
  right-click mutes.
- **Brightness**: scroll adjusts, click opens a slider (DisplayServices,
  no deps). Scrolling past 0 keeps going: a **shade** dims the display
  below its hardware minimum by scaling gamma, so there is no overlay
  window in the z-order and screenshots come out normal. It survives
  sleep/wake and it reaches external displays, which have no backlight
  API. Gamma is reset when the setting process exits, so a crash or an
  uninstall restores the screen by itself.
- **Battery**: charge and state, live draw in watts, the adapter's
  wattage, time to full or empty when the rate is settled, and health as
  the ratio of full charge to design capacity, which keeps moving after
  Apple's own figure has rounded to 100%. A leaf or a speedometer joins
  the cell in low or high power mode, and a thermal row appears once the
  system reports anything above nominal. Low power mode publishes a
  change, so it is immediate. High power mode publishes nothing, not even
  when you leave it, so it is re-read on the minute tick and again
  whenever the popup opens.
- **Clock** (calendar popup) / **Activity** (floating btop).

## Keybindings — Super = hold Caps Lock

Karabiner remaps Caps Lock to `cmd+ctrl+alt` (a combo macOS never
uses), so omarchy's scheme works letter-for-letter without breaking
typing or app shortcuts. Caps Lock tapped alone is Escape.

| Chord | Action |
|---|---|
| **Navigation** | |
| `Super+1..9` | switch to workspace N |
| `Super+tab` / `Super+shift+tab` | next / previous workspace on the display under the cursor |
| `Super+b` | back and forth between the last two workspaces |
| `Alt+tab` | focus the previously focused window |
| `Ctrl+Alt+tab` / `Ctrl+Alt+shift+tab` | cycle focus between displays. The cursor moves with focus, so `Super+tab` then acts on that display. A display with no workspace is skipped |
| `Super+arrows` | focus the window in that direction |
| `Super+o` | workspace overview |
| **Moving windows** | |
| `Super+shift+arrows` | **swap** tiles (`ctrl+opt+shift+arrows` stacks into the neighbor as a group instead) |
| `Super+shift+1..9` | move the window to workspace N and follow it |
| `Super+shift+o` | throw the window to the workspace on show on the next display |
| `Super+shift+space` | throw every window of the workspace to the next display's workspace |
| **Layout** | |
| `Super+w` | close window |
| `Super+t` | toggle floating |
| `Super+s` | raise every floating window |
| `Super+backtick` | show or hide scratchpad 1 |
| `Super+shift+backtick` | send the focused window to scratchpad 1 |
| `Super+j` | toggle split direction (dwindle) |
| `Option+shift+l` | switch the workspace between niri and dwindle |
| `Super+-` / `Super+=` | narrower / wider: the column under niri, the split under dwindle |
| `Super+shift+-` / `Super+shift+=` | shorter / taller, in either layout |
| `Super+f` | fullscreen inside the workspace; the bar strip stays, and swipes still reach it |
| `Super+n` | native macOS fullscreen (a separate Space — outside the workspace model, avoid unless an app needs it) |
| **Apps and system** | |
| `Super+enter` / `Super+shift+enter` | terminal / browser |
| `Super+space` | OmniWM's command palette |
| `Cmd+space` | Raycast (give it this hotkey in Raycast's settings) |
| `Super+shift+f` / `+m` / `+g` | files / music / messenger (set in `apps.conf`) |
| `Super+shift+e` / `+c` / `+y` | Outlook / Teams / a YouTube web app |
| `Super+shift+t` | next theme (one theme, so a light/dark pair stops) |
| `Super+shift+b` | next wallpaper of the current theme |
| `Super+shift+l` | lock the screen |
| `Super+k` | keybinding cheatsheet (this table, rendered from the config) |

![The keybinding cheatsheet — every binding, read from OmniWM's settings.toml and omacosy's Karabiner rules](docs/screenshots/cheatsheet.jpg)

Screenshots, clipboard and app switching stay macOS's own
(`Cmd+Shift+3/4/5`, `Cmd+C/V`, `Cmd+Tab`). `Alt+Tab` above works on
windows, which macOS's own switcher does not.

**herdr.** If herdr is installed and `~/.config/herdr/config.toml` has
no `[keys]` table, `install.sh` adds the keys in
`config/herdr/keys.toml`. They need no `ctrl+b` prefix, and the prefix
keys still work.

| Chord | Action |
|---|---|
| `Ctrl+Alt+h/j/k/l` | focus the pane in that direction |
| `Ctrl+Alt+d` / `Ctrl+Alt+shift+d` | split right / split down |
| `Ctrl+Alt+z` | zoom the pane |
| `Ctrl+Alt+[` / `Ctrl+Alt+]` | previous / next tab |
| `Ctrl+Alt+t` / `Ctrl+Alt+w` | new tab / close tab |
| `Ctrl+Alt+shift+t` | rename tab |
| `Ctrl+Alt+up` / `Ctrl+Alt+down` | previous / next space |
| `Ctrl+Alt+g` | new worktree off a branch you pick (herdr's own dialog uses HEAD) |

**On the modifier space.** omarchy layers `Super+Ctrl` and `Super+Alt`
on top of `Super`. This setup cannot: Super IS `cmd+ctrl+alt`, so those
modifiers are already spent and Shift is the only layer left, two
against omarchy's four. Bindings that would collide are re-homed by
mnemonic (lock is `Super+Shift+L`, not `Super+Ctrl+L`), and the
overflow moves to Option chords, such as `Option+Shift+L` for the
layout toggle.

There are nine workspaces in total, not a set per display (details
under [OmniWM](#omniwm)). `Super+N` switches to workspace N,
`Super+Shift+N` moves the window there, and `Super+Tab` cycles the
workspaces of the display under the cursor. Windows open on the
workspace you're on; nothing is auto-assigned by app.

**Unplugging keeps every workspace reachable.** A workspace whose
display is gone moves to the nearest display, and `Super+N` still
reaches it. When one display remains, the bar also runs
`omacosy-ws-collapse`, which moves the windows on any two-digit
workspace into the lowest free 1–9 slot and records where each came
from. Plug the display back in and they go home individually, so
anything you opened while undocked stays put.

## Themes

`theme-set <name>` switches everything at once: the bar, OmniWM's focus
border, the wallpaper on every display, Ghostty, and any terminal that
follows omarchy's `~/.config/omarchy/current/theme` convention (the
author's does). `Super+Shift+T` cycles. `theme-set
light:<name>,dark:<name>` sets a pair instead, and the desktop then
follows macOS light and dark mode on its own; see
[Light and dark](#light-and-dark).

Each theme ships omarchy's full wallpaper set. `Super+Shift+B` (or
`theme-bg-next`) cycles through them; `theme-bg-next <path>` sets any
image you like. Switching themes restarts at the theme's first
wallpaper.

Themes: `tokyo-night`, `catppuccin`, `catppuccin-latte`, `gruvbox`,
`osaka-jade`. Each
`themes/<name>/` holds `colors.toml` (omarchy's 22-color palette),
`sketchybar.sh` / `borders.sh` (bar and focus-border colors; the file
keeps its omarchy name and format, and the border uses the theme
accent, omarchy's own convention), and `backgrounds/` (wallpapers from
omarchy's MIT-licensed theme packs). Copy a directory to add one.

Every colour in `sketchybar.sh` is `0xAARRGGBB`, so the leading byte sets
opacity. `ITEM_BG` fills the pills on the bar and `ROW_BG` fills a
highlighted row or a slider track inside a popup. They are separate
because a pill that reads well at half opacity over a wallpaper is too
faint for a track inside a solid popup. A theme that names only `ITEM_BG`
gets it for both, which is what they were before the split.

`theme-set` also writes `[appearance] mode` in OmniWM's `settings.toml`.
It reads the luminance of the theme's `background` colour, so a light
theme gets light chrome without extra configuration.

`theme-set` also writes `~/.config/omacosy/ghostty-theme` from the palette
and asks Ghostty to reload. The Ghostty config includes that file, so the
terminal follows the desktop theme. Do not set `theme` in
`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`: macOS
config files load after the XDG one, so it would win.

The reload goes through `omacosy-helper ghostty-reload`, not `SIGUSR2`.
Ghostty reloads on that signal only on Linux; on macOS it accepts the
signal and ignores it, which looks like success from the sending side. The
helper aims one Apple Event at each Ghostty process, because omacosy opens
an instance per window while AppleScript addresses an app by bundle and so
would reach only one of them.

OmniWM's quake terminal reads the same Ghostty config files, but it is not a
Ghostty process. It re-reads them when OmniWM reloads `settings.toml`, which
`theme-set` edits for the focus border, so `theme-set` writes the Ghostty
file first.

herdr follows too. `theme-set` writes `[theme] name` in
`~/.config/herdr/config.toml` and runs `herdr server reload-config`. It
does not keep a copy of herdr's theme list: it writes this theme's name,
and an unknown one comes back as a reload diagnostic, which falls back to
herdr's `terminal` theme. Prefer a real match where one exists. `terminal`
takes the host palette, but reads its text colour from the ANSI white
slot, so on a light theme the sidebar turns pale grey.

### Light and dark

`theme-set` also takes a light/dark pair, in the same syntax as Ghostty's
`theme` key:

```
theme-set light:catppuccin-latte,dark:catppuccin
```

With a pair, the desktop follows the macOS appearance. `theme-set`
stores the pair in `~/.config/omacosy/theme.conf` and applies the half
that matches the current appearance. The bar watches the system
appearance, and when it changes, the bar runs `theme-set` with the pair
again: the bar, OmniWM's focus border, Ghostty, herdr and the wallpaper
switch together. The bar also runs it once when it starts. A pair sets
OmniWM's `[appearance] mode` to `automatic`, so OmniWM's own chrome
follows the system directly.

`theme-set` with one name stores that name instead, and so does
`Super+Shift+T`, which runs `theme-next` to set the next theme by name.
Either one stops the following until you set a pair again.

On the first switch, macOS asks whether omacosy-bar can control Ghostty.
If you do not allow it, the terminal keeps its old colours.

## Tiling: niri and dwindle

![Three terminals in a dwindle layout — README, git log and btop — accent border ring on the focused one](docs/screenshots/tiling.jpg)

Workspaces start in OmniWM's niri layout, which scrolls a row of
columns, and `Option+Shift+L` switches one workspace to dwindle.
Hyprland's dwindle splits the focused window along its own longer edge:
a new window lands beside a wide window and below a tall one. That is
the omarchy feel, and on a 3440-wide display it is also the difference
between a usable third window and three narrow strips.

OmniWM's dwindle puts the new window on a different side from
omarchy's. With `smartSplit` off, a new window goes right in a
horizontal split and above in a vertical one, while Hyprland's
`force_split=2` puts it right or below. So `omacosy-spawn`, which the
terminal chord runs, preselects the side for each new window. It
applies OmniWM's own orientation rule (height × `splitWidthMultiplier`
greater than width means a vertical split) to the focused tile, and
asks for down or right. Spawns are serialized, so a burst of
`Super+Enter` becomes a clean staircase instead of splitting the same
cell over and over.

Floats sink behind tiles, because macOS orders windows per app, not
per window: a float sinks behind whichever app you focus next, and
pinning it would need a private call with SIP off. **Super+S** raises
every floating window.

## OmniWM

[OmniWM](https://github.com/BarutSRB/OmniWM) is the window manager: a
signed and notarized tiling WM with niri and dwindle layouts.
`install.sh` installs it with Homebrew, starts it, and adds it as a
login item. OmniWM does not start while another window manager runs,
so quit any other one first.

The rest of omacosy is built around it. The bar and the overview (with
type-to-search) read its workspaces over IPC, and `theme-set` colours
its focus border and sets its light or dark chrome. OmniWM's hotkeys
cannot run shell commands, so the chords that open apps or run
omacosy's scripts are Karabiner rules, which `install.sh` adds through
`omacosy-karabiner-omniwm`. `Super+Space` opens OmniWM's command
palette.

`Super+N`/`Hyper+N` route through Karabiner into `omacosy-omni` (a
held-socket IPC client) so slots resolve on the display under your
cursor — OmniWM's native hotkeys are name-global and would always hit
the main set — at the cost of a shell command per chord (the IPC round
trip itself takes about 4 ms). `Hyper+arrows` swap tiles; OmniWM's own
directional move *stacks* windows into a group, which stays available
on `ctrl+opt+shift+arrows`.

Workspaces use OmniWM's niri layout, which scrolls a row of columns.
`Option+Shift+L` toggles one workspace to dwindle. The resize chords
work in both layouts: each one tries the niri command first, and that
command fails on a dwindle workspace, so the dwindle one runs instead.
Keyboard focus also moves the cursor (`moveMouseToFocusedWindow`),
because `Super+Tab` and the throws act on the display under the cursor.

This fork runs OmniWM with nine workspaces in total, not a set per
display, so `Super+N` always reaches workspace N. The template in
`config/omniwm/settings.toml` puts 1–5 on the main display and 6–9 on
the secondary one. `install.sh` copies it to
`~/.config/omniwm/settings.toml` once, and OmniWM and `theme-set` edit
that local copy, so settings for one desk stay out of the repo. To pin
workspaces to one display, set `type = "specificDisplay"` and add the
display's `displayUUID` and `name` in the local copy. When a pinned
display is missing, OmniWM moves its workspaces to the nearest display. `Super+Tab` cycles the workspaces on the display
under the cursor. `Super+Shift+O` and `Super+Shift+Space` throw to the
workspace on show on the next display to the right.

Honesty section: OmniWM is daily-driven on a docked multi-monitor desk,
and docs/omniwm-port.md carries a ledger of upstream quirks found
while porting — read it before assuming a weird layout is omacosy's
fault.

## Focus and swipes

Focus follows clicks and keys, because `followsMouse` is off in
`config/omniwm/settings.toml`. When a key moves focus, OmniWM moves the
pointer to the focused window.

OmniWM's own swipes do the horizontal work. A 4-finger swipe left or
right switches workspaces. In a Niri workspace, a 3-finger swipe left
or right scrolls the columns and focuses the column it stops on, and a
fast flick can pass more than one column. `omacosy-gesture` keeps only
the 4-finger swipe up for the overview. `macos-defaults.sh` turns off
the system's 4-finger gestures, so Mission Control never fights them,
and its 3-finger swipe between full-screen apps; `uninstall.sh`
restores them. The finger counts are in the `[gestures]` table of
`config/omniwm/settings.toml`. An existing
`~/.config/omniwm/settings.toml` keeps its own values, so set
`fingerCount = 3` and `workspaceSwipeFingerCount = 4` there to match.

## Workspace overview

![Workspace overview — live preview cards over the zoomed-out wallpaper, chips for empty workspaces](docs/screenshots/overview.jpg)

4-finger **swipe up**: the wallpaper breathes in behind a dim wash and
every non-empty workspace of the cursor's monitor gets a card
(per-display Mission Control semantics), with live window previews
(ScreenCaptureKit, composed into the tile layout), app icons, and an
accent ring on the focused workspace. Click a card or press its digit
to jump; empty workspaces show as small chips, and digits work for them
too. **Swipe down**, Esc, or a backdrop click dismisses. It is a
resident daemon, so it opens instantly.

**Type to search** while it is open: a search pill filters cards to
matching window titles and apps as you type, `Enter` jumps to the
first hit, `Esc` clears the filter before it closes the overview.
Digits type into an active filter instead of switching, so numeric
titles stay reachable.

**Drag a card** to reorganize: the row makes room as you move, and the
drop slides everything between the old and new position over by one.
A workspace's name is its position, so what actually moves is its
windows, which means a split layout inside a moved workspace comes back
as a flat row. Dropping a card on an empty chip moves that workspace
there instead.

## Parking the setup

`omacosy-toggle off` returns to a vanilla Mac in one command (OmniWM
quits, and the gesture daemon and the bar stop) without uninstalling;
`omacosy-toggle on` brings everything back. No argument flips.

## Memory use

About **293MB** of physical footprint (what Activity Monitor calls
Memory) across OmniWM, the bar, the overview daemon, the gesture daemon
and Karabiner's two user processes. The measurement, on 2026-09-14
under OmniWM and docked to two external displays, came to 306MB. That
figure included 13MB for `omacosy-borders`, which omacosy no longer
runs, so 293MB is what remains. Footprint is the number to compare:
resident set size counts each process's share of the shared system
frameworks more than once. Karabiner's three root processes need root
to measure, so they are not in the total; their resident size is about
39MB. Largest first:

| | footprint |
|---|---|
| OmniWM | 169MB |
| Karabiner (2 user processes) | 47MB |
| `omacosy-bar` | 42MB |
| `omacosy-overview` | 24MB |
| `omacosy-gesture` | 11MB |

The figures move with uptime. `omacosy-overview` caches a
half-resolution capture per window shown, so it starts near 9MB and
settles between about 25MB and 37MB. It plateaus there rather than
climbing, because it filters the cache to the visible set on each open.
Packaging the bar as an `.app` (which is what unlocks the wi-fi network
name) cost about 1MB; the bundle is a directory and an Info.plist, not a
second copy of anything.

## Back to a normal Mac

```sh
./uninstall.sh
```

Manifest-driven: `install.sh` records what this machine actually gained
(Homebrew packages that weren't already present, cloned repos, every
`defaults` key's prior value), and `uninstall.sh` removes and restores
exactly that. Tools and settings you had before omacosy are never
touched. Pre-manifest installs fall back to a conservative teardown
that leaves all Homebrew packages in place.

## License & credits

MIT (see `LICENSE`). Standing on: [omarchy](https://omarchy.org)
(the whole idea, plus MIT-licensed theme palettes and wallpapers),
[OmniWM](https://github.com/BarutSRB/OmniWM),
[Karabiner-Elements](https://karabiner-elements.pqrs.org),
[aerospace-swipe](https://github.com/acsandmann/aerospace-swipe) (MIT;
its gesture engine lives on here as `omacosy-gesture`, notice kept in
`helper/gesture/`).
