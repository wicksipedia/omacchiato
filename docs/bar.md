# Configuring the bar

Every setting the bar reads, the JSON a plugin pill returns, and a
section on each pill that ships. The bar itself is described in the
[README](../README.md).

## Choosing pills

`~/.config/omacchiato/bar-pills.conf` sets what each right-cluster pill
does, one `<name> = <mode>` per line. The names are `menubar`,
`weather`, `wifi`, `bluetooth`, `brightness`, `volume`, `mic`,
`status`, `battery`, `clock` and `activity`. The modes are `hide` and `icon`.
`volume` also takes `muted`, and `battery` takes `time`. Lines starting
with `#` are comments.

```
weather = hide
battery = icon
```

`hide` also skips the pill's provider, so hiding `weather` stops the
wttr.in fetches and hiding `bluetooth` never touches the Bluetooth
grant. `icon` drops the label and keeps the glyph. `volume = muted`
draws the volume pill only while the output device is muted or at
zero, as a red icon, the same way the microphone pill works.
`battery = time` shows only the battery icon on AC power; on battery
it adds the time left, in whole hours or in minutes under an hour.

The status pill is one gauge for the battery and the wi-fi, and it
replaces the `wifi` and `battery` pills. The ring is the Mac battery,
and the four dots that close the ring at the bottom are the wi-fi
signal. The ring is red at 20 % or less and green on AC power. The
wi-fi glyph in the ring is dim when no network is joined, and a slash
through it means wi-fi is off. A click opens a panel with the gauge
drawn large, tiles for power, health, mode, signal, link, channel and
address, a wi-fi switch, and the networks and phones to join. A middle
click turns wi-fi on or off. `wifi` and
`battery` show only when the file names them, for example
`wifi = icon` or `battery = time`. `status = hide` removes the gauge.

To change the gauge or a panel, open `helper/ui/Package.swift` in Xcode,
then open `StatusGauge.swift`, `BarPillsPreviews.swift` (the workspace
chips and the music pill), `StatusPreviews.swift`, `CalendarPreviews.swift`,
`ActivityPreviews.swift`, `ThemePreviews.swift` or `WeatherPanel.swift` and show the canvas
(Option-Command-Return). Each preview file shows every design. The weather previews read a saved
wttr.in answer, `tests/fixtures/wttr-j1.json`.
The previews draw every state at bar size and large, in light and dark.

`status_panel`, `clock_panel`, `menubar_panel` and `activity_panel` pick
the design of the status, clock, menu bar apps and activity popups.
`status_panel` takes `gauge` (the default), `control-center` or
`settings`. `clock_panel` takes `timeline` (the default), `up-next` or
`month`. `menubar_panel` takes `list` (the default), `grid` or `dock`.
`activity_panel` takes `monitor` (the default), `widgets` or `top`. Each
design shows the same things and takes the same clicks.

```
status_panel = settings
clock_panel = month
```

Every popup sits on Liquid Glass, as the macOS menus do. A popup of
rows, such as the Apple menu or a plugin's rows, looks like a macOS
menu: the arrow keys select a row, Return clicks it and Esc closes the
popup.

`media = <characters>` sets how much of the track title the music pill
shows before the title scrolls on a display without a notch. The
default is 28.

On a display with a notch, the music pill joins the left side and
grows up to the notch. `media_notch_fill = no` stops that, and then
`media_notch = <characters>` sets the limit. The default is 20. The
pill never runs under the notch.

`left_gap = <points>` and `right_gap = <points>` set the space between
the pills on each side of the bar. The defaults are 6 on the left and
6 on the right.

`order` sets the order of the right-hand pills, left to right. It takes
built-in and plugin pills alike, so a plugin can sit between two
built-in pills:

```
order = clock, github, status, weather
```

The pills it names come first. The rest follow in the default order:
`menubar`, the plugins in the order of `bar-plugins.conf`, then the
built-in pills. The bar ignores an unknown name. A hidden pill keeps
its place, so it goes back there when it shows again. The Bar page in
Settings writes this key when you drag a pill.

The bar reloads the file when it changes, so an edit applies at once.
The Settings window, from "Omacchiato Settings…" in the Apple menu,
writes the same keys. Each popup also ends with "Customize Pill",
which opens that pill's page in Settings.

## HUDs, keys and features

These keys in `bar-pills.conf` turn features on or off. Each is on by
default unless it says otherwise. The HUDs & Sounds page in Settings
holds the HUD and click switches.

| Key | Effect |
|---|---|
| `volume_hud = off` | The volume keys change the volume with no HUD. The bar still takes the keys. |
| `volume_click = off` | No click when a volume key goes up. |
| `mic_hud = off` | No HUD when the microphone mutes or unmutes. `Super+M` still mutes it. |
| `keep_awake_hud = off` | No HUD when keep awake turns on or off. |
| `keep_awake_display = on` | Keep awake also keeps the display on. Off by default. |
| `keep_awake_jiggle = <minutes>` | Move the mouse, without moving the pointer, every N minutes while keep awake is on, so chat apps do not show Away. The default is 1; `off` or `0` stops it. |
| `keep_awake_battery = <percent>` | On battery, keep awake ends at this level. The default is 20; `off` or `0` stops the limit. |
| `keep_awake_lid = off` | Keep awake no longer keeps the Mac awake with the lid closed. |
| `quit_on_close = on` | Quit an app when its last window closes. Off by default. |
| `hud_position = <place>` | Where the HUDs show: `top-right` (the default), `top-center`, `top-left`, `center` or `bottom-center`, on the screen with the pointer. |
| `debug = on` | Write the bar's memory to `/tmp/omacchiato-bar.log` once a minute. Off by default. |

The bar takes the volume keys and shows its own HUD, so the macOS HUD
does not show. Shift+Option steps a quarter step. Option alone still
opens Sound settings. An output with no volume control, such as some
HDMI displays, passes the key on to macOS.

Quit on close counts standard windows and dialogs, minimized ones and
the ones OmniWM parks on other workspaces. It never quits a menu bar
app, an app with a menu bar icon, Finder, Omacchiato or OmniWM. The
apps in `~/.config/omacchiato/quit-on-close.conf`, one bundle ID a
line, stay open too. The first `install.sh` run copies that list, and
the on or off setting, from Vorssaint if it finds them.

`omacchiato-popup <item> [display]` opens a pill's popup from a script or
a Karabiner chord, as a click on the pill does. The item is a pill
name, a plugin pill's name, `apple` or `appmenu`, and the display is
its name as macOS shows it, such as `"DELL U2722D (1)"`. Without a
display it uses the display under the pointer, and with no item it
closes the open popup.

## Adding pills

`~/.config/omacchiato/bar-plugins.conf` adds pills without a rebuild.
Each `[name]` section takes a `command`, run by `/bin/sh -c`, whose
first line of stdout becomes the label. `interval` is the gap between
runs in seconds (minimum 1, default 30) and `icon` is an optional
glyph. The icon takes the pill's colour unless `icon_color` names one:
a theme colour such as `accent`, or `#RRGGBB` for a brand colour.

```
[cpu]
command = ps -A -o %cpu | awk '{s+=$1} END {printf "%.0f%%", s/8}'
interval = 5
```

If a run fails, the pill keeps its last label in the muted colour, and
its popup starts with the error: "no answer in 120 s" when the run took
longer than its interval (or 30 s), or "failed with exit 1" when the
command exits non-zero and prints nothing. The first line of stderr and
a "run again" row follow, then the rows of the last run that worked. A
pill that hides when all is well shows a warning icon instead. The next
run that works clears the error.

Plugin pills sit at the left of the right cluster, in file order.
Clicking one runs its command again at once. A name that matches a
built-in pill is ignored, and so is a section with no `command`.
Labels are cut at 32 characters, because the cluster is laid out from
the right edge inwards and a long one would push the other pills off
screen.

The command is passed to `sh` as an argument, never spliced into a
shell string. It runs with `~/.local/bin` and the Homebrew prefixes
ahead of `PATH`, so a plugin can name a script or a `brew` binary
directly, and it runs with the bar's own permission grants. The bar
reloads the file when it changes, and restarts only the plugins whose
section changed.

A command that prints a JSON object instead of a line can also set the
pill's colour and give it a popup:

```json
{
  "label": "10% - 2h 6m",
  "color": "green",
  "rows": [
    {"text": "Claude", "subtitle": "Max 5x", "detail": "10% · 2h 6m", "hero": true},
    {"separator": true},
    {"text": "Session", "bar": 0.1, "marker": 0.58, "bar_color": "green",
     "detail": "10% · 2h 6m"}
  ]
}
```

`color` is one of `accent`, `label`, `muted`, `red`, `green` or
`yellow`, resolved from the current theme, and tints both the icon and
the label. A row takes the same `color` names. A row with an `https`
or `x-apple.systempreferences:` `url` opens it when clicked, and a row
with a `terminal` command opens your terminal on that command instead,
the way the activity popup opens btop. A row with a `run` command runs
it with no window, then runs the plugin again, so the popup shows what
the command changed. A top-level `right_click` command runs when you
right-click the pill, then the plugin runs again; the keep-awake pill
uses it to turn keep awake on or off. Both run with the same trust as the plugin
command that printed them. A colour emoji draws its own colours and
ignores the icon tint, which is why the label carries it too. `icon`
overrides the config.
A row's `icon` draws a glyph before its text, in the accent colour or
in the row's `icon_color`, which takes a theme colour name or
`#RRGGBB`.

A row with `"section": "closed"` or `"section": "open"` is a header.
A click on it shows or hides the rows after it, up to the next header
or a row with `"section": "end"`. The value sets how the section starts,
and the bar keeps each click until it restarts. The header shows ▸ when
the section is closed and ▾ when it is open.

`parts` adds more icons and labels to the pill, after the icon and
label. `icon_color` colours a part's icon, and `label_color` its label,
such as a quiet time. `"under": true` stacks a part's label under the
label before it, in smaller type:

```json
{"label": "", "color": "green", "parts": [
  {"icon": "\uec82", "icon_color": "#D97757", "label": "27%"},
  {"label": "2h", "label_color": "muted"},
  {"icon": "\uec81", "icon_color": "label", "label": "0%"}
]}
```

Each part's label takes the pill's `color`.

A `slider` between 0 and 1 draws a progress track. On a slider row
`text` is a short right-aligned readout rather than a label, so put
the label on the row above, and `color` sets the fill. A `marker`
between 0 and 1 draws a tick across the track; the AI usage pill uses it
to show how far through each usage window you are. A `bar` between 0
and 1 draws the same track inside an ordinary row, between its `text`
and its `detail`, and all such bars in a popup share one column, which
holds still when a folded section opens. `bar_color` colours that bar
alone and leaves the words beside it in the row's own colour.

A `subtitle` follows the `text` in small quiet type, for the second
half of a title: the AI usage pill names the provider, then the plan. Give
a pill rows and clicking it opens the popup instead of re-running the
command.

A pill draws nothing while its label and its icon are both empty,
which is how a pill reports a state worth no space at all. Send
`"icon": ""` to hide one, because an absent `icon` falls back to the
glyph the config names.

## The AI usage pill

`omacchiato-ai-usage` shows the plan usage of Claude, Codex and Copilot.
[tokscale](https://github.com/junhoyeo/tokscale) reads the numbers, and
`install.sh` installs it. These settings go on the command line:

- `--pill` sets the providers in the pill label, and the usage window
  for each one: `<id>[:<window>]`, separated by commas. The default is
  `claude`.
- `--panel` sets the providers in the popup, separated by commas. The
  default is the `--pill` providers.
- `--inline` puts the time to the first provider's reset beside its
  percent. By default it sits under the percent, in smaller type.

An id is `claude`, `codex` or `copilot`. A window is the name that the
popup shows for it, such as `weekly` or `fable`, and case does not
matter. Without a window, the pill uses the five-hour window. `5h`
names it for every provider, and `max` takes the window with the most
use. If a provider has no window of that name, the pill uses `max`.

```ini
[ai]
command = omacchiato-ai-usage --pill claude,codex:weekly --panel claude,codex,copilot
interval = 120
icon = 
icon_color = #D97757
```

With one provider, the label shows the percent used and the time until
that window resets, such as `23% · 2:25`. With more, it shows each
provider's logo in its brand colour and its percent, in `--pill` order.
A provider that rounds to 0% in its window leaves the label, so the
pill names only what you use. When every provider sits at 0%, the pill
is one robot face. The popup still lists every `--panel` provider.
The `icon` setting then does not show, because one icon cannot name
more than one provider. The Claude logo is `#D97757`. The OpenAI and
Copilot logos are black or white, so they take the theme's label
colour. The percents are green under 50%, yellow under 80% and red
above.

The popup is a panel with one card for each `--panel` provider. If
tokscale reports more than one Codex account, each account gets a card.
A card header carries the provider's logo, its name and the plan. Click
a header to open or close the card. A closed card shows the percent of
its fullest window. `--open` names the providers whose cards start
open, separated by commas. The default is the first `--panel` provider.

```ini
command = omacchiato-ai-usage --pill claude,codex --panel claude,codex,copilot --open claude
```

An open card shows the usage windows as rings, outside in, as the
Fitness app shows its rings. Each ring has its own colour: blue, purple,
then mint. A table next to the rings gives each window's percent and
the time until it resets, with a dot in the ring's colour. The tick on
a ring marks the share of the window that has passed. The percent turns
orange when the use is more than 5 points ahead of an even pace, and
red when it is more than 20 points ahead or at 90% used. A window whose plan
carries no limit is left out.

A status box appears only while a provider is not operational. It reads
the provider's components on its status page:
Claude Code on status.claude.com, the Codex components on
status.openai.com, and Copilot on githubstatus.com. It ignores the
page's overall rating, which also drops when another product of that
company has a problem. If the worst component is not operational, the
pill gets 🏥 for a minor problem or 🪦 for a major one. An open
incident adds its title, its state and the time of its latest update,
and a click opens the incident page. The box stays on screen when the
card is closed. status.openai.com lists no incidents, so Codex has the
status line only.

After the providers, a card shows the last seven days from tokscale's
read of the session logs on this Mac. A bar chart gives the tokens of
each day, split by model, with a dashed line at the daily average. A
bar under the chart gives each model's share of the week. The card also
gives the week's tokens and their value at API prices. The last row
opens tokscale's full report in a terminal.

`<pill>_panel` in `bar-pills.conf` picks another design, with the pill's
name from `bar-plugins.conf`: `screen-time` leads with the daily
average, and `forecast` says where each window is heading at the
current rate. The default is `rings`.

```
ai_panel = forecast
```

The script prints the panel's data under `panel`, and the rows too. The
bar shows the rows when the panel data is missing.

The script runs `tokscale usage` at most every five minutes and reads
the week every ten minutes. If a provider is missing from one run, the
popup keeps its last numbers for 15 more minutes. tokscale reads the
Claude Code token and never refreshes it or writes it back: a third
party that rewrites the CLI's own credentials can race Claude Code and
sign you out. For the icon, the Nerd Font Claude glyph is U+EC82.

## The AirPods pill

`omacchiato-airpods` shows a pill while AirPods Pro or AirPods Max are
connected, and prints no pill otherwise. Add it to `bar-plugins.conf`:

```ini
[airpods]
command = omacchiato-airpods
interval = 10
```

With `interval = 10`, the pill shows up to 10 seconds after the AirPods
connect. The label is the lowest battery level of the earbuds, or of
the AirPods Max, and turns red at 20% or less. The case does not count.

The popup shows a battery bar for each earbud and the case, or one for
AirPods Max. Below it, one row for each noise control mode that the
device supports: Off, Transparency, Adaptive and Noise Cancellation.
The current mode has a check, and a click switches to that mode. The
last row opens Sound settings. With two devices connected, each device
is a section that starts closed.

Nothing on the Mac reports whether AirPods charge. A cable to this Mac
is the closest fact, so a row under the batteries says the AirPods are
plugged into this Mac while `ioreg` lists them as a USB device with the
same serial number. It is a row of its own, because a mark on one
battery read as that side charging.
A wall charger stays invisible. While the cable carries the audio, the
noise control rows drop out: airpods-control controls a device only
over Bluetooth.

AirPods Max report no battery to `system_profiler`, so the script also
runs `omacchiato-helper bt battery`, which reads the percentages that
IOBluetooth carries. A value from `system_profiler` wins where both
report one.

You can rename AirPods, so the script finds the model from the
device's Bluetooth product ID. macOS ships the product ID of each Apple
model in `CoreTypes.bundle`, and the script counts any model whose type
starts with `com.apple.airpods-pro` or `com.apple.airpods-max`. A new
model works after the macOS update that adds it. The script holds the
IDs of the two models that are older than that list: AirPods Pro and
AirPods Max (Lightning). It reads the battery from
`system_profiler SPBluetoothDataType -json`, which comes with macOS.

The noise control rows come from
[airpods-control](https://github.com/raulgg/airpods-control), which
`install.sh` builds from source at a pinned version. macOS gives the
noise control mode only to a process with a private Apple entitlement.
airpods-control loads a small library into its own process that answers
yes to that one check, and to no other. Its `SECURITY.md` describes the
library. It is a new project, and a macOS update can break it. Without
it, or when it fails, the popup shows the battery rows only.

## The GitHub pull requests pill

`omacchiato-github-prs` lists the open pull requests you authored. It
needs the GitHub CLI, signed in with `gh auth login`.

```
[github]
command = omacchiato-github-prs -repo:owner/bots
interval = 120
```

Arguments are extra GitHub search qualifiers. `-repo:owner/name`
leaves out a repository of automated PRs, and `org:name` keeps one
organisation. For the icon, the Nerd Font pull request glyph is
U+F407.

The popup is a panel. A bar at the top counts the open PRs by stage,
and the panel then groups the PRs by stage, in this order:

- Needs You: CI failed, the branch has merge conflicts, changes were
  requested, or a review thread from someone else is not resolved
- Checks Running
- In Review: waiting for a review
- Ready to Merge: approved, with passing checks and no conflicts
- Drafts
- Done: merged or closed in the last week, while its notification is
  unread

A row shows the PR's mark, its title, the repository and number, the
lines added and removed, and the time since its last change. A PR that
sits on the branch of another PR is indented under it. Under a PR that
needs you, a red line says why, such as "2 checks failed" or "3 threads
to resolve". A click on a row opens the PR.

`github_panel` in `bar-pills.conf` picks another design, with the
pill's name from `bar-plugins.conf`. `reminders` shows a tile with a
count for each stage, and a click on a tile shows only that stage.
`tracker` shows checks, review and merge as three steps on each PR.
The default is `inbox`.

```
github_panel = reminders
```

The pill turns red while CI fails on any open PR.

To take a PR off the list, swipe left on its row with two fingers and
click Read, swipe further to mark it read at once, or click its blue
dot. The script stores the PR's last update time in
`~/.config/omacchiato/github-prs-read.json` and marks its GitHub
notification read. The PR comes back when GitHub updates it again, for
example with a review or a push. Unsubscribing from a PR's
notifications on GitHub also drops it.

An update is an unread GitHub notification on the PR. It puts a blue
dot on the row and a `!` on the pill. GitHub marks the notification
read when you open the PR, so the dot goes at the next run after you
look. To find those notifications, the script reads every page of your
unread inbox, about half a second per 50, while the search runs. If
GitHub is out of reach, the popup keeps the last list and says when it
was fetched.

## The keep-awake pill

`omacchiato-keep-awake` turns keep awake on and off, and shows the cup:
dimmed while the Mac may sleep, in the accent colour while it stays
awake.

```sh
omacchiato-keep-awake on        # until turned off
omacchiato-keep-awake for 45    # for 45 minutes
omacchiato-keep-awake toggle    # on for the time chosen last, or off
omacchiato-keep-awake off
```

The command writes `~/.local/state/omacchiato/keep-awake`, and the bar
holds the Mac awake while that file reads on. So if the bar stops, keep
awake stops too. `Super+Esc` and a right-click on the cup run `toggle`.
The popup has the switch, buttons for 30 minutes, 1 hour, 2 hours and
until turned off, and a custom time in 15-minute steps. The time you
pick is the one `toggle` uses next. The keys under
[HUDs, keys and features](#huds-keys-and-features) set the jiggle, the
battery limit, the display and the lid.

The lid needs `pmset -a disablesleep`, which needs root.
`omacchiato-lid-rule install`, which `install.sh` runs, adds a sudoers
rule that allows only `pmset -a disablesleep 0` and `1`, and asks for
the admin password once.

The popup also lists the other apps that hold the Mac awake. It names no particular app: it reads the
power assertions, and ignores the ones held from the system's own
directories, because powerd, coreaudiod and sharingd hold one as a
matter of course. It also ignores an assertion held by a coding agent,
which is a short lease on the machine rather than a setting you left
on. Reading the assertion rather than an app's saved setting means it
still reports the truth after the app holding it quits. Clicking it
lists what is holding the Mac awake and how long each has held it.

## The CPU, memory and disk pills

`omacchiato-stats cpu`, `omacchiato-stats ram` and `omacchiato-stats disk`
each show the percentage in use. The pill turns yellow at 75 % and red
at 90 %. The CPU popup shows the processes that use the most CPU, and
the memory popup shows the app, wired and compressed memory and the
processes that use the most memory. Memory counts as Activity Monitor
counts it. The disk popup shows the free space of the startup disk and
links to Storage settings.

```
[cpu]
command = omacchiato-stats cpu
interval = 5

[ram]
command = omacchiato-stats ram
interval = 10

[disk]
command = omacchiato-stats disk
interval = 300
```

## The update pill

`omacchiato-updates` shows the number of commits that your clone does
not have yet, and hides when there are none. It fetches the branch that
your local branch tracks, as `omacchiato-update` does. The popup lists
the new commits. Click "update now" to run `omacchiato-update` in a
terminal. A fetch goes to the network, so set a long interval:

```
[updates]
command = omacchiato-updates
interval = 3600
```

The microphone pill is built in rather than a plugin, because
CoreAudio costs about 65 ms to open in a fresh process and the bar
already holds it open for the volume pill.

## Workspace icons

The optional `~/.config/omacchiato/workspace-icons.conf` file sets an
icon per workspace. Each non-comment line has one workspace name, an
equals sign, and either one Unicode scalar or a reverse-DNS bundle
identifier.

```
1 = ★
14 = ◆

4 = com.apple.Safari
```

The bar first uses a configured icon. It then shows the icons of up to
three apps on that workspace, fanned like a hand of cards, with the
app in the leftmost window in front. Otherwise it shows the
workspace's last digit. Exact workspace names win: in this example,
workspace `14` uses `◆`, not the `4` shorthand. The shorthand applies
only to multi-digit, all-numeric workspace names ending in `1` through
`9` when they have no exact declaration.

The bar reads the file once at startup, so restart it to apply an
edit. Malformed lines are logged and ignored. A well-formed bundle
identifier that does not resolve to an installed app blocks the
shorthand for that exact workspace, and the bar falls back to the app
icons or the digit. Image paths are unsupported because the bar
resolves configured app icons at startup and does no file I/O while it
draws.

## The native menu bar

The native menu bar auto-hides and the bar sits in its place. If a
fullscreen window covers the bar and no window manager runs, the top
edge brings the bar back; otherwise the top edge belongs to the
auto-hidden native menu bar, which reveals above the bar and stays
clickable. If the native menu bar gets stuck revealed over the bar (a
Tahoe bug, most often poked by a Focus mode's menu-bar icon),
`killall SystemUIServer` resets it.
