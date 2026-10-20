# Spec: Herdr hotkey

Idea: `docs/ideas/herdr-hotkey.md`.

## Objective

`Super+A` takes you to the herdr session in Ghostty. If the herdr window
that the hotkey opened is still open, the press focuses that window and
goes to its workspace. If not, the press opens a new Ghostty window that
runs `herdr` and remembers it. A press on the focused herdr window does
nothing more.

The user is anyone who runs herdr under omacchiato. `Super+Return` does
not change: it still opens a plain shell.

The herdr window is an ordinary tiled window. It opens on the workspace
under the pointer, with the omarchy split side, as `Super+Return` does.
You can move it to another workspace or display, and the hotkey still
finds it.

## Assumptions

1. `open -na Ghostty --args --command=herdr` opens one window that runs
   herdr. The window closes when herdr exits or detaches.
2. A new Ghostty window takes the focus, so after the launch,
   `query focused-window` gives its id.
3. `omacchiato-omni focus-window` takes the string `id` from the window
   query (`ow_…`), not the numeric `windowId`. The `focus` command goes
   to an inactive workspace.
4. That `id` stays the same when OmniWM moves the window to another
   workspace or display.
5. A herdr window that you open by hand is not the hotkey's window. herdr
   attaches it to the same session, so it does no harm.

A test on 2026-10-20 confirmed 1 to 4, with one change: `open` passes
the caller's environment to Ghostty. If the script runs inside herdr,
`HERDR_ENV=1` makes the new herdr refuse to start as a nested herdr. So
the script unsets the `HERDR_*` variables before the launch.

The `id` holds the pid and the CG window id of the window. So OmniWM
cannot give an old `id` to a window of another app, and the script needs
no bundle check before the focus.

## Tech Stack

- Bash, like `bin/omacchiato-spawn`.
- `omacchiato-omni` (`helper/gesture/omnicli.c`) for the OmniWM IPC.
- `/usr/bin/jq` to read the query JSON, as `omacchiato-spawn` does.
- Karabiner, through `bin/omacchiato-karabiner-omniwm`.
- No new dependency.

## Commands

```sh
bin/omacchiato-test                                   # bash -n, unittest, swift test
bash -n bin/omacchiato-herdr bin/omacchiato-spawn
~/.local/bin/omacchiato-omni query windows | /usr/bin/jq '.result.payload.windows[] | {id, app: .app.bundleId, title}'
~/.local/bin/omacchiato-omni query focused-window
bin/omacchiato-karabiner-omniwm install               # rewrites the Karabiner rules
```

## Project Structure

```
bin/omacchiato-herdr                → new: focus or open the herdr window
bin/omacchiato-spawn                → passes the arguments after <App> to `open --args`
bin/omacchiato-karabiner-omniwm     → new rule: "herdr", Super+A
install.sh                          → links bin/omacchiato-herdr into ~/.local/bin
~/.local/state/omacchiato/herdr-window → the id of the hotkey's window, one line
README.md                           → the new key in the hotkey table
```

The cheatsheet (`Super+K`) reads the Karabiner rule descriptions, so it
gets the new key with no change.

## Code Style

Match `bin/omacchiato-spawn`: plain bash, `$HOME/.local/bin/` paths,
stderr to `/dev/null` on IPC calls, comments only for a reason that the
code does not show.

```bash
#!/bin/bash
# omacchiato-herdr: focus the herdr window that this script opened, or
# open one.
OMNI="$HOME/.local/bin/omacchiato-omni"
STATE="$HOME/.local/state/omacchiato/herdr-window"

id="$(cat "$STATE" 2>/dev/null)"
if [ -n "$id" ] && "$OMNI" focus-window "$id" >/dev/null 2>&1; then
  exit 0
fi
# open passes our environment to Ghostty, and herdr refuses to nest.
unset "${!HERDR_@}"
"$HOME/.local/bin/omacchiato-spawn" Ghostty --command=herdr
"$OMNI" query focused-window 2>/dev/null \
  | /usr/bin/jq -r 'select(.result.payload.window.app.bundleId == "com.mitchellh.ghostty") | .result.payload.window.id // empty' \
  > "$STATE.tmp" && [ -s "$STATE.tmp" ] && mv "$STATE.tmp" "$STATE"
```

## Testing Strategy

- The logic is one branch: focus or open. A unit test would mock all of
  it, so there is none. `bin/omacchiato-test` runs `bash -n` on the
  script.
- Manual checks on the live install, after you agree to them, because
  they open windows on your screen:
  1. No herdr window: `Super+A` opens one that runs herdr, on the
     workspace under the pointer.
  2. On another workspace: `Super+A` goes back to that window.
  3. Move the window to another display: `Super+A` still finds it.
  4. Detach or quit herdr, so the window closes: `Super+A` opens a new one.
  5. With the herdr window focused: `Super+A` opens nothing.
  6. `Super+Return` still opens a plain shell.
  7. `Super+K` lists the new key.

## Boundaries

- Always: test on the live install and commit only after you confirm it.
  Write files that the bar or another program reads through a temp file
  and a rename.
- Ask first: any test that opens windows or posts keys on your screen. A
  change to `omacchiato-omni` or to OmniWM.
- Never: post an Escape key. Run `install.sh` to test one change. Take a
  key that another rule uses.

## Success Criteria

- The seven manual checks pass.
- `bin/omacchiato-test` passes.
- Ten presses of `Super+A` leave one herdr window that the hotkey opened.
- A press on an existing window returns within 200 ms.

## Open Questions

None.
