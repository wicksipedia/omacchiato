# Herdr native shortcuts

## Problem Statement

How might we make herdr in Ghostty use the Mac shortcuts that a browser
uses (`cmd+t`, `cmd+w`, `cmd+1..9`, `ctrl+tab`), without a second tool
that also writes the herdr and Ghostty configs?

## Recommended Direction

Use the keymap idea of
[native-shortcuts-herd](https://github.com/yigitkonur/native-shortcuts-herd),
but not its installer. That tool is an npx package. It routes each `cmd` key
through Ghostty as a prefix sequence (`cmd+t` sends `ctrl+b t`) and keeps its
own state file and backups. Herdr 0.9.5 does not need that route: a key
string can name `cmd` directly, and an indexed action takes `cmd+1..9`. So
Ghostty only unbinds its own tab keys, and herdr binds them.

The keys in `config/herdr/keys.toml` replace the `ctrl+alt` set from omacosy.
`cmd` targets tabs, `ctrl+tab` cycles tabs, and `option+tab` cycles
workspaces. The prefix defaults stay. Ghostty does not get its own tabs back:
every Ghostty window runs herdr, and the quake terminal gets the same keys.

| Key | herdr action |
|---|---|
| `cmd+t` | `new_tab` |
| `cmd+w` | `close_tab` |
| `cmd+n` | `new_workspace` |
| `cmd+1..9` | `switch_tab` |
| `ctrl+tab` / `ctrl+shift+tab` | `next_tab` / `previous_tab` |
| `option+tab` / `option+shift+tab` | `next_workspace` / `previous_workspace` |

`config/requirements.conf` gets a herdr minimum of 0.9.5, the version that
these keys are tested on.

## Key Assumptions to Validate

- [ ] When Ghostty unbinds `cmd+t`, it sends the key to herdr with the Super
      modifier. Test: unbind it, then press `cmd+t` in herdr. If herdr gets
      nothing, use the CSI-u `text:` route from native-shortcuts-herd.
- [ ] `cmd+w` closes the herdr tab and not the Ghostty window. `cmd+w` is a
      menu shortcut, so it is the key most likely to fail.
- [ ] Herdr 0.9.5 accepts `switch_tab = ["prefix+1..9", "cmd+1..9"]`.
      Test: `herdr config check`.
- [ ] `option+tab` reaches Ghostty. OmniWM binds `Option+Tab` to
      `focusPrevious` now, and a global hotkey takes the key first.
- [ ] `ctrl+tab` is free in OmniWM and Karabiner.

## MVP Scope

In:
- `config/herdr/keys.toml`: the keys above. The `ctrl+alt+g` worktree popup
  stays.
- `config/ghostty/config`: unbind `cmd+t`, `cmd+w`, `cmd+n`, `cmd+1..9`,
  `ctrl+tab` and `ctrl+shift+tab`.
- `config/requirements.conf`: herdr 0.9.5. `omacchiato-requirements` reads
  only `.app` bundles now, so it also needs to read a command's `--version`.
  A missing herdr is not an error, because herdr is optional.
- An install whose herdr config holds the old omacosy keys block gets the
  new block. `omacchiato-herdr-keys` already removes a block that matches
  the old file, with the `# omacosy:` comment.
- The README herdr table and the `Super+K` cheatsheet.

Out: everything in Not Doing.

## Not Doing (and Why)

- The npx installer: a second program would write the herdr config, and it
  needs Node.
- Prefix sequences through Ghostty: herdr binds `cmd` keys itself. They are
  only the fallback if the first assumption fails.
- Profiles (tabs or workspaces for `cmd+1..9`): one keymap is enough.
- `cmd+k` and `cmd+l` renames: `prefix+shift+t` renames a tab, and renames
  are rare.
- The glass theme: `theme-set` owns the look.
- Ghostty tabs outside herdr: every Ghostty window runs herdr.

## Decisions

- OmniWM's `Option+Tab` (`focusPrevious`) goes, because `cmd+tab` does the
  same job. Then `option+tab` reaches herdr.
- The `ctrl+alt` pane keys go. Panes use the prefix defaults.
