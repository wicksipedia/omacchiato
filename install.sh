#!/usr/bin/env bash
# omacchiato bootstrap — clone this repo anywhere, run this once.
# Idempotent: safe to re-run after pulling changes.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$REPO_DIR/bin/omacchiato-banner"
export OMACCHIATO_BANNER_SHOWN=1

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

"$REPO_DIR/migrate-omacosy.sh"

# --- 0. Manifest: record what THIS machine gains ----------------------------
# uninstall.sh removes only what is recorded here, so tools and settings
# the user had before omacchiato are never touched. First run wins for
# recorded prior values; re-runs never duplicate entries.
STATE_DIR="$HOME/.local/state/omacchiato"
MANIFEST="$STATE_DIR/manifest"
mkdir -p "$STATE_DIR"
touch "$MANIFEST"
mark() { grep -qxF "$1" "$MANIFEST" || printf '%s\n' "$1" >> "$MANIFEST"; }
have() { grep -qxF "$1" "$MANIFEST" 2>/dev/null; }
export MANIFEST

# Configs are SYMLINKED into the repo so edits go live — but TCC walls
# launchd consumers (the bar and the shells it spawns)
# off from ~/Documents, ~/Desktop and ~/Downloads. A clone there makes
# every symlinked config unreadable on a machine without Full Disk
# Access, so such clones get COPIES instead (re-run install.sh after
# editing; manifest-recorded so uninstall removes them). Existing
# repo-symlinks are grandfathered — they prove this machine's grants
# already read through. OMACCHIATO_SYMLINK=1 forces symlinks.
case "$REPO_DIR" in
  "$HOME/Documents"* | "$HOME/Desktop"* | "$HOME/Downloads"*)
    if [ -n "${OMACCHIATO_SYMLINK:-}" ]; then LINK_MODE=symlink; else
      LINK_MODE=copy
      log "Clone sits under a TCC-protected folder — copying configs instead of symlinking."
      log "(clone to ~/.local/share/omacchiato for live-editable symlinks)"
    fi
    ;;
  *) LINK_MODE=symlink ;;
esac

# --- 1. Homebrew ------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  # marked AFTER the install succeeds — an aborted attempt must not
  # tell uninstall.sh that homebrew is ours to remove
  mark "installed-homebrew"
fi

# OmniWM asks to be quit before Homebrew upgrades it, because Homebrew swaps
# the app out underneath a running copy. The start step at the end of this
# script brings it back.
if pgrep -xq OmniWM && [ "$(brew outdated --cask --greedy --quiet omniwm 2>/dev/null)" = omniwm ]; then
  log "Quitting OmniWM while Homebrew upgrades it"
  osascript -e 'quit app "OmniWM"' 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq OmniWM || break; sleep 1; done
  if pgrep -xq OmniWM; then
    # a hung quit must not leave Homebrew swapping the app underneath it
    pkill -x OmniWM 2>/dev/null || true
    for _ in 1 2 3 4 5; do pgrep -xq OmniWM || break; sleep 1; done
  fi
fi

log "Installing packages (brew bundle)"
PRE_FORMULAE="$(brew list --formula 2>/dev/null | sort)"
PRE_CASKS="$(brew list --cask 2>/dev/null | sort)"
# One package failing must not abort the install: the rest of the desktop
# does not depend on it, and `set -e` would otherwise take a cask that
# merely needs sudo to adopt an existing app and turn it into a dead stop.
if ! brew bundle --file="$REPO_DIR/Brewfile"; then
  log "WARNING: some Homebrew packages failed to install (see above)."
  log "  Continuing — re-run install.sh after resolving them."
fi
# record only packages that brew bundle ACTUALLY added
comm -13 <(printf '%s\n' "$PRE_FORMULAE") <(brew list --formula 2>/dev/null | sort) \
  | while read -r f; do [ -n "$f" ] && mark "brew-formula $f"; done
comm -13 <(printf '%s\n' "$PRE_CASKS") <(brew list --cask 2>/dev/null | sort) \
  | while read -r c; do [ -n "$c" ] && mark "brew-cask $c"; done

# Every helper here is a one-file swiftc or clang build, and airpods-control
# builds from source too. Homebrew brings the Command Line Tools, so this only
# catches a Mac that has Homebrew without them.
for tool in swiftc clang; do
  command -v "$tool" >/dev/null 2>&1 && continue
  log "ERROR: $tool is missing. Omacchiato builds its helpers from source."
  log "  Install the Command Line Tools, then run install.sh again:"
  log "    xcode-select --install"
  exit 1
done

log "Checking app versions"
"$REPO_DIR/bin/omacchiato-requirements" ||
  log "WARNING: an app above is older than omacchiato needs; its settings may be rejected."

# --- 2. Symlinks ------------------------------------------------------------
# Existing non-symlink targets are backed up, never deleted. A
# pre-existing SYMLINK (dotfiles managers) is recorded in the manifest
# (tab-separated — paths can hold spaces) so uninstall can relink it.
# In copy mode (TCC-protected clone), repo sources are copied instead;
# sources OUTSIDE the repo always stay symlinks (both ends TCC-safe,
# and liveness matters — the omarchy theme dir).
link() {
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  local mode=$LINK_MODE
  case "$src" in "$REPO_DIR"*) ;; *) mode=symlink ;; esac
  if [ -L "$dst" ]; then
    local cur
    cur="$(readlink "$dst")"
    case "$cur" in
      "$src" | *omacchiato* | *omacosy*)
        # ours. Grandfather it in copy mode: a live repo-symlink
        # proves this machine's grants read through it. A link into a
        # clone that moved, or was renamed, points nowhere.
        [ "$mode" = copy ] && [ -e "$dst" ] && return
        ;;
      *) mark "$(printf 'prior-symlink\t%s\t%s' "$dst" "$cur")" ;;
    esac
  elif [ -e "$dst" ] && ! have "copied-config $dst"; then
    local bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    log "Backing up $dst -> $bak"
    mv "$dst" "$bak"
  fi
  if [ "$mode" = copy ]; then
    rm -rf "$dst"
    cp -R "$src" "$dst"
    mark "copied-config $dst"
  else
    ln -sfn "$src" "$dst"
  fi
}

# app choices for the Karabiner app chords
#
# These are READ, not sourced. apps.local.conf is a file the README
# invites you to paste values into, and `source` would execute whatever
# is in it. The values then land in ~/.config/omacchiato/apps.conf, which
# omacchiato-karabiner-omniwm sources, and inside single-quoted shell
# commands in the Karabiner rules. A name carrying a quote or a newline
# could close the string and run its own command, so anything outside a
# plain app name is refused rather than substituted.
read_apps() {
  local f="$1" line k v
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    [ "$k" = "$line" ] && continue          # no '=' on the line
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    case "$v" in
      ''|*[!A-Za-z0-9\ ._-]*)
        log "ignoring $k in $(basename "$f"): an app name cannot contain '$v'"
        continue ;;
    esac
    case "$k" in
      TERMINAL) TERMINAL="$v" ;;
      BROWSER) BROWSER="$v" ;;
      MUSIC) MUSIC="$v" ;;
      MESSENGER) MESSENGER="$v" ;;
    esac
  done < "$f"
}
read_apps "$REPO_DIR/config/apps.conf"
read_apps "$REPO_DIR/config/apps.local.conf"

log "Linking configs"
link "$REPO_DIR/zsh/zshrc"           "$HOME/.zshrc"
link "$REPO_DIR/config/starship.toml" "$HOME/.config/starship.toml"
# ghostty reads this AND its Application Support config, so personal
# settings there survive
link "$REPO_DIR/config/ghostty"      "$HOME/.config/ghostty"
# OmniWM: settings are canonical TOML, live-reloaded. OmniWM and theme-set
# both write the file, and it holds per-desk values such as display pins,
# so it is a local copy of the template, made once and never overwritten.
# A repo symlink from an earlier install becomes a copy of the same file.
if [ -L "$HOME/.config/omniwm" ] && [ "$(readlink "$HOME/.config/omniwm")" = "$REPO_DIR/config/omniwm" ]; then
  rm "$HOME/.config/omniwm"
fi
mkdir -p "$HOME/.config/omniwm"
[ -e "$HOME/.config/omniwm/settings.toml" ] || cp "$REPO_DIR/config/omniwm/settings.toml" "$HOME/.config/omniwm/settings.toml"

# Add the omacchiato keys only to a herdr config with no keys table, so keys
# that the user set stay.
if command -v herdr >/dev/null 2>&1; then
  HERDR_CFG="$HOME/.config/herdr/config.toml"
  mkdir -p "$(dirname "$HERDR_CFG")"
  touch "$HERDR_CFG"
  if ! grep -qE '^[[:space:]]*\[\[?keys[].]' "$HERDR_CFG"; then
    printf '\n' >> "$HERDR_CFG"
    cat "$REPO_DIR/config/herdr/keys.toml" >> "$HERDR_CFG"
    herdr server reload-config >/dev/null 2>&1 || true
  fi
fi

# Karabiner is COPIED, not symlinked: its background services can't read
# configs living under ~/Documents (TCC folder protection) without Full
# Disk Access. The repo copy is the source of truth on install.
mkdir -p "$HOME/.config/karabiner"
# preserve a pre-omacchiato karabiner config once, for uninstall to restore
if [ -f "$HOME/.config/karabiner/karabiner.json" ] \
  && [ ! -f "$HOME/.config/karabiner/karabiner.json.bak.omacchiato" ] \
  && ! cmp -s "$REPO_DIR/config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"; then
  cp "$HOME/.config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json.bak.omacchiato"
  mark "had-karabiner-config"
fi
cp "$REPO_DIR/config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"
launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server" 2>/dev/null || true
# Karabiner's Menu and NotificationWindow helpers are disabled the
# SUPPORTED way in karabiner.json (global.show_in_menu_bar and
# global.enable_notification_window, both false) — the bootout below
# is only the immediate cleanup for agents already running; the config
# is what survives Karabiner updates, which used to resurrect them
for agent in Karabiner-Menu Karabiner-NotificationWindow; do
  launchctl bootout "gui/$(id -u)/org.pqrs.service.agent.$agent" 2>/dev/null || true
  launchctl disable "gui/$(id -u)/org.pqrs.service.agent.$agent" 2>/dev/null || true
done
pkill -f "Karabiner-Menu|Karabiner-NotificationWindow" 2>/dev/null || true

# theme scripts on PATH (the Karabiner theme chord calls ~/.local/bin/theme-next)
mkdir -p "$HOME/.local/bin"

# tiny compiled helper (cursor position, wallpaper) — replaces the
# cliclick and desktoppr dependencies; swiftc ships with the CLT that
# Homebrew already requires
if [ ! -x "$HOME/.local/bin/omacchiato-helper" ] || [ "$REPO_DIR/helper/main.swift" -nt "$HOME/.local/bin/omacchiato-helper" ]; then
  log "Building omacchiato-helper"
  swiftc -O -F /System/Library/PrivateFrameworks -framework DisplayServices -o "$HOME/.local/bin/omacchiato-helper" "$REPO_DIR/helper/main.swift"
fi

# workspace overview overlay (4-finger swipe up)
if [ ! -x "$HOME/.local/bin/omacchiato-overview" ] || [ "$REPO_DIR/helper/overview.swift" -nt "$HOME/.local/bin/omacchiato-overview" ]; then
  log "Building omacchiato-overview"
  swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight -o "$HOME/.local/bin/omacchiato-overview" "$REPO_DIR/helper/overview.swift"
fi


# the status bar itself: one process for the surfaces, reading its own
# publishers (SkyLight, CoreAudio, IOPS, DisplayServices, SCDynamicStore,
# IOBluetooth) instead of forking scripts. The embedded Info.plist carries
# the Bluetooth usage description an unbundled binary otherwise cannot
# declare, and the agent below sets OMACCHIATO_MANAGED so it knows it may ask.
#
# It ships inside a minimal .app because macOS will not give the wi-fi
# network name to an unbundled binary: measured on 26.3, a bundled app
# with Location authorised reads the SSID and a bare Mach-O reads nil no
# matter what it is granted. The signing identifier is unchanged, so
# existing grants ride through.
#
# the plist is compiled INTO the binary AND copied in as the bundle's
# Info.plist, so a change to it alone still needs a rebuild — the usage
# strings live there and a stale binary asks for nothing
BAR_APP="$HOME/.local/share/omacchiato/omacchiato-bar.app"
BAR_BIN="$BAR_APP/Contents/MacOS/omacchiato-bar"
if [ ! -x "$BAR_BIN" ] \
  || [ -n "$(find "$REPO_DIR/helper/bar" -name '*.swift' -newer "$BAR_BIN")" ] \
  || [ "$REPO_DIR/helper/bar-info.plist" -nt "$BAR_BIN" ]; then
  log "Building omacchiato-bar"
  mkdir -p "$BAR_APP/Contents/MacOS"
  swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight -framework DisplayServices \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$REPO_DIR/helper/bar-info.plist" \
    -o "$BAR_BIN" "$REPO_DIR"/helper/bar/*.swift
fi
cp "$REPO_DIR/helper/bar-info.plist" "$BAR_APP/Contents/Info.plist"
mark "built-bar-app"
# The dwindle, borders and ffm daemons are gone. migrate-omacosy.sh stops
# them, and these are the files they left.
rm -f "$HOME/.config/omacchiato/borders.conf" "$HOME/.config/omacchiato/ffm-ignore"

# The config of AeroSpace is gone: the link, the copy in a TCC-protected
# clone, and the aerospace.toml that an older install.sh generated in the repo.
if [ -L "$HOME/.config/aerospace" ] && [ "$(readlink "$HOME/.config/aerospace")" = "$REPO_DIR/config/aerospace" ]; then
  rm "$HOME/.config/aerospace"
fi
if have "copied-config $HOME/.config/aerospace"; then
  rm -rf "$HOME/.config/aerospace"
  # without this line, every later run would delete a config written there
  { grep -vxF "copied-config $HOME/.config/aerospace" "$MANIFEST" || true; } > "$MANIFEST.tmp"
  mv "$MANIFEST.tmp" "$MANIFEST"
fi
rm -f "$REPO_DIR/config/aerospace/aerospace.toml"
rmdir "$REPO_DIR/config/aerospace" 2>/dev/null || true

# stable code identity so TCC grants survive rebuilds (skipped when no
# signing identity is present — then re-grant after each rebuild)
if security find-identity -p codesigning -v 2>/dev/null | grep -q "Apple Development"; then
  codesign -f -s "Apple Development" --identifier com.omacchiato.helper "$HOME/.local/bin/omacchiato-helper" 2>/dev/null || true
  # the BUNDLE is signed now; the identifier is what grants key on
  codesign -f -s "Apple Development" --identifier com.omacchiato.bar "$BAR_APP" 2>/dev/null || true
  codesign -f -s "Apple Development" --identifier com.omacchiato.overview "$HOME/.local/bin/omacchiato-overview" 2>/dev/null || true
else
  log "NOTE: no Apple Development signing identity found."
  log "  macOS ties permission grants to the binary's signature — without a"
  log "  stable identity, every rebuild (each install.sh re-run) invalidates"
  log "  the Accessibility/Bluetooth grants and you must re-add them in"
  log "  System Settings > Privacy & Security. Free fix: Xcode > Settings >"
  log "  Accounts > Manage Certificates > + > Apple Development, then re-run."
fi
# (omacchiato-gesture is signed in section 4, right after its build —
# the linker signs each build ad-hoc, so signing here
# would be overwritten and every rebuild would invalidate the
# Accessibility grant again)

mkdir -p "$HOME/.config/omacchiato"
# app choices, RESOLVED (apps.local.conf already applied) and copied: the
# bar's activity pill launches $TERMINAL and cannot read the repo from a
# launchd agent when the clone is TCC-protected
printf 'TERMINAL=%s\nBROWSER=%s\nMUSIC=%s\nMESSENGER=%s\n' \
  "$TERMINAL" "$BROWSER" "$MUSIC" "$MESSENGER" > "$HOME/.config/omacchiato/apps.conf"

# after apps.conf, so the injected rules launch the user's chosen apps
"$REPO_DIR/bin/omacchiato-karabiner-omniwm" install \
  || log "WARNING: the OmniWM Karabiner rules did not install. Re-run install.sh."

cat > "$HOME/Library/LaunchAgents/com.omacchiato.bar.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.omacchiato.bar</string>
  <key>ProgramArguments</key><array><string>$BAR_BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <!-- TCC judges bluetooth by the RESPONSIBLE process: started from a
       shell the bar would be killed outright for asking. Under launchd it
       is responsible for itself and may prompt, and this marker is how it
       knows the difference. -->
  <key>EnvironmentVariables</key><dict><key>OMACCHIATO_MANAGED</key><string>1</string></dict>
  <key>StandardErrorPath</key><string>/tmp/omacchiato-bar.err</string>
</dict>
</plist>
PLIST
launchctl unload "$HOME/Library/LaunchAgents/com.omacchiato.bar.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.omacchiato.bar.plist"
link "$REPO_DIR/bin/theme-set"  "$HOME/.local/bin/theme-set"
link "$REPO_DIR/bin/theme-next" "$HOME/.local/bin/theme-next"
link "$REPO_DIR/bin/theme-bg-next" "$HOME/.local/bin/theme-bg-next"
link "$REPO_DIR/bin/omacchiato-toggle" "$HOME/.local/bin/omacchiato-toggle"
link "$REPO_DIR/bin/omacchiato-ai-usage" "$HOME/.local/bin/omacchiato-ai-usage"
link "$REPO_DIR/bin/omacchiato-airpods" "$HOME/.local/bin/omacchiato-airpods"
link "$REPO_DIR/bin/omacchiato-github-prs" "$HOME/.local/bin/omacchiato-github-prs"
link "$REPO_DIR/bin/omacchiato-keep-awake" "$HOME/.local/bin/omacchiato-keep-awake"
link "$REPO_DIR/bin/omacchiato-updates" "$HOME/.local/bin/omacchiato-updates"
link "$REPO_DIR/bin/omacchiato-stats" "$HOME/.local/bin/omacchiato-stats"
link "$REPO_DIR/bin/omacchiato-ws" "$HOME/.local/bin/omacchiato-ws"
link "$REPO_DIR/bin/omacchiato-ws-collapse" "$HOME/.local/bin/omacchiato-ws-collapse"
link "$REPO_DIR/bin/omacchiato-update" "$HOME/.local/bin/omacchiato-update"
link "$REPO_DIR/bin/omacchiato-spawn" "$HOME/.local/bin/omacchiato-spawn"
link "$REPO_DIR/bin/omacchiato-karabiner-omniwm" "$HOME/.local/bin/omacchiato-karabiner-omniwm"
link "$REPO_DIR/bin/omacchiato-omniwmctl" "$HOME/.local/bin/omacchiato-omniwmctl"
link "$REPO_DIR/bin/omacchiato-herdr-worktree" "$HOME/.local/bin/omacchiato-herdr-worktree"
link "$REPO_DIR/bin/omacchiato-popup" "$HOME/.local/bin/omacchiato-popup"
link "$REPO_DIR/bin/omacchiato-permissions" "$HOME/.local/bin/omacchiato-permissions"

# omacchiato-claude-usage became omacchiato-ai-usage, whose default is the
# Claude pill. sed -i replaces a symlink with a file, so edit its target.
PLUGINS_CONF="$HOME/.config/omacchiato/bar-plugins.conf"
if [ -f "$PLUGINS_CONF" ] && grep -q 'omacchiato-claude-usage' "$PLUGINS_CONF"; then
  sed -i '' 's/omacchiato-claude-usage/omacchiato-ai-usage/g' "$(readlink -f "$PLUGINS_CONF")"
fi
OLD_USAGE="$HOME/.local/bin/omacchiato-claude-usage"
case "$(readlink "$OLD_USAGE" 2>/dev/null || true)" in *omacchiato* | *omacosy*) rm -f "$OLD_USAGE" ;; esac
if have "copied-config $OLD_USAGE"; then
  rm -f "$OLD_USAGE"
  { grep -vxF "copied-config $OLD_USAGE" "$MANIFEST" || true; } > "$MANIFEST.tmp"
  mv "$MANIFEST.tmp" "$MANIFEST"
fi
rm -f "$HOME/.config/omacchiato/claude-usage-cache.json"
if grep -qs 'omacchiato-claude-statusline' "$HOME/.claude/settings.json"; then
  log "WARNING: ~/.claude/settings.json runs omacchiato-claude-statusline, which is gone. Remove it from the statusLine command."
fi

# tokscale, for the AI usage pill. Homebrew has no formula, so
# take the macOS binary from tokscale's npm package, pinned by version and
# checksum. Change all three together.
TOKSCALE_VERSION=4.17.0
case "$(uname -m)" in
  arm64) TOKSCALE_ARCH=arm64
         TOKSCALE_SHA512="/Hmgh1VxxLdCo6ou+I7r12E0G4T4c0zzZwZ5iwdynlZKm1IEhoqPB0SagTmVEiLZSMV8zLxptO1GFuOKxMqwiQ==" ;;
  *)     TOKSCALE_ARCH=x64
         TOKSCALE_SHA512="AsAlm80CenvCv9pC/ys46Vmq7GJbgkufO2LxMAWRE5cubU4EBe0SqMew6+HpRY/BcAKJ5+4RFPQpEZS3Tx12lw==" ;;
esac
TOKSCALE_DIR="$HOME/.local/lib/tokscale-$TOKSCALE_VERSION"
if [ ! -x "$TOKSCALE_DIR/tokscale" ]; then
  log "Installing tokscale $TOKSCALE_VERSION"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/pkg.tgz" \
       "https://registry.npmjs.org/@tokscale/cli-darwin-$TOKSCALE_ARCH/-/cli-darwin-$TOKSCALE_ARCH-$TOKSCALE_VERSION.tgz" \
     && [ "$(openssl dgst -sha512 -binary "$tmp/pkg.tgz" | base64)" = "$TOKSCALE_SHA512" ] \
     && tar -xzf "$tmp/pkg.tgz" -C "$tmp" \
     && mkdir -p "$TOKSCALE_DIR" && cp "$tmp"/package/bin/* "$TOKSCALE_DIR"/; then
    # older versions go only once the new one is in place
    for old in "$HOME"/.local/lib/tokscale-*; do
      [ "$old" = "$TOKSCALE_DIR" ] || rm -rf "$old"
    done
  else
    rm -rf "$TOKSCALE_DIR"
    log "WARNING: tokscale did not install; the AI usage pill has no data."
  fi
  rm -rf "$tmp"
fi
if [ -x "$TOKSCALE_DIR/tokscale" ]; then
  ln -sfn "$TOKSCALE_DIR/tokscale" "$HOME/.local/bin/tokscale"
fi

# airpods-control, for the AirPods pill's noise control. It ships source only,
# so build the tagged release, pinned by version and checksum. Change both
# together.
AIRPODS_CONTROL_VERSION=0.4.0
AIRPODS_CONTROL_SHA256=53c7f9ed1846e2dab806301521bee8c3742149e2b4c45c9abf9b2550edd817ad
AIRPODS_CONTROL_DIR="$HOME/.local/lib/airpods-control-$AIRPODS_CONTROL_VERSION"
AIRPODS_CONTROL_BIN="$AIRPODS_CONTROL_DIR/libexec/airpods-control/airpods-control"
if [ ! -x "$AIRPODS_CONTROL_BIN" ]; then
  log "Building airpods-control $AIRPODS_CONTROL_VERSION"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/src.tgz" \
       "https://github.com/raulgg/airpods-control/archive/refs/tags/v$AIRPODS_CONTROL_VERSION.tar.gz" \
     && [ "$(shasum -a 256 "$tmp/src.tgz" | cut -d' ' -f1)" = "$AIRPODS_CONTROL_SHA256" ] \
     && tar -xzf "$tmp/src.tgz" -C "$tmp" \
     && make -C "$tmp/airpods-control-$AIRPODS_CONTROL_VERSION" install PREFIX="$AIRPODS_CONTROL_DIR" >/dev/null; then
    # older versions go only once the new one is in place
    for old in "$HOME"/.local/lib/airpods-control-*; do
      [ "$old" = "$AIRPODS_CONTROL_DIR" ] || rm -rf "$old"
    done
  else
    rm -rf "$AIRPODS_CONTROL_DIR"
    log "WARNING: airpods-control did not build; the AirPods pill shows the battery only."
  fi
  rm -rf "$tmp"
fi
if [ -x "$AIRPODS_CONTROL_BIN" ]; then
  ln -sfn "$AIRPODS_CONTROL_BIN" "$HOME/.local/bin/airpods-control"
fi

# --- 3. omarchy theme convention -------------------------------------------
# Canonical theme state lives at ~/.config/omarchy/current/theme (what the
# shell tools read).
mkdir -p "$HOME/.config/omarchy/current"

if [ ! -e "$HOME/.config/omarchy/current/theme" ]; then
  # record the pre-omacchiato wallpaper per screen (once) so uninstall can
  # put it back — theme-set is about to overwrite every display
  if ! grep -q '^wallpaper	' "$MANIFEST" 2>/dev/null; then
    i=0
    "$HOME/.local/bin/omacchiato-helper" wallpaper get 2>/dev/null | while IFS= read -r wp; do
      [ -n "$wp" ] && printf 'wallpaper\t%s\t%s\n' "$i" "$wp" >> "$MANIFEST"
      i=$((i + 1))
    done
  fi
  log "Applying default theme (tokyo-night)"
  "$REPO_DIR/bin/theme-set" tokyo-night
fi

# --- 4. Trackpad gestures (omacchiato-gesture) ---------------------------------
# The gesture engine — absorbed from aerospace-swipe (MIT, notice kept in
# helper/gesture/LICENSE.aerospace-swipe) with every omacchiato fix folded
# in — runs as a user launch agent. It serves all four directions: the
# vertical swipes open and close the overview, and the horizontal ones
# step through the workspaces over OmniWM IPC, with
# workspaceSwipeEnabled = false in settings.toml. Config is
# COPIED (launch agents can't read ~/Documents — TCC).
GESTURE_APP="$HOME/.local/share/omacchiato/omacchiato-gesture.app"
GESTURE_BIN="$GESTURE_APP/Contents/MacOS/omacchiato-gesture"
mkdir -p "$HOME/.config/omacchiato"
cp "$REPO_DIR/config/gesture/config.json" "$HOME/.config/omacchiato/gesture.json"
# the aerospace-swipe era: retire its agent, and its clone if it was ours
if [ -f "$HOME/Library/LaunchAgents/com.acsandmann.swipe.plist" ]; then
  launchctl unload "$HOME/Library/LaunchAgents/com.acsandmann.swipe.plist" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/com.acsandmann.swipe.plist"
fi
if grep -qxF "cloned-aerospace-swipe" "$MANIFEST" 2>/dev/null && [ -d "$HOME/.local/share/aerospace-swipe" ]; then
  rm -rf "$HOME/.local/share/aerospace-swipe" "$HOME/.config/aerospace-swipe"
fi
# Rebuilding this daemon COSTS ITS ACCESSIBILITY GRANT: measured on
# macOS 26.3, TCC pins the grant to the exact build (any re-sign is a
# new subject — a stable Apple Development identity does not carry it),
# so every rebuild means dead swipes until the user re-grants. The only
# safe rebuild is the one that does not happen: skip the whole block
# unless the binary is missing or a source file actually changed.
# omacchiato-omni: the scripts' held-socket client for OmniWM (plain C,
# ~3 ms launch; no grants involved, so it is simply rebuilt when stale)
G="$REPO_DIR/helper/gesture"
if [ ! -x "$HOME/.local/bin/omacchiato-omni" ] || find "$G/omniwm.c" "$G/omniwm.h" "$G/omnicli.c" "$G/yyjson.c" "$G/yyjson.h" -newer "$HOME/.local/bin/omacchiato-omni" 2>/dev/null | grep -q .; then
  # C11 lets yyjson.h and omniwm.h both declare the yyjson typedefs
  clang -std=c11 -O2 -arch arm64 -o "$HOME/.local/bin/omacchiato-omni" "$G/omniwm.c" "$G/yyjson.c" "$G/omnicli.c" -framework ApplicationServices -framework CoreFoundation \
    || echo "omacchiato-omni build failed"
fi
GESTURE_STALE=""
if [ ! -x "$GESTURE_BIN" ]; then GESTURE_STALE=1
elif find "$REPO_DIR/helper/gesture" -newer "$GESTURE_BIN" 2>/dev/null | grep -q .; then GESTURE_STALE=1
fi
if [ -n "$GESTURE_STALE" ]; then
  log "Building omacchiato-gesture (grant Accessibility + Input Monitoring when prompted)"
  launchctl unload "$HOME/Library/LaunchAgents/com.omacchiato.gesture.plist" 2>/dev/null || true
  G="$REPO_DIR/helper/gesture"
  mkdir -p "$GESTURE_APP/Contents/MacOS"
  clang -std=c11 -O3 -fobjc-arc -arch arm64 \
    -Wno-pointer-integer-compare -Wno-incompatible-pointer-types-discards-qualifiers -Wno-absolute-value \
    -o "$GESTURE_BIN" "$G/omniwm.c" "$G/yyjson.c" "$G/haptic.c" "$G/event_tap.m" "$G/main.m" \
    -framework CoreFoundation -framework IOKit -F/System/Library/PrivateFrameworks -framework MultitouchSupport \
    -framework ApplicationServices -framework Cocoa -ldl \
    || echo "omacchiato-gesture build failed"
  cp "$G/gesture-info.plist" "$GESTURE_APP/Contents/Info.plist"
  echo "APPL????" > "$GESTURE_APP/Contents/PkgInfo"
  # sign BEFORE anything launches: the only binary launchd ever starts
  # is the one the user grants
  if security find-identity -p codesigning -v 2>/dev/null | grep -q "Apple Development"; then
    codesign -f -s "Apple Development" --identifier com.omacchiato.gesture \
      --entitlements "$G/accessibility.entitlements" "$GESTURE_APP" 2>/dev/null || true
  else
    codesign -f --entitlements "$G/accessibility.entitlements" --sign - "$GESTURE_APP" 2>/dev/null || true
  fi
fi
cat > "$HOME/Library/LaunchAgents/com.omacchiato.gesture.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.omacchiato.gesture</string>
  <key>ProgramArguments</key><array><string>$GESTURE_BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>/tmp/omacchiato-gesture.log</string>
  <key>StandardErrorPath</key><string>/tmp/omacchiato-gesture.log</string>
</dict></plist>
PLIST
launchctl unload "$HOME/Library/LaunchAgents/com.omacchiato.gesture.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.omacchiato.gesture.plist" 2>/dev/null || true

# --- 5. macOS look ----------------------------------------------------------
"$REPO_DIR/macos-defaults.sh"

# --- 6. Services ------------------------------------------------------------

# OmniWM does not start beside another window manager, and quitting one
# strands the windows it parked off screen, so a running AeroSpace is
# left for the user to quit. Its login item goes, or it would take the
# next login.
if pgrep -xq AeroSpace; then
  log "WARNING: AeroSpace is running. Quit it, then start OmniWM: open -a OmniWM"
else
  log "Starting OmniWM"
  pgrep -xq OmniWM || open -a OmniWM \
    || log "WARNING: OmniWM did not start. Check the brew bundle output above."
fi
osascript -e 'tell application "System Events"
  if exists login item "AeroSpace" then delete login item "AeroSpace"
  if not (exists login item "OmniWM") then make new login item at end with properties {path:"/Applications/OmniWM.app", hidden:false}
end tell' 2>/dev/null || true

# The remapping runs in launchd-managed services; the app itself is only
# the settings window, and it costs ~92MB resident to leave open. Launch
# it only when the service is not already up — i.e. a first run, where it
# is needed to approve the driver extension.
if launchctl list 2>/dev/null | grep -q org.pqrs.service.agent.karabiner_console_user_server; then
  log "Karabiner already running (Caps Lock -> Super)"
else
  log "Starting Karabiner-Elements (approve its driver extension, then quit the app)"
  open -a Karabiner-Elements
fi

log "Checking the permissions of the bar and the gesture daemon"
"$REPO_DIR/bin/omacchiato-permissions" || log "WARNING: a permission above is still off. Run omacchiato-permissions to try again."

cat <<EOF

Done. One-time macOS steps if this is a fresh machine:
  1. Grant OmniWM     System Settings -> Privacy & Security -> Accessibility (required) and Input Monitoring (swipes)
  2. Karabiner-Elements: approve its driver extension + Input Monitoring
     when prompted (System Settings -> Privacy & Security)

Super = hold Caps Lock. Switch themes:  theme-set <name>  or  Super+Shift+T
Back to a normal Mac any time:  ./uninstall.sh
EOF
