#!/usr/bin/env bash
# Omacchiato used OmniWM as its window manager, and now uses Defi. This
# stops OmniWM and removes what Omacchiato built around it. OmniWM.app and
# ~/.config/omniwm stay, so the user can go back. install.sh and
# uninstall.sh run it first. A second run does nothing.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
found=""

# Quit, not kill: OmniWM puts back the windows it parked off screen.
if pgrep -xq OmniWM; then
  osascript -e 'quit app "OmniWM"' 2>/dev/null || true
  found=1
fi
if osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
  | tr ',' '\n' | sed 's/^ *//' | grep -qx OmniWM; then
  osascript -e 'tell application "System Events" to delete login item "OmniWM"' >/dev/null 2>&1 || true
  found=1
fi

# The overview daemon has no launch agent. Trust the pidfile only as digits.
for pidfile in "$HOME/.local/state/omacchiato/overview.pid" "/tmp/omacchiato-overview-$(id -u).pid"; do
  [ -f "$pidfile" ] && [ ! -L "$pidfile" ] || continue
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  case "$pid" in '' | *[!0-9]*) ;; *) kill "$pid" 2>/dev/null || true ;; esac
  rm -f "$pidfile"
done
pkill -f 'omacchiato-overview --daemon' 2>/dev/null || true
rm -f "/tmp/omacchiato-overlay-active-$(id -u)" /tmp/omacchiato-ws-switch /tmp/omacchiato-overview.log

# Remove the built binaries, and the links into a clone. A file of the
# user's with the same name stays.
for name in omacchiato-overview omacchiato-omni; do
  f="$HOME/.local/bin/$name"
  [ -f "$f" ] && [ ! -L "$f" ] && { rm -f "$f"; found=1; }
done
for name in omacchiato-ws omacchiato-ws-collapse omacchiato-omniwmctl omacchiato-karabiner-omniwm; do
  f="$HOME/.local/bin/$name"
  [ -L "$f" ] || continue
  case "$(readlink "$f")" in */bin/"$name") rm -f "$f"; found=1 ;; esac
done

# A karabiner.json that install.sh keeps can still hold the OmniWM rules.
KARABINER="$HOME/.config/karabiner/karabiner.json"
if [ -f "$KARABINER" ] && grep -qE '"(omacchiato|omacosy)-omniwm:' "$KARABINER"; then
  "$REPO_DIR/bin/omacchiato-karabiner-keys" install >/dev/null && found=1
fi

if [ -n "$found" ]; then
  echo "==> Moved from OmniWM to Defi. OmniWM.app and ~/.config/omniwm are still there."
fi
