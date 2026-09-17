#!/usr/bin/env bash
# Omacchiato was called omacosy. This moves an omacosy install to the new
# names, so install.sh and uninstall.sh know one name only. Both run it
# first. On a Mac with no omacosy install, it does nothing.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
found=""

# dwindle, borders and ffm are daemons that omacchiato no longer has
for label in bar gesture dwindle borders ffm; do
  plist="$HOME/Library/LaunchAgents/com.omacosy.$label.plist"
  [ -f "$plist" ] || continue
  found=1
  launchctl bootout "gui/$(id -u)/com.omacosy.$label" 2>/dev/null || true
  rm -f "$plist"
done
pkill -f 'omacosy-overview --daemon' 2>/dev/null || true
# logs, flags and locks of the stopped processes
rm -rf /tmp/omacosy-* "${TMPDIR:-/tmp}"/omacosy-* 2>/dev/null || true

# Remove the built binaries and the links into a clone. A file of the
# user's with the same prefix stays.
for f in "$HOME"/.local/bin/omacosy-*; do
  if [ -L "$f" ]; then
    case "$(readlink "$f")" in */bin/omacosy-*) rm -f "$f"; found=1 ;; esac
  elif [ -f "$f" ]; then
    case "${f##*/}" in
      omacosy-helper | omacosy-overview | omacosy-omni | omacosy-bar | omacosy-dwindle | omacosy-borders | omacosy-ffm)
        rm -f "$f"; found=1 ;;
    esac
  fi
done
for dir in "$HOME/.local/share/omacosy" "$HOME/.local/share/omacchiato"; do
  rm -rf "$dir/omacosy-bar.app" "$dir/omacosy-gesture.app"
done
# empty unless the clone is there
rmdir "$HOME/.local/share/omacosy" 2>/dev/null || true

for dir in .local/state .config; do
  if [ -d "$HOME/$dir/omacosy" ] && [ ! -e "$HOME/$dir/omacchiato" ]; then
    mv "$HOME/$dir/omacosy" "$HOME/$dir/omacchiato"
    found=1
  fi
done

# The user owns these files, so change only the command names in them.
# sed -i replaces a symlink with a file, so edit the file it points to.
rename_commands() {
  [ -f "$1" ] && grep -q 'omacosy' "$1" || return 0
  sed -i '' 's/omacosy-/omacchiato-/g; s/com\.omacosy\./com.omacchiato./g' "$(readlink -f "$1")"
}
rename_commands "$HOME/.config/omacchiato/bar-plugins.conf"
rename_commands "$HOME/.config/herdr/config.toml"

KARABINER_BAK="$HOME/.config/karabiner/karabiner.json.bak"
if [ -f "$KARABINER_BAK.omacosy" ] && [ ! -e "$KARABINER_BAK.omacchiato" ]; then
  mv "$KARABINER_BAK.omacosy" "$KARABINER_BAK.omacchiato"
fi

if [ -n "$found" ]; then
  echo "==> Moved the omacosy install to the omacchiato names."
  echo "    macOS asks again for the permissions of the bar and the gesture daemon."
fi
if [ "$REPO_DIR" = "$HOME/.local/share/omacosy" ]; then
  echo "==> To use the new name for the clone too, run:"
  echo "    mv ~/.local/share/omacosy ~/.local/share/omacchiato && ~/.local/share/omacchiato/install.sh"
fi
