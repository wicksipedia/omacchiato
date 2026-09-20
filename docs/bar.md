# Configuring the bar

Every setting the bar reads, the JSON a plugin pill returns, and a
section on each pill that ships. The bar itself is described in the
[README](../README.md).

## Choosing pills

`~/.config/omacchiato/bar-pills.conf` sets what each right-cluster pill
does, one `<name> = <mode>` per line. The names are `menubar`,
`weather`, `wifi`, `bluetooth`, `brightness`, `volume`, `mic`,
`battery`, `clock` and `activity`. The modes are `hide` and `icon`.
`volume` also takes `muted`, and `battery` takes `time`. Lines starting
with `#` are comments.

```
weather = hide
battery = icon
```

`hide` also skips the pill's provider, so hiding `weather` stops the
wttr.in fetches and hiding `bluetooth` never touches the Bluetooth
grant. `icon` drops the label and keeps the glyph; the weather pill
ignores it, because its glyph is part of the label. `volume = muted`
draws the volume pill only while the output device is muted or at
zero, as a red icon, the same way the microphone pill works.
`battery = time` shows only the battery icon on AC power; on battery
it adds the time left, in whole hours or in minutes under an hour.

`popup = glass` draws the popups on Liquid Glass, so the desktop shows
through them, instead of the theme's flat background. The system
setting Accessibility > Display > Reduce transparency turns it off
again.

`media = <characters>` sets how much of the track title the music pill
shows before the title scrolls. The default is 28. A display with a
notch uses five sevenths of the number, so 20 by default.

The bar reads the file once at startup, so restart it to apply an
edit:

```sh
launchctl kickstart -k "gui/$(id -u)/com.omacchiato.bar"
```

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

Plugin pills sit at the left of the right cluster, in file order.
Clicking one runs its command again at once. A name that matches a
built-in pill is ignored, and so is a section with no `command`.
Labels are cut at 32 characters, because the cluster is laid out from
the right edge inwards and a long one would push the other pills off
screen.

The command is passed to `sh` as an argument, never spliced into a
shell string. It runs with `~/.local/bin` and the Homebrew prefixes
ahead of `PATH`, so a plugin can name a script or a `brew` binary
directly, and it runs with the bar's own permission grants. Like the
rest of this file it is read once at startup.

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
the way the activity pill opens btop. A row with a `run` command runs
it with no window, then runs the plugin again, so the popup shows what
the command changed. Both run with the same trust as the plugin
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

`parts` adds more icons to the pill, each in its own colour, after the
icon and label:

```json
{"label": "", "color": "green", "parts": [
  {"icon": "\uec82", "icon_color": "#D97757", "label": "27%"},
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
`install.sh` installs it. Two settings on the command line choose the
providers:

- `--pill` sets the providers in the pill label, and the usage window
  for each one: `<id>[:<window>]`, separated by commas. The default is
  `claude`.
- `--panel` sets the providers in the popup, separated by commas. The
  default is the `--pill` providers.

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

The popup has one section for each `--panel` provider. The first opens
with the popup and the rest start closed; click a header to open one.
If tokscale reports more than one Codex account, each account gets a
section. A header carries the provider's logo, its name, the plan in
small quiet type, and the usage and reset of the five-hour window, so a
closed section still answers the question you opened the popup for.

Inside, each usage window takes one row: its name, a bar, and the
percent with the time until it resets. The bar has a tick at the share
of the window that has passed, and the bar's colour compares the two:
green at or near an even pace, yellow more than 5 points ahead, and red
more than 20 points ahead or at 90% used. A window whose plan carries
no limit is left out.

A status row appears only while a provider is not operational. It reads
the provider's components on its status page:
Claude Code on status.claude.com, the Codex components on
status.openai.com, and Copilot on githubstatus.com. It ignores the
page's overall rating, which also drops when another product of that
company has a problem. If the worst component is not operational, the
pill gets 🏥 for a minor problem or 🪦 for a major one. An open
incident adds rows with its title, its state and the time of its latest
update, and a click opens the incident page. status.openai.com lists no
incidents, so Codex has the status row only.

After the providers, a closed section holds the last seven days from
tokscale's read of the session logs on this Mac: tokens per day and per
model with their value at API prices, sessions, active days and active
hours. The last row opens tokscale's full report in a terminal.

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

Each PR gets one mark, for what it needs next. If more than one
applies, the first in this list wins:

- a pencil: a draft
- a red warning: CI failed, or the branch has merge conflicts
- a yellow clock: CI is running
- a yellow comment: feedback to resolve, which is changes requested or
  a review thread from someone else that nobody has resolved
- a green check: ready to merge, approved with passing checks and no
  conflicts
- a muted clock: waiting for a review

Under the mark, a sentence appears only where it says more than the
mark does: a merge conflict, a failed check, changes requested, or the
number of threads left to resolve. A pull request that is only waiting
takes one row.

The pill turns red while CI fails on any open PR. Clicking a PR row or
the line under it opens the PR. To drop a PR from the list,
unsubscribe from its notifications on GitHub.

An update is an unread GitHub notification on the PR. GitHub marks the
notification read when you open the PR, so the `!` goes at the next
run after you look. A PR merged (🟣) or closed (⚫) in the last week
stays in the list, with a merge glyph or an x, while its notification
is unread. To find those
notifications the script reads every page of your unread inbox, about
half a second per 50, while the search runs. If GitHub is out of
reach, the popup keeps the last list and says when it was fetched.

## The keep-awake pill

`omacchiato-keep-awake` shows a cup while something is keeping the Mac
awake, and hides otherwise. It names no particular app: it reads the
power assertions, and ignores the ones held from the system's own
directories, because powerd, coreaudiod and sharingd hold one as a
matter of course. It also ignores an assertion held by a coding agent,
which is a short lease on the machine rather than a setting you left
on. Reading the assertion rather than an app's saved setting means it
still reports the truth after the app holding it quits. Clicking it
lists what is holding the Mac awake and how long each has held it.

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
