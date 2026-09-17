# Contributing to Omacchiato

Small repo, strong opinions. PRs are welcome when they keep these.

## The doctrines

- **Events over polling — always ask "who publishes this?" first.**
  Window changes come from SkyLight notifications and OmniWM's `watch`
  stream, network state from SCDynamicStore, bluetooth from IOBluetooth
  notifications, power from IOPS, app lifecycle from NSWorkspace. A
  timer is acceptable only as a guarded safety net that never acts as
  the primary path, or where no publisher exists at all (the weather
  fetch, the clock, plugin commands).
- **The bar derives, it does not enumerate.** `rightOrder` builds the
  pill order from `bar-plugins.conf` and `bar-pills.conf`. If your
  change needs a hardcoded name list, find the derived form instead.
  Hardcoded lists in this repo have rotted before.
- **The bar is one process.** Bar, popups and OSDs are surfaces of
  `helper/bar.swift`. They draw from a model that the bar holds in
  memory and feeds from publishers (SkyLight, OmniWM's `watch` stream,
  CoreAudio, IOPS, DisplayServices, SCDynamicStore, IOBluetooth).
  Nothing on a render path may fork. A workspace switch repaints the
  chips from the `watch` stream, which is already running. The full
  OmniWM snapshot runs off the main queue, 150 ms after a window or
  display event.
- **Ask for a font family and VERIFY you got it.** Requesting a family
  that is not installed does not fail, it silently substitutes; that is
  how half a bar ended up rendering in Hiragino Sans without one error
  anywhere. `nerdFont()` checks the family it got back and writes a
  `tlog` line each time it falls back.
- **Popups are views, not items.** A popup is a list of rows in its own
  window, built fresh each time it opens. There is no naming convention
  to respect and nothing to clean up: closing the window takes the rows
  with it.
- **Popup design language:** accent hero row, plain body rows, dimmed
  12pt action footer. Click paths never touch the network — fetch on a
  timer into the model, render from that.
- **Hide, don't lie.** A pill whose data source fails hides itself
  rather than rendering garbage.
- **Shell is /bin/bash 3.2.** No `declare -A`, no `${var,,}`, no
  bash-4isms — a fresh Mac has no Homebrew bash. launchd gives the bar
  a bare `PATH`, so the bar puts `~/.local/bin` and Homebrew first
  before it runs a plugin command. If Karabiner or launchd runs a
  script directly and it needs Homebrew tools, export
  `PATH="/opt/homebrew/bin:$PATH"` in that script. Quote
  everything; device names and SSIDs contain spaces.
- **Daemons are single-file swiftc builds.** No SPM, no Xcode
  projects. The C tools are the exception: `omacchiato-gesture` and
  `omacchiato-omni` build with one `clang` line each in install.sh.
  Swift code declares private functions with `@_silgen_name`, and
  install.sh's build line links the framework. CoreBrightness and
  login.framework load at run time with `dlopen` instead. Blocking
  work (CLI spawns, AX calls) stays off the event/main thread, and AX
  calls carry a messaging timeout.
- **install.sh is idempotent and manifest-honest.** Anything it adds
  to the machine is recorded in `~/.local/state/omacchiato/manifest`;
  uninstall.sh removes exactly that and nothing the user had before.
  Backups are never deleted, displaced symlinks are recorded and
  restored.
- **Signing identity is sacred.** Helpers are codesigned with a
  stable "Apple Development" identity so TCC grants survive rebuilds.
  On Apple Silicon the linker signs each build ad-hoc, so sign with
  the identity after the last build step. For this reason install.sh
  signs `omacchiato-gesture` in section 5, right after its build.

## Practical notes

- Test on stock bash: `bash -n` is the floor, `/bin/bash script.sh`
  is the truth.
- The debug story is `/tmp/omacchiato-*.log`. The bar and the overview
  write there with `tlog`, and launchd sends the gesture daemon's output
  there. The bar's stderr goes to `/tmp/omacchiato-bar.err`. Keep it
  that way; it is what bug reports run on.
- Theme packs are the easiest contribution: copy a directory under
  `themes/`, provide `colors.toml`, `sketchybar.sh` (the bar reads its
  palette from that file, keeping the omarchy theme format), `borders.sh`,
  `backgrounds/`. Palettes compatible with omarchy's 22-color scheme
  drop straight in.
- One change per PR, and say what you tested on (macOS version,
  displays, trackpads).
