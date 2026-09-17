# OmniWM feature subsystems — source audit

Audited from source: `github.com/BarutSRB/OmniWM` @ `33b748b` ("Release 0.6.3", 2026-08-24).
All paths relative to the repo root. Read-only audit; claims cite the file they come from.
Companion doc: config-key inventory is covered by a separate audit; this one is about *behavior*.

---

## 1. Quake terminal (libghostty)

**What it embeds.** A real embedded terminal built on Ghostty's C API (libghostty). It is
**statically linked**: `Package.swift` declares `.binaryTarget(name: "GhosttyKit", path: "Frameworks/GhosttyKit.xcframework")`,
and `Scripts/build-metadata.env` pins the artifact as `libghostty-internal.a` with a SHA-256.
`Scripts/ghostty-preflight.sh` is a **build gate** (verifies arch=arm64 + digest), not a runtime probe.
The framework is gitignored ("prepared outside git", `docs/ARCHITECTURE.md`) and shipped as a separate
release asset (`Scripts/omniwm_release.py`). There is no dlopen, no weak link, no fallback —
`Core/Diagnostics/PrivateAPIHealthDiagnostics.swift` says it outright: "statically linked; surface
lifecycle not probed". Runtime init failures (`ghostty_init`, `ghostty_config_new`, `ghostty_app_new`)
log and leave `window == nil`, making the hotkey a silent no-op (`QuakeTerminal/QuakeTerminalController.swift`).

**Capabilities.**
- **Tabs**: `QuakeTerminal/QuakeTerminalTab.swift` + a hand-drawn NSView tab bar
  (`QuakeTerminalTabBar.swift`, 28 pt, hidden when ≤1 tab). Closing the last tab hides the panel.
- **Splits**: recursive `SplitNode { leaf(GhosttySurfaceView) | split(dir, ratio, l, r) }`
  (`QuakeTerminal/SplitNode.swift`), ratios clamped 0.1–0.9, draggable 2 pt dividers with 12 pt hit
  area (`QuakeSplitContainer.swift`), equalize, directional pane navigation (nearest-center).
- **Positions**: `top/bottom/left/right/center` (`QuakeTerminalPosition.swift`); center "slide" is a
  pure alpha fade. Slide-in/out via `NSAnimationContext` + `window.animator()`, easeIn, duration =
  `quakeTerminalAnimationDuration` setting; snaps when global animations are off.
- **Monitor modes**: `mouseCursor | focusedWindow | mainMonitor` (`Core/Config/QuakeTerminalMonitorMode.swift`).
- **Appearance**: background effect `standardBlur | glassRegular | glassClear`
  (`QuakeTerminalAppearancePolicy.swift`). Glass = `NSGlassEffectView` (macOS 26) in
  `QuakeTerminalGlassView.swift`; standard blur uses the **private SkyLight API**
  `setWindowBackgroundBlurRadius` (`QuakeTerminalController.swift`). Dark/light synced into ghostty
  via `ghostty_app_set_color_scheme`.
- **Window**: borderless non-activating `NSPanel`, `.canJoinAllSpaces + .fullScreenAuxiliary`,
  registered as `SurfaceKind.quake` (`QuakeTerminalWindow.swift`, `Core/Surface/SurfaceScene.swift`).
  Option+drag moves; dragging within 8 pt of a perimeter edge resizes (min 200×100); a manual
  resize/move flips into "custom frame" mode persisted in runtime state.
- **Input bridge**: `GhosttySurfaceView` is an `NSView + NSTextInputClient` over a `CAMetalLayer`;
  keys go through `ghostty_surface_key_translation_mods` → `interpretKeyEvents` (IME) →
  `ghostty_surface_key`; mouse via `ghostty_surface_mouse_*` (`GhosttySurfaceView.swift`,
  `QuakeGhosttyInputBridge.swift`). OSC-52 clipboard read/write prompts with a Deny-default alert.

**Config.** `QuakeGhosttyConfig.swift` loads **the user's own Ghostty config**
(`ghostty_config_load_default_files` + recursive includes), then overlays a temp file containing
exactly two keys: `background-opacity` and `background-blur`. Everything else (font, theme, shell,
keybinds, scrollback) is inherited from `~/.config/ghostty/config`. OmniWM-side settings live in the
`[quakeTerminal]` TOML table (enabled, position, width/height %, animation duration, autoHide,
opacity, background effect, blur radius, monitor mode) with clamping in `Core/Config/SettingsStore.swift`.

**Triggers.** Hotkey `toggleQuakeTerminal`, default **Option+`** (`Core/Input/ActionCatalog.swift`);
IPC/CLI `omniwmctl command toggle-quake-terminal` (`Sources/OmniWMIPC/IPCAutomationManifest.swift`).
No gesture trigger. In-terminal shortcuts (Cmd+T/W/D, Cmd+1–9, Ctrl+Tab, …) are **hard-coded
keycodes** in `QuakeTerminalWindow.performKeyEquivalent` — not user-configurable.

**Can an external/custom terminal be substituted? No — hard-wired.** The split tree is typed on
`GhosttySurfaceView` (`SplitNode.swift: case leaf(GhosttySurfaceView)`); there is no pane protocol,
no "quake app bundle id" config key (the `[quakeTerminal]` TOML table has ten fields, none naming an
app — `Core/Config/CanonicalTOMLConfig.swift`), no window-adoption path, and nothing under
`QuakeTerminal/` launches or attaches to another process. The misleadingly named
`QuakeTerminalRestoreTarget.external` is only "the foreign window that had focus before the panel
opened", for focus hand-back. The nearest approximation for a custom terminal is the
**scratchpad** (`scratchpad-assign` / `scratchpad-toggle`, see §4a) plus an app rule to float it —
but that gives a corner-park show/hide of one window, not an edge slide, and none of the quake
position/opacity/auto-hide machinery. A true integration would need to de-type the pane tree, add a
non-ghostty construction path, and re-do geometry/animation against a foreign AX window
(`QuakeTerminalController.setup()/animateIn()` all guard on the owned window existing).

**Hard limits / half-built.** arm64 + macOS 26 only; can't build from a fresh clone without the
XCFramework. Single quake window; custom frame is **one global rect**
(`Core/Config/RuntimeStateStore.swift`), contradicting README's "remembers size/position per
monitor". No session restore of tabs/splits. Tab titles never update — `QuakeTerminalTab.title` is
never assigned, every tab reads "Terminal". The ghostty `action_cb` handles **only**
`CONFIG_CHANGE`/`RELOAD_CONFIG`; set-title, ghostty-keybind new-tab/split, open-URL, notifications
are all inert. IME candidate windows are positioned at the pane corner
(`firstRect(forCharacterRange:)` returns a zero rect). `QuakeTerminalWindow.initialFrame` is dead
(never assigned).

---

## 2. Command palette + clipboard history

**Modes: exactly three** — `windows | menu | clipboard` (`Core/CommandPaletteMode.swift`). There is
**no actions/commands mode** despite `docs/ARCHITECTURE.md` claiming "windows, commands, and
clipboard history": `Core/Input/ActionCatalog.swift` (which has per-action `keywords`) is never
imported by `UI/CommandPalette/CommandPaletteController.swift`. Doc drift; the infrastructure exists
but is unwired.

**Sourcing.** Windows mode snapshots `workspaceManager.allEntries()` (standard-layout windows only;
hidden apps get a "Hidden" badge, still selectable — selecting unhides + focuses). Menu mode
extracts the frontmost app's AX menu tree via `MenuAnywhereFetcher` (shared with Menu Anywhere,
§4d). Clipboard mode reads `ClipboardHistoryService.paletteItems`. Snapshot is taken once at
`show()` — no live refresh while open.

**Matching is substring, not fuzzy.** All three filters use case-insensitive
`String.range(of:)` with field penalties (title +0, appName +1000, …) — `chrm` will not match
"Chrome" (`CommandPaletteController.swift:513-633`). README's "fuzzy-search" overstates it.

**Selection.** Enter: navigate to window / `AXPress` the menu item (after focusing its app + 100 ms) /
copy-then-synthesized-⌘V paste. Shift+Enter: "summon window to the right" (Niri) or copy-only for
clipboard. The paste path is the most defensive code in the subsystem: requires lock-screen-inactive,
`AXIsProcessTrusted`, `!IsSecureEventInputEnabled`, then after 100 ms re-verifies frontmost pid *and*
focused `CGWindowID` before posting ⌘V (`CommandPaletteController.swift:992-1019`).

**Triggers.** Hotkey `openCommandPalette`, default **Control+Option+Space**; ⌘1/⌘2/⌘3 and
Tab/Shift+Tab switch modes; last mode persists in `runtime-state.json`. IPC/CLI:
`open-command-palette` (`IPCCommandRouter.swift`) — **toggle-only**: no way to open in a specific
mode, prefill a query, or drive selection over IPC.

**Extensibility: none.** No plugin/script/custom-entry mechanism; items can only be tracked windows,
AX menu items, or clipboard entries. `CommandPaletteEnvironment` (20 injectable closures) is a
compile-time test seam only.

**Rendering.** Fixed 620×430 `NSPanel` + SwiftUI `NSHostingView`, glass effect, centered on the
screen under the mouse. Mode-picker colors are hardcoded non-semantic RGB (won't follow accent/light
mode). Focus of the search field is found by walking the NSView tree for the first editable
`NSTextField` — fragile.

**Clipboard history** (`Core/Clipboard/*`, 3 files):
- Capture by **polling `NSPasteboard.general.changeCount` every 0.5 s**, reads off-main.
- Types: text, RTF, HTML, PNG/TIFF images, file URLs; multi-item pasteboards preserved.
- Privacy: respects the nspasteboard.org conventions (`ConcealedType`, `TransientType`, …) plus
  1Password/KeeWeb/TypeIt4Me markers — any such type aborts the whole capture. **Gap: secure-input
  and lock-screen are checked only on paste, not capture.**
- Persistence: **plaintext JSON** (`clipboard-history.json`, data base64) under
  `${XDG_STATE_HOME:-~/.local/state}/omniwm`, chmod 0700/0600, no encryption. Saves debounced
  250 ms; `flush()` is never called on app termination (`App/AppDelegate.swift`) so the newest clip
  can be lost on quit.
- Limits: opt-in (`clipboardHistoryEnabled` default **false**), 200 items / 8 MiB item / 64 MiB
  total (`Core/Config/SettingsExport.swift:244-247`); count/byte-bounded only, no time expiry.
  Dedup by SHA-256, repeat copies bump MRU.
- **No Settings-window UI exists** for any of this — the only in-app toggle is an "Enable" button in
  the palette's disabled state; size limits are TOML-only and undocumented in the README.
- Zero test coverage (`grep -rln ClipboardHistory Tests/` → nothing).

---

## 3. Overview

*(Read directly: `Core/Overview/OverviewRenderer.swift`, `OverviewLayoutCalculator.swift`,
`OverviewController.swift`, `OverviewWindow.swift`, `OverviewAnimator.swift`,
`OverviewInputHandler.swift`, `OverviewState.swift`, `OverviewThumbnailSizing.swift`,
`UI/OverviewSettingsTab.swift`.)*

**Rendering approach.** One borderless `NSPanel` **per monitor** at `.screenSaver` level
(`OverviewWindow.swift`); the content is a single custom `NSView` drawn **immediate-mode with
CoreGraphics/CoreText** in `draw(_:)` (`OverviewRenderer.render(...)`). No SwiftUI, no per-card
CALayers, no live window compositing. Thumbnails are static `CGImage`s captured per window via
**ScreenCaptureKit** `SCScreenshotManager.captureImage` (max 4 concurrent,
`OverviewController.captureWindowThumbnail`), sized to the projected card rect
(`OverviewThumbnailSizing.swift`). Without Screen Recording permission cards render as solid
rounded rects + info bar.

**What it shows.** A vertically scrolling stack of **workspace sections** per monitor
(`OverviewLayoutCalculator.calculateLayout`). Each section = a workspace label (SF Pro Display 16,
blue when active) above a spatial projection of that workspace's windows:
- **Niri workspaces** get a faithful column projection — translucent column containers with dividers,
  widths from column weights, tiles stacked by preferred height (`buildNiriWorkspaceProjection`,
  `NiriOverviewSnapshot`); drop zones between/beside columns for drag insertion.
- **Everything else** (Dwindle/floating) gets a scaled projection of the windows' *actual frames*,
  preserving their on-screen arrangement (`buildGenericWorkspaceSection`).
Each window card: rounded rect, thumbnail aspect-fit, a 36 pt bottom info bar with app icon + title
(SF Pro Text 12) + app name (10), hover close button, group-count badge, hover/selected border. A
centered search bar sits near the top; non-matching windows dim to 30 %.

**Interactions.** Click focuses (spring close animation interpolates each card back toward its real
frame — `OverviewWindowItem.interpolatedFrame`); click backdrop / Esc / Enter dismisses; type to
search; arrows navigate spatially, Tab cycles; Cmd+W closes the selection; scroll scrolls,
**Option+Shift+scroll live-zooms** (0.5–1.5, ±0.05 steps, `OverviewController.handleScroll`);
**Option+drag** moves a card to a workspace, an exact Niri position, or a column gap
(`OverviewState.resolveDragTarget`, `OverviewController.performDragAction`). Structural hotkeys
(move/reorder/consume/expel/workspace transfer) operate on the selection while open
(`executeStructuralHotkey`). Open/close is a spring (`SpringConfig.balanced`) driven by per-display
`CADisplayLink`s (`OverviewAnimator.swift`).

**Customization — what's real.** Exactly **five settings**: `overviewZoom` (0.5–1.5 baseline scale)
and four colors — backdrop, normal/hovered/selected border (`Core/Config/SettingsStore.swift:200-216`,
`UI/OverviewSettingsTab.swift`: one slider + four `ColorPicker`s, routed through
`OverviewRenderPalette` in `OverviewRenderer.swift`). Everything else is compile-time constants:
all other colors (card background, info bar, search bar, workspace label active/inactive, column
fills, close button, drop-target cyan) live in the private `OverviewRenderer.Colors` enum; all
geometry (corner radii, paddings, 200–400 pt thumbnail width, 16:10 aspect, info-bar height, badge
sizes) in `OverviewRenderer.Metrics` + `OverviewLayoutMetrics`; fonts are hardcoded SF Pro.

**Honest assessment vs. our wallpaper-zoom workspace-card overview.** The card/grid **concept is
hardcoded, not configurable**. There is no per-workspace wallpaper backdrop, no workspace-as-card
metaphor (workspaces are labeled *sections* in one scrolling column, not cards), and no
zoom-out-from-desktop transition — the open animation interpolates individual window rects from
their real frames, over a flat dark backdrop fill. The theming surface (5 values) cannot express any
of that; getting our layout means changing `OverviewLayoutCalculator` + `OverviewRenderer` code.
Realistic paths:
1. **Fork/patch** — the code is cleanly layered (layout calculator is pure, renderer is a static
   enum, `OverviewEnvironment` is injectable) and GPL-2.0, so a patched layout is feasible but is a
   permanent fork burden.
2. **External overview app** — feasible against the IPC surface: `windows`/`workspaces`/`displays`
   queries with frames, `subscribe` channels (`windows-changed`, `layout-changed`,
   `active-workspace`, `focused-monitor`), and `window focus` / `switch-workspace` commands
   (`Sources/OmniWMIPC/IPCModels.swift`, §7). The external app must do its own ScreenCaptureKit
   thumbnails and its own overlay window. Two caveats: events are **full snapshots with
   `bufferingNewest(1)`** (drops intermediates under load, `IPC/IPCEventBroker.swift`), and there is
   no IPC event for "overview opened" — but an external overview simply wouldn't use OmniWM's.
   **Recommendation: external.** OmniWM's overview cannot be themed toward the wallpaper-zoom
   concept; only forked.

**Triggers.** Hotkey `toggleOverview` (`Core/Input/HotkeyCommand.swift:116`); IPC/CLI
`toggle-overview` (`IPCAutomationManifest.swift:887`). **No gesture** (nothing in
`Core/Multitouch/` maps to overview). While open, most other IPC commands return
`ignored_overview` (`IPC/IPCCommandRouter.swift:324`). Overview cannot be *fed* via IPC — no data
in, no query of its state.

---

## 4. Scratchpad, groups/tabs, Hidden Bar, Menu Anywhere, mouse warp, workspace bar

### 4a. Scratchpad

**A single global per-window flag, not a workspace**: `WorldStore.scratchpadToken: WindowToken?`
(`Core/World/WorldStore.swift:59`). Exactly **one scratchpad window process-wide**; assigning a
second returns `.notFound` (`WMController.assignFocusedWindowToScratchpad`, `WMController.swift:2647`).
Assignment force-floats the window (`setManualLayoutOverride(.forceFloat)`); hiding is an
**off-screen park** (`HiddenReason.scratchpad`) with the AX element pinned first so apps that drop
off-screen windows from `kAXWindowsAttribute` (Calculator) can still be revealed
(`WMController.hideScratchpadWindow`). Toggle summons it to the active workspace of the monitor
under the pointer — it follows you across monitors (`scratchpadTarget(on:)`); if it's on another
workspace, toggle summons rather than hides. Re-invoking assign on the summoned scratchpad
un-assigns it. Extensive resilience code guards it through AX rescans, identity rekeys, and app
hides (`LayoutRefreshController.preserveScratchpadHiddenWindowsDuringFullRescan`, etc.).

Triggers: hotkeys `assignFocusedWindowToScratchpad` / `toggleScratchpadWindow` — **both ship
unassigned** (`ActionCatalog.swift:847-859`); IPC `scratchpad-assign` / `scratchpad-toggle`; the
workspace bar renders a `tray.fill` pill (secondary island only in split-notch mode) that can also
reveal it when its app is macOS-hidden. Limits: **not persisted** across restarts (zero hits in
SettingsExport/RuntimeState/restore catalog); no per-workspace/per-monitor scratchpads; no tiled
scratchpad; toggle (hotkey path) refuses when the app is macOS-hidden — only the bar path handles that.

### 4b. Groups / tabbed containers

**Dwindle groups** = a BSP leaf whose `DwindleTile` has >1 member (`Core/Layout/Dwindle/DwindleNode.swift`);
per-member fullscreen flag. Inactive members are **parked off-screen** with a deferred-hide
transaction — the previous tab is only parked after the newly revealed tab's frame verifies, with
rollback (`DwindleLayoutHandler.swift:1634`, `PendingGroupRevealTransaction`). Join = `move` toward
a geometric neighbor; extract = `move` again from inside a group (places the window on the requested
side); reorder is up/down only. **There are no dedicated group commands** — they were deliberately
deleted, and `Tests/OmniWMTests/DwindleGroupCommandContractTests.swift` locks in the absence of 12
action IDs and 6 IPC names; group behavior is folded into shared `focus`/`move` (⌥↑/↓ cycles tabs,
⌥⇧arrows join/extract). Group membership is **not persisted** (README admits this).

**Niri tabbed columns**: `ColumnDisplay { normal | tabbed }` on `NiriContainer`
(`Core/Layout/Niri/NiriNode.swift`); toggled by **⌥T** (`toggleColumnTabbed`,
`ActionCatalog.swift:554`) or IPC `toggle-column-tabbed`. Tabbed tiles all collapse to the same rect
(`NiriProjectedGeometry.swift:102`) and are **z-ordered via SkyLight**, *not* parked off-screen
(`isHiddenInTabbedMode` only suppresses animations) — a real mechanical asymmetry vs. Dwindle. Tab
cycling doesn't wrap. Consume/expel: `consume-or-expel-window-left/right` exist as IPC but are
**`.unassignable`** as hotkeys (filtered from defaults, rejected by the binding resolver) — reachable
via `move` or `consume-window-into-column`/`expel-window-from-column` (advanced, unassigned). A
tabbed column always accepts transfers (`columnCanAcceptTransfer`). Expelled windows land in a
`.normal` column (displayMode not copied). Niri tab state **is persisted**
(`PersistedNiriColumnState { displayMode, activeTileIndex }`,
`Core/Reconcile/PersistedWindowRestoreCatalog.swift:41`) — unlike Dwindle groups.

**TabRail is shared** between both (`Core/Surface/TabRail.swift`:
`TabRailOwner { niriColumn | dwindleTile }`) — a per-group borderless panel in the left gutter
(12 pt visible / 20 pt hit), vertical segments, top-down, click-to-select with staleness guards,
full accessibility (radio-button elements), excluded from screen capture. **Entirely
non-configurable**: all metrics in a private enum, colors derived from system accent/label colors;
`grep tabRail` over `Core/Config/` and `UI/` finds zero settings. No position/side option.

### 4c. Hidden Bar

**Not Bartender-style icon moving.** Concealment is a macOS **assessment-mode (proctored-exam)
lockdown assertion**: `Sources/OmniWMMenuBarAssertion/OmniWMMenuBarAssertion.m` dlopens the private
`MenuBarClientCore.framework` and drives `MBAssessmentModeConfiguration` /
`MBAssessmentModeAssertion` with an *allowlist* (running apps minus hidden ones, plus protected
system hosts and magic system-item ordinals `0...8`, `UI/HiddenBar/HiddenBarAllowlist.swift`).
**Requires macOS 27** — on the shipped floor (macOS 26) the whole subsystem is written, tested, and
inert (`UI/HiddenBarSettingsTab.swift:76`).

Reveal path: icon geometry via the undocumented `AXExtrasMenuBar` AX attribute
(`MenuBarItemLocator.swift`), glyphs by **screenshotting the menu-bar band** with ScreenCaptureKit
and cropping per item (`HiddenBarIconCaptureService.swift`; falls back to the Dock icon without
Screen Recording). Clicking a panel glyph re-reveals the app, re-resolves the item (by AX semantic
identity or pixel-identical icon; **silently no-ops if ambiguous**), then posts a **synthetic HID
click with cursor warp + restore** (`HiddenBarClickForwarder.swift`; Electron apps get `AXPress`
instead). Re-hide countdown (2–30 s, default 5) pauses while the revealed app has a menu open,
detected by polling `CGWindowListCopyWindowInfo` for pop-up-level windows (`HiddenBarMenuGuard.swift`),
with backoff, watchdog (60 s) and anti-flap (3 s window, `HiddenBarAntiFlap.swift`). While
concealing, OmniWM's own status item is replaced by a floating fallback icon panel per monitor
(`HiddenBarFallbackIconController.swift`).

Triggers: right-click/Option-click the OmniWM status item; hotkey `toggleHiddenBarPanel`
(unassigned); IPC `hidden-bar-panel`. Limits: per-app granularity only (no per-item, no ordering,
no "always hidden" tier); three private surfaces stacked (MenuBarClientCore, AXExtrasMenuBar,
magic ordinals); the panel centers under the notch in split modes.

### 4d. Menu Anywhere

Extracts the frontmost app's menu bar over AX (`Core/Menu/MenuExtractor.swift`) and pops a native
`NSMenu` **at the cursor** (`UI/MenuAnywhere/MenuAnywhereController.swift`,
`menu.popUp(at: NSEvent.mouseLocation)`); items execute via `AXPress` (app activated first, 100 ms
delay). Submenus load lazily with a **0.25 s AX messaging timeout each** and "(Unavailable)"
placeholders. Trigger: hotkey `openMenuAnywhere`, default **Control+Option+M**; IPC
`open-menu-anywhere`. No gesture/right-click trigger. While the menu tracks, a focus lease
suppresses focus-follows-mouse (`FocusPolicyEngine`, `duration: nil` — released only by cleanup).

The palette's Menu mode is a **sibling sharing `MenuExtractor`**, not a layer — and it is the weak
path: `flattenMenuItemsRecursive` has **no depth cap, no timeout, and runs synchronously on the main
thread** (`MenuExtractor.swift:120-176`), so ⌘2 against a wedged app freezes the UI for the full AX
timeout; it also *excludes* disabled items, separators, and the Apple menu, and misses apps that
populate submenus on open. Fails silently (no feedback) for apps with no AX menu bar.

### 4e. Mouse warp

Three independent features in `Core/Controller/MouseWarpHandler.swift` / `MouseWarpGeometry.swift` /
`MouseContainment.swift`:
1. **Edge warp** (default on): pointer-motion-only; crossing a monitor edge within
   `mouseWarpMargin` (default 1 px) warps the cursor to the opposite edge of the **routed** adjacent
   monitor (OmniWM's own arrangement, not macOS's), preserving proportional position, with a 16 pt
   corner-safety inset and a 50 ms cooldown. `CGWarpMouseCursorPosition` + a synthetic
   `.mouseMoved`. Not triggered by focus/workspace/monitor changes.
2. **Cursor containment** ("Constrain Cursor to Arrangement", default off, requires custom routing):
   walls off pointer crossings that the routing graph doesn't allow, clamping to the source edge.
   Deliberately best-effort — degrades to allow on incomplete layouts, exact diagonals, unreachable
   monitors, or >1 s stale samples.
3. **Focus warp** (`moveMouseToFocusedWindow`, default off): centers the cursor on the newly focused
   window (`WMController.moveMouseToWindow`), suppressed when the focus originated from a mouse
   click, when the cursor is already inside, or off-screen; intent-ledger gated. **Niri-only on the
   layout path** — Dwindle only gets it via the AX focus-confirmation path.
Programmatic cursor moves (focus warp, hidden-bar click forwarder) call
`noteProgrammaticCursorMove` so edge warp/containment don't misfire.

### 4f. Workspace bar

Per-monitor floating pill bars (`UI/WorkspaceBar/*`): workspaces with app icons (tiled / floating
groups separated), monospaced labels, focus glow, window-count badges, red eye-slash badges for
macOS-hidden windows (selecting unhides + focuses), scratchpad pill, optional system-stats button.
Positions: overlapping or below the menu bar; window level configurable; ±offsets; **notch modes**
including split-active-left/right (two islands around the notch, active workspace alone on one
side, `WorkspaceBarGeometry.swift`). Can reserve layout space (top inset fed into tiling).

**No timed auto-hide** — instead: (1) a **modifier-hold reveal** (any combination of
⌃⌥⌘⇧, hold-delay 0–1000 ms; while reveal mode is active the reserved inset is forced to 0 so the bar
always overlays — `WMController.swift:1089/1157`), and (2) a manual per-monitor toggle
(`toggle-workspace-bar`, in-memory only, lost on restart).

Interactions are **click-only** — no scroll-to-switch-workspace, no drag-and-drop (zero
`scrollWheel`/drag hits under `UI/WorkspaceBar/`). Dedupe mode pops a window-list sheet per app icon.

Icon pipeline: overrides map bundle id → file path or `bundle-resource:Name`
(`WorkspaceBarIconOverrideSource.swift`); the settings picker *discovers* candidate icons by parsing
Info.plist and shelling out to **`/usr/bin/assetutil --info Assets.car`** (3 s timeout) to enumerate
asset-catalog renditions, scored heuristically (`WorkspaceBarAppIconDiscovery.swift`). Zero runtime
cost when no overrides exist. No file watching (explicit Replace to reload).

Config depth: ~14 per-monitor-overridable settings (enabled, labels, floating, dedupe, hide-empty,
reserve space, notch mode + zone, position, level, height 20–40, opacity 0–0.5, X/Y offsets);
accent/text color, stats button, exclusions, icon overrides, and reveal settings are **global-only**.
**No font config** (hardcoded monospaced caption). Limits: no overflow handling in single-island
mode (a busy bar pushes off-screen rather than clipping/scrolling); manual hides not persisted;
`titlePreferFast` AX round trip per window per refresh.

---

## 5. Rules engine

**Matchers** (user-configurable, `Core/Config/AppRule.swift` compiled in
`Core/Rules/WindowRuleEngine.swift:304-344`): `bundleId` (exact, case-insensitive),
`appNameSubstring`, `titleSubstring`, `titleRegex` (unanchored `NSRegularExpression`), `axRole`,
`axSubrole` (both exact, case-sensitive). Title substring and regex are mutually exclusive. **No
size matcher, no modal/dialog matcher** (only indirectly via `axSubrole = "AXDialog"`). Rules with
only AX matchers or no effect are dropped at rebuild. Conflicts: highest specificity (bundleId +2,
others +1), then list order; user pool consulted before built-ins.

**Decisions a user rule can make — five fields only**: `layout` (auto/tile/float),
`assignToWorkspace` (by name; workspace must already exist; effectively **one-shot per app** — only
the first window of an app is routed unless via explicit `rule apply`,
`Core/Workspace/PlacementResolver.swift:156`), `initialContainerPrimarySpan` (Niri, 0.05–1.0),
`minWidth`, `minHeight`. **Not expressible**: unmanaged/ignore, opacity, border, monitor assignment,
scratchpad/quake assignment, tabbed placement, float position. `.unmanaged` is reserved for built-ins.

**Built-ins** (evaluated around user rules, `WindowRuleEngine.decision`): help tags and input-method
panels → unmanaged **before user rules, not overridable** (IME set auto-discovered by scanning
`/Library/Input Methods` etc., `Core/Rules/InputMethodBundleRegistry.swift`); then user rules; then
default-float apps (`Core/Ax/DefaultFloatingApps.swift`: System Settings, Simulator, Calculator, …),
Firefox/Zen picture-in-picture, Steam, CleanShot overlays (WindowServer level 103), transient-widget
detection using WindowServer parent/floating/modal tags, a hidden-title-bar registry (VS Code,
qutebrowser), and finally a button-based float heuristic. Built-in *rules* are overridable by an
explicit user tile/float; the registries are constructor-injectable **test seams only** (production
uses `WindowRuleEngine()` with no args).

**Lifecycle**: evaluated at admission; continuous re-evaluation (e.g. on title change) happens
**only if some rule uses advanced matchers** — bundle-id-only rule sets ignore title changes
entirely (`AXEventHandler.scheduleWindowRuleReevaluationIfNeeded`). 25 ms debounce,
world-sequence staleness guards.

**IPC**: `rule add/replace/remove/move/apply` + `rules`/`rule-actions` queries
(`IPC/IPCRuleRouter.swift`). IPC-added rules are **persistent** (written to `settings.toml` via
`SettingsStore.appRules didSet → scheduleSave`). `IPCRuleValidator` requires an identifying matcher
+ at least one effect. `rule apply` is the only way to re-apply workspace assignment to a running
app. No IPC listing of built-ins, no enable/disable flag, no dry-run query (a decision inspector
exists only in the UI, `UI/AppRuleEditor.swift`).

---

## 6. Animations

**What animates, with what**: window frames are moved by **real AX writes every tick** — no CALayer
proxies; each `CADisplayLink` tick rebuilds the layout plan and calls
`axManager.applyFramesParallel` (`Core/Controller/LayoutDiffExecutor.swift`). Niri viewport scroll =
spring / deceleration / live gesture (`Core/Animation/AnimationDriver.swift`); column/window
moves + tab transitions = `SpringAnimation` via `MoveAnimation`; column width = spring; Dwindle
relayout = the sole `CubicAnimation` user (`CubicConfig.hyprlandDwindle`, 0.2 s, Hyprland's curve);
window close = a small upward spring on a dedicated `.closing` AX lane; **there is no window-open
animation** (new windows snap in, only neighbors are displaced). Overview = spring on a drawn
progress value; Quake = AppKit `window.animator()`. **Workspace switches are not animated** — the
source stops, windows park/unpark.

**Pacing**: per-display `CADisplayLink`s created lazily and torn down when idle
(`Core/Controller/LayoutRefreshController+DisplayLink.swift`); all tick families batched in **one
SkyLight transaction per frame**; math evaluated at `targetTimestamp`. Refresh rates are sampled per
display but **nothing adapts to them** — the `displayRefreshRate` parameter is threaded through five
layers into `SpringAnimation` and never read (dead ProMotion seam); a 120 Hz panel just costs 2× the
AX writes. Backpressure is handled downstream: per-window write mailboxes coalesce (newest wins),
a frame ledger dedupes writes within 1 pt, verification is skipped on animation ticks, and each app
has its own AX thread so one hung app can't stall the link.

**One spring feel in the whole product**: all three named presets are identical
(dampingRatio 1.0, stiffness 800). **User-tunable knobs: exactly two** — the global
`animationsEnabled` toggle and `quakeTerminalAnimationDuration`. No stiffness/duration/curve is
reachable from TOML or UI. Disable is honored deeply (in-flight animations cancelled, gestures still
track). **System Reduce Motion is not consulted anywhere** — the clearest accessibility gap.

Diagnostics exist but don't act: `AnimationTickRecorder` computes a dropped-frame heuristic that
nothing reads; `AXWriteLatencyRecorder` breaks out per-write cost including the
AXEnhancedUserInterface (Electron) tax, but excludes the closing lane.

---

## 7. IPC / CLI surface (cross-cutting)

Unix socket (`$OMNIWM_SOCKET` or `~/Library/Caches/com.barut.OmniWM/ipc.sock`), newline-delimited
JSON, protocol v11; peer-uid check + per-launch bearer token in a 0600 `.secret` file; **off by
default** (`Sources/OmniWMIPC/IPCSocketPath.swift`, `IPC/IPCServer.swift`). `omniwmctl` is fully
manifest-driven (`IPCAutomationManifest.swift` generates usage + shell completions).

- ~110 commands (focus/move/column/workspace/monitor/sizing/layout + the UI surfaces:
  `open-command-palette`, `toggle-overview`, `toggle-quake-terminal`, `toggle-system-stats`,
  `toggle-workspace-bar`, `hidden-bar-panel`, `open-menu-anywhere`, `scratchpad-*`). Layout-gated
  commands return `layout_mismatch`; most mutations return `ignored_overview` while overview is open.
- Queries: `windows`/`workspaces`/`displays`/`apps`/`focused-*`/`workspace-bar`/`rules` +
  self-describing `capabilities`, with selectors and `--fields` projections. Window ids are opaque
  and session-scoped (`stale_window_id` across restarts).
- Subscriptions (for external bars/overviews): `focus`, `workspace-bar`, `active-workspace`,
  `focused-monitor`, `windows-changed`, `display-changed`, `layout-changed` — **full snapshots, not
  diffs**, buffered `newest(1)` (intermediates drop under load), and computed only while subscribers
  exist. `omniwmctl watch <channels> --exec cmd` spawns a child per event with
  `OMNIWM_EVENT_*` env vars — the intended external-integration hook (`OmniWMCtl/CLIRuntime.swift`).
- **Data-in is rules-only.** No IPC to set workspace names, icons, settings, hotkeys, palette items,
  or manual overrides; no discrete window-created/closed events; no overview/quake state events.

---

## 8. Undocumented findings (in Sources/, absent or misrepresented in README)

1. **System-wide window corner radius via secret macOS defaults.** `UI/GlobalWindowCornerPreferences.swift`
   writes `NSConvolutionOverride1` / `NSConvolutionOverride2` (standard + panel windows) into the
   **global CFPreferences domain**, radius 0–64 (0.01 = "square"), affecting *all* Mac apps after
   relaunch — surfaced in Settings as "System-wide Window Corners" (`UI/AppWindowCornerSettings.swift`)
   but nowhere in the README. This is an undocumented-Apple-key hack with system-wide blast radius.
2. **On-device LLM bug reporting.** `Core/IssueReporter/FoundationModelsIssueEngine.swift` (macOS 27,
   `-weak_framework FoundationModels`) rewrites free-form bug text into a structured GitHub issue via
   Apple's `SystemLanguageModel` with prompt templates in `Core/IssueReporter/Prompts/`. README
   documents "Report a Bug…" but not the AI rewrite.
3. **System stats popup.** `UI/SystemStats/*` — CPU ticks, memory pressure, chip/model/OS info via
   IOKit/Darwin, popup anchored to the workspace-bar button, hotkey + IPC `toggle-system-stats`.
   Zero README mentions.
4. **Hidden Bar's mechanism** (assessment-mode lockdown via private `MenuBarClientCore`, §4c) — the
   README describes the feature but not that it's an exam-lockdown assertion, that it needs three
   private surfaces, or that clicking hidden icons synthesizes HID clicks with cursor warps.
5. **Clipboard history internals**: plaintext JSON storage of clipboard contents (incl. images) on
   disk, TOML size limits, and the synthesized-⌘V paste are all undocumented; there is no Settings
   UI for it at all (§2).
6. **Secure-input monitor + indicator.** `Core/Input/SecureInputMonitor.swift` +
   `UI/SecureInputIndicator.swift` detect when a secure-input session (password field) is wedging the
   event tap and surface it. Not in README.
7. **Sleep prevention.** `Core/Sleep/SleepPreventionManager.swift` takes IOPM assertions (with
   user-session tracking). Not in README.
8. **WM conflict detection.** `App/LaunchConflictChecker.swift` detects another window manager at
   launch (Amethyst, bobrwm, glide, komorebi, Nehir, another OmniWM and more). Not in README.
9. **Mission Control gesture probe.** `UI/MissionControlGestureProbe.swift` reads `com.apple.dock` /
   trackpad defaults to detect whether macOS will steal 3/4-finger vertical swipes and deep-links to
   Trackpad settings (README only mentions the manual instruction).
10. **Native-fullscreen placeholders.** `Core/Controller/NativeFullscreenPlaceholderManager.swift`
    renders placeholder panels for windows suspended in native fullscreen, with capture exclusion.
11. **Doc drift**: the palette's documented "commands" mode doesn't exist; "fuzzy search" is
    substring matching (§2); quake "remembers size/position per monitor" is actually one global rect
    (§1); quake tab titles never update.
12. **Deliberately deleted features locked by contract tests**: dedicated Dwindle group commands
    (12 action IDs + 6 IPC names, `DwindleGroupCommandContractTests`) and the legacy
    `initialColumnWidth` rule key (ignored with a diagnostic).
13. **Dead/half-built seams worth knowing before depending on them**: `displayRefreshRate` plumbed
    into springs but never read (no ProMotion adaptation); no Reduce-Motion support; no window-open
    animation; scratchpad and Dwindle group state not persisted; `consume-or-expel` hotkeys
    unassignable by design; tab rail 100 % non-configurable.
14. **Diagnostics depth** (`Core/Diagnostics/`, 40+ files): always-on ring-buffer recorders, AX write
    latency traces, animation tick traces, runtime trace capture bundles — far beyond what "records
    an optional diagnostics trace" in the README suggests. Plus `Scripts/energy-profile.sh` for
    power profiling.
