# Spec: Herdr native shortcuts

Idea: `docs/ideas/herdr-native-shortcuts.md`.

## Objective

In Ghostty, herdr answers the Mac shortcuts that a browser uses. These keys
replace the `ctrl+alt` keys that omacosy added. The user is anyone who runs
herdr in Ghostty under omacchiato. Every Ghostty window runs herdr, so
Ghostty gives up its own tab keys.

| Key | herdr action |
|---|---|
| `cmd+t` | `new_tab` |
| `cmd+w` | `close_tab` |
| `cmd+n` | `new_workspace` |
| `cmd+1..9` | `switch_tab` |
| `ctrl+tab` / `ctrl+shift+tab` | `next_tab` / `previous_tab` |
| `alt+tab` / `alt+shift+tab` | `next_workspace` / `previous_workspace` |
| `ctrl+alt+g` | the worktree popup (no change) |

Each action keeps its herdr default prefix key as well. The panes use only
the prefix defaults (`prefix+h/j/k/l`, `prefix+v`, `prefix+minus`,
`prefix+z`).

Herdr binds the `cmd` keys itself. Ghostty only unbinds them, so Ghostty
sends them to herdr through the Kitty keyboard protocol. Ghostty sends
`ctrl+tab` and `ctrl+shift+tab` as CSI-u text. No prefix sequence goes
through Ghostty.

## Changes

### `config/herdr/keys.toml`

```toml
# omacchiato: Mac shortcuts. Ghostty unbinds its own tab keys, so herdr
# gets cmd+t, cmd+w, cmd+n, cmd+1..9 and ctrl+tab.
[keys]
new_tab = ["prefix+c", "cmd+t"]
close_tab = ["prefix+shift+x", "cmd+w"]
new_workspace = ["prefix+shift+n", "cmd+n"]
switch_tab = ["prefix+1..9", "cmd+1..9"]
next_tab = ["prefix+n", "ctrl+tab"]
previous_tab = ["prefix+p", "ctrl+shift+tab"]
next_workspace = "alt+tab"
previous_workspace = "alt+shift+tab"

[[keys.command]]
key = "ctrl+alt+g"
...
```

The `[[keys.command]]` table for the worktree popup does not change.
`herdr config check` must accept the file.

### `config/herdr/keys-omacosy.toml`

This is the old `keys.toml`, byte for byte (`git show HEAD:config/herdr/keys.toml`).
It is in the repo only so that install and uninstall can find the old
block and remove it.

### `bin/omacchiato-herdr-keys`

`add` and `remove` take more keys files after the current one:

```
omacchiato-herdr-keys <add|remove> <config.toml> <keys.toml> [<old-keys.toml>...]
```

- `remove` removes the block of the current file. If there is no such block,
  it removes the first block that matches an old file. The rules for a
  changed block stay as they are: a changed block stays, with a warning.
- `add` first removes a block that matches an old file, then adds the
  current block. A config with a keys table of the user's own stays as it is.
- An old block that the user changed stays, so `add` adds nothing, because
  the config still has a keys table.

### `install.sh` and `uninstall.sh`

Both pass `config/herdr/keys-omacosy.toml` as the old file. The comment in
`install.sh` says that an old omacchiato block is replaced too.

### `config/ghostty/config`

```
# herdr runs in every window and binds these keys itself.
keybind = super+t=unbind
keybind = super+w=unbind
keybind = super+n=unbind
keybind = super+digit_1=unbind
...
keybind = super+digit_8=unbind
keybind = super+1=unbind
...
keybind = super+9=unbind
keybind = ctrl+tab=text:\x1b[9;5u
keybind = ctrl+shift+tab=text:\x1b[9;6u
```

An unbound `ctrl+tab` reaches herdr as a plain Tab, so Ghostty sends the
CSI-u sequence for it. The `cmd` keys reach herdr when they are unbound.

These are the defaults of Ghostty 1.3.1 for those keys, as
`ghostty +list-keybinds --default` lists them. `super+digit_9` has no
default binding. Super in this file is the Command key, which is not
omacchiato's Super key (`cmd+ctrl+alt`).

### OmniWM `Option+Tab`

Remove the `focusPrevious` hotkey from `config/omniwm/settings.toml`, so that
`alt+tab` reaches Ghostty. `cmd+tab` does the same job. `install.sh` never
overwrites the live copy, so you remove it by hand from
`~/.config/omniwm/settings.toml`. The README tells other users to do the
same.

### `config/requirements.conf` and `bin/omacchiato-requirements`

```
# herdr 0.9.5: keys.toml binds cmd keys and cmd+1..9.
herdr   0.9.5  formula:herdr
```

A third field `formula:<name>` marks a command-line tool from a Homebrew
formula:

- The installed version is the last field of the first line of
  `<app> --version` (`herdr 0.9.5` gives `0.9.5`).
- If the command is not on `PATH`, print nothing and do not fail, because
  the tool is optional.
- If the version is too old, print `brew upgrade <name>` (no `--cask`) and
  exit 1, as for an app.

The lines for `.app` bundles do not change.

### `README.md`

- Replace the herdr chord table with the table in Objective. Say that
  Ghostty's own tab keys are off.
- Delete the `Option+Tab` row from the OmniWM table, if the README has one,
  and add a note that an existing install removes the hotkey by hand.
- Add herdr 0.9.5 to the herdr row of the requirements table.

### This Mac

- Run `install.sh`, or run `omacchiato-herdr-keys add` with the old file,
  to replace the omacosy block in `~/.config/herdr/config.toml`.
- Remove `Option+Tab` from `~/.config/omniwm/settings.toml`.

## Tech stack

Python 3.9 (`omacchiato-herdr-keys` runs under the system Python), bash,
TOML, and the Ghostty config syntax. There are no new dependencies.

## Commands

```sh
# All checks that need no screen
bin/omacchiato-test

# The herdr keys tests only
python3 -m unittest discover -s tests -p 'test_herdr_keys.py'

# Herdr accepts the keys
herdr config check

# Ghostty accepts the unbinds and shows the result
/Applications/Ghostty.app/Contents/MacOS/ghostty +list-keybinds | grep -E 'super\+(t|w|n|[1-9])|ctrl\+(shift\+)?tab'

# Version check
bin/omacchiato-requirements
```

## Project structure

```
config/herdr/keys.toml           new keys
config/herdr/keys-omacosy.toml   the old keys, for migration only
config/ghostty/config            unbinds
config/omniwm/settings.toml      no Option+Tab
config/requirements.conf         herdr 0.9.5
bin/omacchiato-herdr-keys        old-keys arguments
bin/omacchiato-requirements      formula: lines
install.sh, uninstall.sh         pass the old keys file
tests/test_herdr_keys.py         migration tests
tests/test_requirements.py       new: formula: lines
README.md                        herdr table, requirements
```

## Code style

Match the files you change. Comments follow CLAUDE.md: give the reason only,
in Simplified Technical English. `omacchiato-herdr-keys` keeps `add` and
`remove` as pure functions of strings, and `main()` sits behind
`if __name__ == "__main__"`.

## Testing strategy

Unit tests (`bin/omacchiato-test`):
- `add` with an unchanged old block gives the new block in place of the
  old one.
- `add` with a changed old block gives the config back unchanged.
- `remove` takes out an old block when the current block is not there.
- `omacchiato-requirements` with a `formula:` line covers four cases: the
  tool is missing (pass, prints nothing), too old (fail), new enough
  (pass), and a `.app` line still works. A stub `herdr` script on `PATH`
  supplies `--version`, and the test runs with a temp conf file.

Manual tests on this Mac, in herdr in Ghostty:
- `cmd+t`, `cmd+w`, `cmd+n` and `cmd+1..9` act on herdr tabs. `cmd+w`
  does not close the Ghostty window.
- `ctrl+tab` and `ctrl+shift+tab` cycle tabs. `alt+tab` and
  `alt+shift+tab` cycle workspaces.
- The quake terminal accepts the keys and is not damaged.
- `prefix` keys still work.

## Boundaries

- Always: run `bin/omacchiato-test` before a commit. Run `herdr config check`
  after you change `keys.toml`. Deploy to this Mac and get Matt's OK
  before you commit.
- Ask first: running `install.sh` (it restarts services), editing the live
  OmniWM settings, or changing a key that is not in this spec.
- Never: add the npx tool or Node, overwrite a herdr keys block that the
  user changed, or post key events to test.

## Success criteria

- Every key in Objective works in herdr 0.9.5 in Ghostty 1.3.1.
- A herdr config that holds the unchanged omacosy block gets the new block
  after `install.sh`. A config that holds a changed block keeps it.
- `uninstall.sh` removes the new block or the old one.
- `omacchiato-requirements` reports herdr and does not fail on a Mac with
  no herdr.
- `bin/omacchiato-test` passes.

## Fallback

The assumption with the most risk is that an unbound `cmd` key reaches
herdr. If herdr gets nothing, the fallback is a route from
native-shortcuts-herd: Ghostty sends a CSI-u `text:` sequence for the key,
and the herdr side does not change. Find this out in the first task,
before any other work.

## Not doing

- The npx installer and its profiles.
- The `cmd+k` and `cmd+l` renames, and the glass theme.
- herdr entries in the `Super+K` cheatsheet. It reads only OmniWM and
  Karabiner, and the README table covers herdr.
- Ghostty tabs outside herdr.
