# OmniWM notes

Findings from running omacosy on OmniWM: trial notes, the capability
audit, upgrade notes and a ledger of upstream quirks. Read the ledger
before you assume that a strange layout is omacosy's fault.

## Trial findings (2026-08-26, first live day)

- **OmniWM refuses to start alongside another window manager**, and
  its conflict dialog never checks again: launch it again after the
  other manager quits.
- **IPC socket** had to be enabled once from OmniWM's status-bar menu
  before omniwmctl worked (socket:
  ~/Library/Caches/com.barut.OmniWM/ipc.sock).
- **Dwindle ignores outer gaps** — DwindleSettings carries only
  innerGap; [gaps.outer] is Niri-only. Verified empirically (top=42
  and bottom=60 both no-ops after forced relayout; innerGap
  live-reloads fine). So the bar gets no reserved strip and lives in
  hover-reveal mode. Gap values stay in settings.toml for the day
  upstream honors them. UPSTREAM ISSUE CANDIDATE.
- **Gestures need the grant before launch** — the multitouch reader
  initializes at startup, so Input Monitoring granted mid-session
  needs an OmniWM restart to take. Cost us an hour of GUI archaeology;
  the settings file had been right all along.
- **Swipe feel**: one-switch-per-swipe by design, less smooth than
  omacosy-gesture's swipes. Trial con.
- **Vertical swipes RESTORED (2026-08-26)**: the gesture daemon runs
  with its horizontal swipes off, swipe-up fires `omniwmctl command
  toggle-overview`, and swipe-down closes via `omacosy-helper
  omniwm-overview-close` — activation-based, since OmniWM blackholes
  IPC while its overview is open and ignored synthetic Escape. Both
  live-verified. Swipe-up has since moved to omacosy-overview.
- **Phantom-bar workaround FAILED** — their workspace bar's
  reserveLayoutSpace does reserve under dwindle (measured, windows
  y=32->78), but the bar cannot be made invisible (app icons and
  workspace chips render regardless of backgroundOpacity/showLabels)
  and the reservation did not survive an OmniWM restart. Removed;
  omacosy-bar stays hover-reveal until upstream honors [gaps.outer]
  for dwindle. That upstream issue is now the ONLY path to a
  permanently visible bar.
- **Overview verdict (user)**: OmniWM's is search-and-scroll — the
  search is liked, but the old omacosy overview LAYOUT (wallpaper-zoom
  workspace cards) is preferred over their concept. Open decision:
  port our overview to an omniwmctl data source, or upstream-feature
  request a card layout, or live with theirs.
- **Menu-bar apps are awkward under omacosy**: OmniWM is menu-bar-only
  and our bar covers/hides the native bar; even _HIHideMenuBar=false +
  Dock restart did not bring it back while our bar ran. Reaching their
  GUI means parking omacosy-bar. Their GUI toggle for swipes did not
  actually persist to settings.toml in our attempt — TOML remained the
  authority.

## Capability audit (2026-08-26, four docs)

Full reference: omniwm-capabilities-{config,features,ipc,layout}.md in
this directory. Version-critical reconciliation:

- Installed 0.6.2; **0.6.3 released 2026-08-25** and audited at its
  commit (33b748b). Two findings of ours were 0.6.2-only:
  - "dwindle ignores outer gaps" — FIXED in 0.6.3: outer gaps are
    struts on the workingFrame for BOTH engines (WMController
    .layoutFrames). The bar gets its strip by upgrading. No upstream
    issue needed.
  - fullscreen-uses-outer-gaps and other keys exist only from 0.6.3.
- **0.6.3 UPGRADE TRAP**: its decoder is strict (every table complete,
  every hotkey catalog id present exactly once) and cold start
  silently moves a rejected file to settings.toml.corrupt and writes
  defaults. Our file is sparse. REQUIRED ORDER:
    1. brew upgrade omniwm (restarts the WM; expect our config to be
       rejected -> defaults, exec chords still work via Karabiner)
    2. let 0.6.3 write its full canonical defaults file
    3. patch our keys INTO that file (script the patch; comments are
       lost on GUI rewrites anyway)
    4. verify hotkeys + [gaps.outer] top -> bar strip
- Overview: theirs is hardcoded layout (zoom + 4 colors only); cannot
  be themed toward our wallpaper-card concept. Options: fork (GPL,
  cleanly layered) or external overview on IPC (feasible: queries +
  focus/switch commands exist; missing thumbnails-by-IPC means own
  ScreenCaptureKit, which omacosy-overview already does).
- IPC: bar + gesture daemon fully served; no exec, no config access,
  no close-window (Karabiner Cmd+W stays). Docs' alias section is
  unimplemented — worth reporting upstream.
- Undock: workspaces keep numbers and re-resolve home on redock
  natively; our fold-into-1-9 has no equivalent (may not be needed).
- Undocumented gem: system-wide window corner radius via
  NSConvolutionOverride defaults.

## 0.6.8 (upgraded 2026-09-08)

How it broke first: 0.6.8 moved the cask from BarutSRB/tap to
homebrew/cask, and a `brew upgrade` on 2026-09-07 21:56 replaced the
app and omniwmctl on disk UNDER the running 0.6.4 process. The server
kept speaking protocol 13 while the new CLI speaks 15, so every
omniwmctl request but `version` answered `protocol_mismatch`: bar
click-to-jump, overview card taps and the Super+Space palette chord
were all dead, and the bar's `watch workspace-bar` survived only
because its child predated the upgrade. Everything on the held client
(omacosy-omni: swipes, Super+N, bar snapshots) negotiates per
connection and never noticed. Rule: a cask upgrade is not done until
the WM has been restarted. Casks cannot be pinned, so expect this on
every `brew upgrade` that carries OmniWM.

Restart facts (0.6.4 -> 0.6.8, one quit + `open -a`): the socket
answered in ~1 s (no >10 s migration wait this time). Settings went
schema 1 -> 3 in one step with a single settings.toml.pre-v3 backup;
[[monitorRoutingOverrides]] became [routing.arrangements] (mode
"custom", one arrangement, both monitor UUIDs kept); 19 hotkeys were
added Unassigned (switchWorkspaceSlot/moveToWorkspaceSlot 1-9,
closeFocusedWindow); every key of ours survived (188 hotkeys, 18
workspaces, 13 appRules; gaps, ffm, ipc, swipe and bar keys intact).
Every real window stayed on its workspace across the restart (0.6.5's
dwindle persistence). The managed-window count fell 19 -> 10 because
Notification Centre widgets, QuickShade and omacosy-bar's own windows
are no longer admitted (0.6.5's structural eligibility). The bar did
NOT re-establish its workspace-bar watch: no launch/quit observer line
in its log and no watch child afterwards; `launchctl kickstart -k
gui/$UID/com.omacosy.bar` brought it back in 1 s. WATCH ITEM. A
round-trip next/prev through omacosy-omni was verified live and the
bar followed each switch within 15 ms.

Protocol 13 -> 15 (14 in 0.6.5, 15 in 0.6.6): a no-op switch now
answers `status: "ignored"`, `code: "no_change"`, `ok: false` — the
same falsy shape our clients already got as `not_found`, so nothing
changed for them. New IPC worth using: `window move-to-workspace <id>
<ws>` moves WITHOUT focusing (ledger #4 resolved; ws-collapse's
focus-then-verify dance can go), `command close-focused-window` (the
"OmniWM has NO close-window command" note above is obsolete),
`switch-workspace slot <n>` / `anywhere <n>`, `move-to-workspace slot
<n>`, `workspace rename`, `query metrics`, `subscribe --format
ndjson`. Upstream highlights 0.6.5-0.6.8: dwindle state survives
restarts (split orientation, ratios, tab groups); Option+drag swaps
dwindle tiles (ledger #6 resolved); monitor arrangements remembered
per desk setup; closing a dwindle window keeps you on its workspace;
focus borders track the real on-screen frame and stay rounded while
switching; fewer pauses on window switches; workspaces renamable over
IPC.

## 0.6.4 (re-upgraded 2026-08-31 evening — final)

Back on 0.6.4 for good: its stale-window retirement fix is the cure
for the Arc phantom-window accumulation that degraded 0.6.3 layouts
all day (29 ghost windows purged in the same pass). Upgrade procedure
that works: quit the old process COMPLETELY before touching settings;
first boot after migration can take >10 s before the IPC socket
appears — wait for the socket, don't diagnose at 9 s. Window map is
snapshotted by app name (window ids die with the WM session) and
restored via focus-by-id + move + verify.

## 0.6.4 (upgraded 2026-08-31)

Settings migration is automatic now (schemaVersion 1, .pre-v1 backup)
— the 0.6.3 UPGRADE TRAP procedure below is historical. IPC protocol
went 11 -> 13; our client negotiates per connection since 4bfe5c0's
follow-up, so future bumps cannot strand the stack. Ten labeled
scratchpad slots are available and unbound. Rolling back to 0.6.3
requires restoring settings.toml.pre-v1 first.

## Upstream issue ledger (file these on BarutSRB/OmniWM)

1. **Dwindle ignores [gaps.outer] on 0.6.3** — resolved settings report
   outerGapTop 42 (IPC payload) while the layout applies 0; the strut
   plumbing exists in source. Evidence: capabilities-layout doc +
   measured frames.
2. **docs/IPC-CLI.md aliases are unimplemented** — `query monitors` /
   `--monitor` rejected live; no alias code at HEAD.
3. **Overview scroll fights natural scrolling** —
   normalizedScrollDelta un-inverts isDirectionInvertedFromDevice
   (OverviewWindow.swift), hardcoded.
4. **No move-window-by-id IPC** — `command move-to-workspace` acts on
   the focused window only; external tooling must focus-then-move
   (racy). Feature ask: `window move-to-workspace <id> <ws>`.
   RESOLVED 0.6.5: `omniwmctl window move-to-workspace <opaque-id>
   <workspace>` moves without focusing.
5. **active-workspace (and focus) events fire only when the focused
   WINDOW changes** — measured 2026-08-29: the sequence 14,2,9,2,3,2
   emitted events for 3 and 2 only; every switch to OR from an empty
   workspace is silent, not just in bursts. handleSessionStateChanged's
   workspaceChanged is derived from window state. The `workspace-bar`
   channel does fire on every switch (their bar highlights empties), so
   omacosy-bar consumes that instead. Feature ask: emit
   active-workspace on the workspace change itself.
6. **Dwindle has no mouse move/swap** — MouseEventHandler's dwindle
   path guards button == .right (resize only); Option+drag move is
   Niri-only.
   RESOLVED 0.6.5: hold the mouse-move modifier (Option) and drag a
   dwindle tile to swap it.
7. (cosmetic) **Their border decorates their own command palette** —
   mismatched-radius outline; persists with borders disabled, so
   likely the palette's own edge drawing.
12. **0.6.4 REGRESSION: move-onto hides windows** — 1 left + 2 right,
   move a right window left: only two windows stay visible; the third
   parks (isVisible false, layoutReason "standard") and focusing it
   swaps which window shows, at near-fullscreen frames. Reproduced
   2026-08-31. Together with #11 this made 0.6.4 unusable; ROLLED BACK
   to 0.6.3 same day (grants survive — same signing identity; restore
   settings.toml.pre-v1 only after the 0.6.4 process is fully gone, or
   its shutdown save overwrites the restore). Do not brew upgrade
   until upstream fixes land (their HEAD commits already target this
   area).
11. RESOLVED 2026-09-01, third diagnosis correct: solo windows filled
   the RAW display because dwindle's singleWindowFit="fill" is defined
   as the FULLSCREEN frame (SingleWindowFit.usesFullscreenLayoutFrame),
   and fullscreenUsesOuterGaps=false made that frame edge-to-edge —
   deterministic config semantics, not a version regression and not
   poisoning. Fix: fullscreenUsesOuterGaps=true; solo windows and
   Super+F fullscreen both keep the bar strip now (pixel-verified on
   both displays); native fullscreen stays edge-to-edge. The earlier
   retraction text below stands as a record of the wrong turns.
   RETRACTED as a 0.6.4 regression; re-diagnosed 2026-08-31. Two real
   causes, both version-independent: (a) dwindle `move.*` is
   groupWindow(into: neighbor) BY DESIGN — a directional move STACKS
   into the neighbor's cell (12px member strip), it never swaps; the
   true swap is moveColumn.* -> swapWindow on dwindle. We rebound
   Hyper+arrows to moveColumn.* (swap) and parked stacking on
   Control+Option+Shift+arrows. (b) workspace-state POISONING: windows
   closing while OmniWM is mid-restart leave stale tiles that corrupt
   that workspace's tree (raw-display frames, phantom hides) until it
   empties — upstream HEAD is actively fixing this ("prevent AX
   mismatches from poisoning layout constraints", "retire stale
   tiles"). The 0.6.3 rollback was, in hindsight, unnecessary; staying
   on 0.6.3 until the poisoning fixes ship in a release, then
   re-upgrade (settings migration + protocol negotiation both ready).
9. **Dwindle vertical insertion is top, not bottom** — with smartSplit
   off, planSplit returns newFirst=false ("new is second") and
   splitRect places the first child at minY; frames are y-up, so the
   new window lands ABOVE the existing one. Horizontal splits go right
   as expected. Hyprland's force_split=2 (omarchy) is right/bottom, so
   the spiral never reads as the omarchy staircase. Measured 2026-08-28
   with tty-timestamped spawns; `command preselect down` over IPC
   yields the bottom placement (one-shot). Feature ask: a
   newWindowPosition knob, or flip the vertical default.
8. (watch) **Silent self-relaunch at 03:34 2026-08-26** — no crash
   report, no known trigger; not yet reproducible.

## Root cause of the pill/overshoot saga (2026-08-26)

Four stacked bugs, each masking the next: `omacosy-ws next` parsed
"next" as a slot so the cycle logic was dead code; isFocused goes dark
on empty workspaces; omniwmctl pretty-prints multi-line JSON that a
per-line parser silently rejects; and — the last one standing —
**OmniWM's active-workspace event channel skips empty-workspace
switches during bursts** (measured: focus-name 8/9 returned
`executed`, no event arrived, the pill froze while the screen showed
the empty workspace). The bar cannot trust that stream alone, so it
follows the workspace-bar channel, which fires on every switch. Ledger
#5 tracks the upstream issue.

## Stability watch (2026-08-26, late)

OmniWM relaunched itself at 03:34 with no crash report and no known
trigger — during its downtime swipes failed with dead-socket warnings
and recovered on their own when it returned. Watch for recurrence;
if it repeats, `log show --predicate 'process == \"OmniWM\"'` around
the restart is the first stop. Degraded behavior during a WM restart
is acceptable-by-design; silent WM restarts are not.

## Next session (in order)

1. **Apple Development certificate** (Xcode -> Settings -> Accounts ->
   Manage Certificates -> +). Tonight cost five re-grants; this ends
   the class.
2. Mirror the LIVE ~/.config/omniwm/settings.toml (full canonical,
   0.6.3-proof) into config/omniwm/settings.toml — the repo still
   carries the sparse file that 0.6.3 rejects. Then make install.sh
   provision it with a key-patch step rather than a plain copy.
3. Upstream issues: dwindle outer-gaps resolved-but-not-applied
   (payload says 42, layout applies 0 — full evidence in this doc),
   and the unimplemented alias section in docs/IPC-CLI.md.
4. theme-set writes overview backdrop/border colors (option 1 of the
   overview plan).

## Remaining

1. **Verification pass.** Map the rest of the omarchy scheme into
   `[[hotkeys]]`: resize, fullscreen, float toggle, split toggle,
   window throws between monitors, workspace throw. Needs the complete
   hotkey id list from `Sources/OmniWM/Core/Input/DefaultHotkeyBindings.swift`.
   Also `[[appRules]]` seeding: messengers/media to the secondary-set
   workspaces so the "apps per screen" survive restarts.
2. **Verification pass.** Spawn-flicker behaviour vs our serialized
   spawn, Ghostty titlebar interplay.

## Open questions

- Retire omacosy-overview for OmniWM's, or keep ours for the themed
  look? (Theirs has search and drag; ours matches the wallpaper zoom.)
