# Tiling and OmniWM

How windows behave under each layout, and the OmniWM settings
Omacchiato writes or leaves to you. The rest of the desktop is in the
[README](../README.md).

## Tiling details

OmniWM's dwindle puts the new window on a different side from
omarchy's. With `smartSplit` off, a new window goes right in a
horizontal split and above in a vertical one, while Hyprland's
`force_split=2` puts it right or below. So `omacchiato-spawn` applies
OmniWM's own orientation rule (height times `splitWidthMultiplier`
greater than width means a vertical split) to the focused tile and
preselects down or right for each new window.

Floats sink behind tiles, because macOS orders windows per app, not
per window: a float sinks behind whichever app you focus next, and
pinning it would need a private call with SIP off. `Super+S` raises
every floating window.

The resize chords work in both layouts: each one tries the niri
command first, and that command fails on a dwindle workspace, so the
dwindle one runs instead. Keyboard focus also moves the pointer
(`moveMouseToFocusedWindow`), because `Super+Tab` and the throws act
on the display under the pointer.

Focus follows clicks and keys, because `followsMouse` is off in
`config/omniwm/settings.toml`. The finger counts for the swipes are in
its `[gestures]` table. An existing `~/.config/omniwm/settings.toml`
keeps its own values, so set `fingerCount = 3` and
`workspaceSwipeFingerCount = 4` there to match.

## OmniWM notes

[OmniWM](https://github.com/BarutSRB/OmniWM) is a signed and notarized
tiling window manager with niri and dwindle layouts. `install.sh`
installs it with Homebrew, starts it, and adds it as a login item.
OmniWM does not start while another window manager runs, so quit any
other one first.

The bar and the overview read OmniWM's workspaces over IPC, and
`theme-set` colours its focus border and sets its light or dark
chrome. `Super+N` and `Super+Shift+N` route through Karabiner into
`omacchiato-omni`, a held-socket IPC client written in C, so slots
resolve on the display under your pointer; OmniWM's native hotkeys are
name-global and would always hit the main set. The cost is a shell
command per chord, and the IPC round trip itself takes about 4 ms.

The template in `config/omniwm/settings.toml` puts workspaces 1 to 5
on the main display and 6 to 9 on the secondary one. `install.sh`
copies it to `~/.config/omniwm/settings.toml` once, and OmniWM and
`theme-set` edit that local copy, so settings for one desk stay out of
the repo. To pin workspaces to one display, set
`type = "specificDisplay"` and add the display's `displayUUID` and
`name` in the local copy. If a pinned display is missing, OmniWM
moves its workspaces to the nearest display.

With one display left, the bar also runs `omacchiato-ws-collapse`,
which moves the windows on any two-digit workspace into the lowest
free 1 to 9 slot and records where each came from. Plug the display
back in and each window goes home.

OmniWM is daily-driven on a docked multi-monitor desk, and
`docs/omniwm-port.md` carries a ledger of upstream quirks found while
porting. Read it before assuming a strange layout is Omacchiato's fault.
