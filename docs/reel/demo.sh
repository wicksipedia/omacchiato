#!/bin/zsh
# Drives the desktop on the empty workspaces at the end for the sizzle reel. Every step is a CLI
# call, and `key` logs the hotkey that does the same, for the on-screen labels.
# Usage: demo.sh <marks file>. record.sh runs it.
B=~/.local/bin
REPO=${0:A:h:h:h}
LOG=${1:?marks file}
: > $LOG
key() { echo "$(perl -MTime::HiRes=time -e "printf '%.2f', time")|$1|$2" >> $LOG; }
wm() { $B/omacchiato-defi "$@" >/dev/null 2>&1; }
ghostty() { open -na Ghostty --args --wait-after-command=true "$@"; }
pop() { key "" "$2"; $B/omacchiato-popup "$1"; sleep ${3:-2.6}; $B/omacchiato-popup "$1"; sleep 0.5; }

sleep 1.5

term() { ghostty --command="/bin/zsh -lc 'cd $REPO; $1; exec /bin/zsh -l'"; }
key "Super+Return" "New terminal, tiled"; term "fastfetch -s OS:Kernel:Uptime:Packages:Shell:Display:WM:Terminal:CPU:GPU:Memory:Break:Colors"; sleep 1.6
key "Super+Return" "New terminal, tiled"; term "eza --tree --level 2 --icons=always --color=always bin helper themes"; sleep 1.6
key "Super+Return" "New terminal, tiled"; term "lazygit"; sleep 2

for i in 1 2; do key "⌃⌥+←" "Scroll the columns"; wm focus-column left; sleep 0.8; done
key "⌃⌥+=" "Cycle the column width"; wm cycle-width next; sleep 1.1
for i in 1; do key "⌃⌥+→" "Scroll the columns"; wm focus-column right; sleep 0.8; done

key "⌃⌥+↓" "Switch workspace"; wm focus-workspace down; term "git log --graph --oneline --decorate --color=always -40 | cat"; sleep 1.2; wm center-column; sleep 0.6
key "⌃⌥+↓" "Switch workspace"; wm focus-workspace down; sleep 1
key "⌃⌥+↑" "Switch workspace"; wm focus-workspace up; sleep 1
key "⌃⌥+↑" "Switch workspace"; wm focus-workspace up; sleep 1.3

key "⌃⌥+O" "Overview"; wm toggle-overview; sleep 3
wm toggle-overview; sleep 1

pop clock "Calendar|Today's events at a glance" 3.2
pop weather "Weather|The next hours and days, where you are" 3.2
pop status "Battery and Wi-Fi|Join a network or your iPhone's hotspot from the bar" 3.4
pop activity "Activity|See what is slowing your Mac down" 3.2
pop claude "AI usage|Know your Claude, Codex and Copilot limits before you hit them" 3.6
pop github "Pull requests|Stay on top of reviews, checks and conflicts" 3.6

# One window on a workspace leaves the wallpaper in view, and the terminals
# take the palette, so each theme reads as a whole desktop.
key "⌃⌥+↓" "Switch workspace"; wm focus-workspace down; sleep 1.2
for i in 1 2 3 4 5; do key "Super+⇧+T" "Next theme"; $B/theme-next >/dev/null 2>&1; sleep 2.8; done
key "⌃⌥+↑" "Switch workspace"; wm focus-workspace up; sleep 1

key "Super+K" "Every shortcut"; touch /tmp/omacchiato-bar-cheatsheet; sleep 3.5
touch /tmp/omacchiato-bar-cheatsheet; sleep 0.8
