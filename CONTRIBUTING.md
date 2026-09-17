# Contributing to Omacchiato

Small repo, strong opinions. PRs are welcome when they keep these.

## The doctrines

- **Events over polling — always ask "who publishes this?" first.**
  Window changes come from SkyLight notifications, network state from
  SCDynamicStore, bluetooth from IOBluetooth notifications, power from
  IOPS, app lifecycle from NSWorkspace. A timer is acceptable only as
  a guarded safety net that never acts as the primary path, or where
  no publisher exists at all (the weather fetch, the clock).
- **The bar derives, it does not enumerate.** Pill spacing sweeps
  "every right-positioned item"; popup cleanup works off the naming
  convention below. If your change needs a hardcoded name list, find
  the derived form instead — every list here has rotted.
- **The bar is one process.** Bar, popups and OSDs are surfaces of
  `helper/bar.swift`, drawing from a model it holds in memory and feeds
  from publishers (SkyLight, CoreAudio, IOPS, DisplayServices,
  SCDynamicStore, IOBluetooth). Nothing on a render path may fork: the
  slow half — asking OmniWM what exists — runs off the main queue on
  window create/destroy only. A workspace switch touches no subprocess.
- **Ask for a font family and VERIFY you got it.** Requesting a family
  that is not installed does not fail, it silently substitutes; that is
  how half a bar ended up rendering in Hiragino Sans without one error
  anywhere. `nerdFont()` checks the family it got back and says so,
  once, when it had to fall back.
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
  bash-4isms — a fresh Mac has no Homebrew bash. Every plugin exports
  `PATH="/opt/homebrew/bin:$PATH"` (a launchd agent's environment does
  not guarantee it). Quote everything; device names and SSIDs contain
  spaces.
- **Daemons are single-file swiftc builds.** No SPM, no Xcode
  projects. Private APIs are declared with `@_silgen_name` and the
  framework linked explicitly in install.sh's build line. Blocking
  work (CLI spawns, AX calls) stays off the event/main thread, and AX
  calls carry a messaging timeout.
- **install.sh is idempotent and manifest-honest.** Anything it adds
  to the machine is recorded in `~/.local/state/omacchiato/manifest`;
  uninstall.sh removes exactly that and nothing the user had before.
  Backups are never deleted, displaced symlinks are recorded and
  restored.
- **Signing identity is sacred.** Helpers are codesigned with a
  stable "Apple Development" identity so TCC grants survive rebuilds.
  Never re-sign ad-hoc after the identity signing (that ordering bug
  has bitten before — see install.sh section 5).

## Practical notes

- Test on stock bash: `bash -n` is the floor, `/bin/bash script.sh`
  is the truth.
- The debug story is `/tmp/omacchiato-*.log` — daemons `tlog` there.
  Keep it that way; it is what bug reports run on.
- Theme packs are the easiest contribution: copy a directory under
  `themes/`, provide `colors.toml`, `sketchybar.sh` (the bar reads its
  palette from that file, keeping the omarchy theme format), `borders.sh`,
  `backgrounds/`. Palettes compatible with omarchy's 22-color scheme
  drop straight in.
- One change per PR, and say what you tested on (macOS version,
  displays, trackpads).
