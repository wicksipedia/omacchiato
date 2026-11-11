# OmniWM layout engines — capabilities audit from source

Audited 2026-08-26 against `BarutSRB/OmniWM` HEAD (GPL-2.0). Every claim cites the
source file it was read from. Paths relative to repo root, `Sources/OmniWM/`
abbreviated as `…/`. Companion docs: `omniwm-capabilities-config.md`,
`omniwm-capabilities-ipc.md`.

Two engines exist, selected **per workspace**: `niri` (scrolling columns) and
`dwindle` (BSP). `LayoutType` = `default | niri | dwindle`
(`…/Core/Config/WorkspaceConfig.swift`); `default` resolves to the global
`defaultLayoutType`, whose built-in default is `niri`
(`…/Core/Config/SettingsStore.swift` `layoutType(for:)`,
`…/Core/Config/SettingsExport.swift` line 175).

---

## 1. Dwindle engine (`…/Core/Layout/Dwindle/*`)

### Tree model

`DwindleNode.kind` is `leaf(tile: DwindleTile?)` or
`split(orientation, ratio)` — a strict binary tree with exactly two children per
split (`…/Core/Layout/Dwindle/DwindleNode.swift`). A **leaf holds a
`DwindleTile`, which is a tab group**: `members: [DwindleTileMember]`, each
member `(token, isFullscreen)`, plus an `activeToken`. So "tabs" in dwindle are
tile-level, one visible member per leaf; fullscreen is tracked **per member**,
not per tile (`DwindleNode.swift` lines 11–90).

Per-workspace state (`DwindleWorkspaceState`: root, `leafByToken`, `tileCount`,
`selectedNodeId`, `preselection`, `excludedTokens`) lives in
`DwindleLayoutEngine.states[workspaceId]`
(`…/Core/Layout/Dwindle/DwindleLayoutEngine.swift` `ensureState`).

### Split decision logic (insertion)

`addWindow` (`DwindleLayoutEngine.swift` 307–461):

1. Target = the **selected leaf** (falls back to `root.descendToFirstLeaf()`).
2. If a **preselection** direction is set (`preselect(Direction)` hotkey,
   consumed & cleared on use), the split orientation and child order come from
   it: `left/down` puts the new window first.
3. Else if `smartSplit` (default on): Hyprland-style — compares the slope of
   the vector (active window center → target rect center) against the target
   rect's aspect ratio; `|slope| < aspect` → horizontal split, sign of delta
   decides which side the new window lands on (`planSplit`).
4. Else aspect-based: `height * splitWidthMultiplier > width` → vertical,
   otherwise horizontal (`aspectOrientation`); the new window is always second.

New splits get `ratio = defaultSplitRatio`. **Ratio scale**: ratio ∈ [0.1, 1.9]
where 1.0 = 50/50; `fraction = ratio / 2` clamped [0.05, 0.95]
(`…/Core/Layout/Dwindle/DwindleSettings.swift`). Splits **never re-derive
orientation after creation** — there is no re-flow; only explicit commands
change them.

### Removal / preserve semantics

Removing the last member of a tile collapses the leaf and **promotes the
sibling into the parent** (`cleanupAfterRemoval`, `DwindleLayoutEngine.swift`
784–810): the parent takes over the sibling's kind and children. There is no
Hyprland-style `preserve_split` option — but since orientation is only ever set
at insertion and promotion copies the sibling subtree verbatim, existing splits
keep their orientation. Removing a member of a multi-member tile just shrinks
the tab group.

### Toggle / swap / balance / ratio commands

All operate on the first visible split **ancestor** of the selection
(`DwindleLayoutEngine.swift`):

- `toggleOrientation` (hotkey `toggleSplit`) — flips that split's orientation,
  keeps ratio (2045).
- `swapSplit` — swaps the two children of that split (2284).
- `swapWindow(direction)` — geometric-neighbor tile swap
  (`swapWindowOutcome`, 1974).
- `balanceSizes` — recursively sets every visible split's ratio to 1.0
  (i.e. 50/50), min-size clamped (2246).
- `cycleSplitRatio` (mapped from the shared `cycleSizeForward/Backward` hotkeys
  via `LayoutSizable`, `…/Core/Controller/DwindleLayoutHandler.swift` 1299) —
  cycles the ancestor split's ratio through hardcoded presets
  `[0.3, 0.5, 0.7]` (2301). **Quirk, source-verified:** these presets are on
  the *ratio* scale where fraction = ratio/2, so they produce 15% / 25% / 35%
  splits, not 30/50/70. Balanced is ratio 1.0, which is not in the preset list.
- `moveSelectionToRoot(stable:)` — hoists the selected leaf to be a direct
  child of the root (2121; `dwindleMoveToRootStable` setting picks the variant,
  `…/Core/Controller/CommandHandler.swift` `moveToRootInDwindle`).
- `summonWindowRight(token, beside:)` — removes a window and re-inserts it via
  preselection `.right` next to an anchor, preserving constraints and
  fullscreen flags (2077; used by workspace-bar "summon",
  `…/Core/Controller/WindowActionHandler.swift` 894).

### Resize model

- Keyboard: `resizeAlongAxis(orientation, grow)` walks up from the selection to
  the first split of the **requested orientation** with two visible branches
  and nudges its ratio by ±`resizeStep`; `resizeFocusedWindow` uses the first
  split of *any* orientation (2174–2245). `resizeStep` is **hardcoded 0.1** in
  `DwindleSettings` — it exists in the struct but is not in the config surface
  or UI (implemented, not exposed).
- All ratio changes go through `clampedRatioRespectingMinimums` /
  `feasibleRatioRange`, which use pre-computed projected min-size facts per
  subtree (window AX min sizes + inner gaps + tab-rail width) so a resize can
  never violate a descendant's minimum (1300–1583).
- Mouse: `interactiveResizeBegin/Update/End`
  (`…/Core/Layout/Dwindle/DwindleLayoutEngine+InteractiveResize.swift`) —
  resolves up to two "controlling splits" (one per axis) from the grabbed
  edges, then converts pixel deltas to ratio deltas per axis. Fullscreen tiles
  refuse resize. Both-axis (corner) drags work.
- `splitRect` distributes min-size shortfall proportionally when the rect can't
  fit both minimums (1601).

### Groups / tabs semantics

- The **shared `move(direction)` hotkey is group/ungroup in dwindle**
  (`DwindleLayoutHandler.swift` `moveWindow`, 523): moving an ungrouped window
  toward a geometric neighbor *merges it into that neighbor's tile as a tab*
  (`groupWindow(_:into:)`); moving a grouped window *splits it back out* in the
  given direction (`ungroupWindow` re-splits the leaf with the direction as
  preselection). At the workspace edge it reports `.atWorkspaceEdge`, which the
  command layer can escalate to a cross-monitor move
  (`CommandHandler.swift` case `.move`).
- `moveGroupMember` reorders within a tile — **up/down only**; left/right
  return false (`DwindleLayoutEngine.swift` 732).
- Group focus wraps within the tile (`wrapGroupFocus`,
  `DwindleLayoutHandler.swift` 453). Group membership mutations are gated
  while pending group-reveal transactions are in flight (947–1263 — an
  async choreography that un-hides a tab before committing selection).
- Rendering: a tile with >1 visible member reserves a **left-edge tab rail** of
  `TabRailManager.tabIndicatorWidth`; the window content frame is inset by it
  (`contentFrame`, `DwindleLayoutEngine.swift` 1173). Rail geometry is emitted
  as `TabRailInfo` for the surface layer (`desiredTabRailInfos`,
  `DwindleLayoutHandler.swift` 691; `…/Core/Surface/TabRail.swift`).
- Groups are **flat**: members are a list inside one leaf tile. No nested
  groups, no group-of-groups.

### Single-window fit

With exactly one visible leaf, `singleWindowRect` applies the workspace's
`SingleWindowFit` (`DwindleLayoutEngine.swift` 903, 1646):

- `fill` → uses the **fullscreenLayoutFrame** (`usesFullscreenLayoutFrame` is
  true for `fill`, `…/Core/Config/SingleWindowFit.swift`), i.e. a lone dwindle
  window ignores outer gaps unless `fullscreenUsesOuterGaps = true`.
- `custom WxH` → centered, clamped to the working frame and to the window's
  min size.
- `container_primary_span` is declared niri-only in the UI
  (`SingleWindowFit.dwindleModes = [.fill, .custom]`) but the serializer
  accepts it for dwindle via config, where it degrades to a working-frame fill
  (`SingleWindowFit.frame` returns `workingFrame` for that mode) — implemented
  but not exposed.

### GAP model

`DwindleSettings` carries **only `innerGap`** — confirmed; there is no outer
gap anywhere in the dwindle engine. `DwindleGapCalculator.applyGaps`
(`…/Core/Layout/Dwindle/DwindleGapCalculator.swift`): each tile side that
"sticks" to the tiling-area edge (2 px tolerance) gets **zero** gap; interior
sides get `innerGap / 2` each, so neighbors sum to one full gap. The tiling
area itself is the **working frame**, which already has outer gaps subtracted
upstream — see §3. So **outer gaps do apply under dwindle**; what dwindle lacks
is any engine-local outer-gap knob.

Gap resolution for dwindle (`SettingsStore.swift`
`resolvedDwindleSettings`, 1274–1294): `useGlobalGaps` (default from
`dwindleUseGlobalGaps`) picks between the shared per-monitor/global inner gap
(`resolvedGapSettings(for:).innerGap`, clamped 0–64) and a dwindle-specific
override `MonitorDwindleSettings.innerGap ?? gapSize`. **The dwindle-specific
path skips the 0–64 clamp** (minor quirk; the shared path clamps in
`resolvedInnerGap`, 1324).

### Per-monitor dwindle overrides

`MonitorDwindleSettings` (`…/Core/Config/MonitorDwindleSettings.swift`), all
optional-with-global-fallback: `smartSplit`, `defaultSplitRatio`,
`splitWidthMultiplier`, `singleWindowFit`, `useGlobalGaps`, `innerGap`.
`ResolvedDwindleSettings` is re-resolved per monitor on every layout pass and
pushed into the (single, shared) engine instance before each workspace's
calculation (`DwindleLayoutHandler.swift` `applyResolvedSettings` /
`calculationSettings` — the engine is monitor-agnostic; the handler re-stamps
settings per snapshot).

---

## 2. Niri engine (`…/Core/Layout/Niri/*`)

### Columns model

`NiriRoot` → `NiriContainer` (columns) → `NiriWindow` (rows)
(`…/Core/Layout/Niri/NiriNode.swift`). Per-column state: `displayMode`
(`normal | tabbed`), `width`/`height` as `ProportionalSize`
(`proportion | fixed`), cached pixel sizes, `presetWidthIdx`, `isFullWidth` /
`isFullHeight` with `savedWidth/savedHeight` for restore, manual
single-window overrides, and animations (move + width springs). Windows carry
`WeightedSize` (`auto(weight) | fixed | preset(index)`) for the secondary axis
and `SizingMode` (`normal | maximized | fullscreen`).

**Orientation-aware**: `NiriMonitor.orientation` (`horizontal | vertical`,
auto from aspect or per-monitor override,
`…/Core/Config/MonitorOrientationSettings.swift`) — on vertical monitors the
whole model rotates: columns become rows and the viewport scrolls vertically
(`toggleContainerPrimarySpan` delegates to `toggleContainerHeight` when
vertical, `…/Core/Layout/Niri/NiriLayoutEngine+Sizing.swift` 520). Dwindle has
no orientation concept (its splits are intrinsically 2-D).

The engine holds `monitors: [Monitor.ID: NiriMonitor]`, each owning
`workspaceRoots` and per-monitor `resolvedSettings`
(`…/Core/Layout/Niri/NiriMonitor.swift`;
`NiriLayoutEngine+Monitors.swift` `effectiveSettings` — per-monitor override,
else global).

### Viewport / scrolling

`ViewportState` (`…/Core/Layout/Niri/ViewportState.swift`):
`activeColumnIndex`, `viewOffset`, `selectedNodeId`, plus an
`OffsetTransition` (`jump | spring | deceleration`) and rebase bookkeeping.
Geometry (`ViewportState+Geometry.swift`) computes fit/centered/visible
offsets honoring `visibleContainerCount`, `centerFocusedColumn`
(`never | always | onOverflow`), and `alwaysCenterSingleColumn`.
`visibleContainerCount` is hard-clamped **1–5**
(`NiriLayoutEngine.swift` `updateConfiguration`).

ViewportState is stored **per workspace in WorkspaceManager**
(`niriViewportState(for:)`) and saved on every workspace transition
(`…/Core/Controller/WorkspaceNavigationHandler.swift` `saveNiriViewportState`,
623) — scroll position and selection survive workspace switches (in-memory
only; not persisted to disk).

`infiniteLoop`: pure index-wrapping in navigation
(`NiriLayoutEngine.swift` `wrapIndex`, 402 —
`((idx % n) + n) % n` when enabled, hard bounds otherwise), consumed by
`moveSelectionByColumns` (`NiriNavigation.swift`).

### Spans / presets

- Column primary span: presets default `[1/3, 1/2, 2/3]`
  (`…/Core/Config/BuiltInSettingsDefaults.swift`
  `niriContainerPrimarySpanPresets`), configurable, validated to ≥2 entries
  each clamped 0.05–1.0 (`SettingsStore.swift`
  `validatedContainerPrimarySpanPresets`). `defaultContainerPrimarySpan` is a
  double-optional: unset = "Auto" (`updateConfiguration`,
  `NiriLayoutEngine.swift` 463).
- Cycling: `cycleSizeForward/Backward` (shared hotkey → `LayoutSizable` →
  `toggleContainerPrimarySpan`, `…/Core/Controller/NiriLayoutHandler.swift`
  1754) — picks the next preset strictly wider/narrower than the current pixel
  width when no preset index is active (`NiriLayoutEngine+Sizing.swift` 520).
- Direct set: `setContainerPrimarySpan` / `setWindowPrimarySpan` /
  `setWindowSecondarySpan` accept `NiriSizeChange`
  (`setFixed | setProportion | adjustFixed | adjustProportion`) — full
  set-to-value API, exposed via hotkeys and IPC (`…/IPC/IPCCommandRouter.swift`
  `sizeChange(for:)`).
- `toggleContainerFullPrimarySpan` (maximize width, restoring `savedWidth`),
  `expandContainerToAvailablePrimarySpan` (grow into free viewport space),
  secondary-span set/toggle/reset, `balanceSizes`
  (`NiriLayoutEngine+Sizing.swift`, `+ColumnOps.swift`).
- Constraint solving: `NiriConstraintSolver` / axis-solve cache distribute the
  secondary axis among auto-weighted windows respecting AX min/max
  (`…/Core/Layout/Niri/NiriConstraintSolver.swift`,
  `NiriLayoutEngine.swift` `axisSolveCache`).

### Tabs

Per-column `displayMode = .tabbed` (`toggleColumnTabbed`,
`…/Core/Layout/Niri/NiriLayoutEngine+TabbedMode.swift`): all but the active
window get `isHiddenInTabbedMode = true`; entering/leaving animates windows
from/to their stacked offsets; column width re-clamps against the tab content
inset. Unlike dwindle (tabs = leaf tiles), niri tabs are whole-column.

### Column / window movement

`+ColumnOps.swift`: `moveColumn(direction)`, `moveColumnToFirst/Last/Index`,
`consumeOrExpelWindow(left/right)` (niri-style: pull the next column's window
into this column / push a window out into its own column),
`consumeWindowIntoColumn`, `expelWindowFromColumn`, `moveWindowToColumn`.
`+WorkspaceOps.swift`: `moveWindowToWorkspace`, `moveColumnToWorkspace`
(cross-workspace with sizing policy `workspaceDefault | inheritSource`).
`+ViewportCommands.swift`: `centerColumn`, `centerVisibleColumns`.

### Gestures integration

- `NiriScrollTracker` (`…/Core/Input/NiriScrollTracker.swift`) — explicit Swift
  port of niri's `scroll_tracker.rs`, accumulates wheel/trackpad deltas into
  discrete ticks.
- Continuous viewport gestures: `ViewportState+Gestures.swift` `endGesture` —
  builds snap points per column (leading/trailing pairs), applies momentum via
  `DecelerationAnimation` or spring-snaps to the nearest column boundary;
  respects `visibleContainerCount` windows and center modes.
- Interactive mouse move with a rendered drag ghost and drop-target overlay
  (`DragGhostController/Window.swift`, `SwapTargetOverlay.swift`,
  `NiriLayoutEngine+InteractiveMove.swift`); interactive edge resize
  (`InteractiveResize.swift`, `+InteractiveResize.swift`).
- Trackpad config (finger count, swipe axis, scroll style/modifier) lives in
  `…/Core/Config/GestureFingerCount.swift`, `WorkspaceSwipeAxis.swift`,
  `TrackpadScrollStyle.swift`, `ScrollModifierKey.swift`; multitouch source in
  `…/Core/Multitouch/*`. None of this exists for dwindle beyond plain
  interactive resize — viewport gestures are structurally niri-only (dwindle
  has no viewport).

### Single-window fit

`resolvedSingleWindowRect` (`…/Core/Layout/Niri/NiriLayout.swift` 608):
without manual overrides, `fill`/invalid-custom use the fullscreen layout
frame, `custom` centers the box; **`containerPrimarySpan`** (the niri-only
third mode) keeps the column's resolved width/height so a lone window sits at
its preset span, centered (`centeredSingleWindowRect`). Manual width/height
overrides (`hasManualSingleWindowWidthOverride`) win over the fit mode.

### Per-monitor niri overrides

`MonitorNiriSettings` (`…/Core/Config/MonitorNiriSettings.swift`):
`visibleContainerCount`, `centerFocusedColumn`, `alwaysCenterSingleColumn`,
`singleWindowFit`, `infiniteLoop` — resolved per monitor
(`SettingsStore.swift` `resolvedNiriSettings`, 1248) and pushed into
`NiriMonitor.resolvedSettings`.

---

## 3. Shared model

### The gap/frame pipeline — outer gaps are NOT niri-only

The "outer gaps appear niri-only" hypothesis is **wrong**; the truth is more
interesting:

1. Global `[gaps]` (`size` = inner, `outer.left/right/top/bottom`,
   `fullscreenUsesOuterGaps`) plus per-monitor `MonitorGapSettings` overrides
   resolve to `ResolvedGapSettings`
   (`…/Core/Config/MonitorGapSettings.swift`, `SettingsStore.swift`
   `resolvedGapSettings`, 1312).
2. `WMController.layoutFrames(for:scale:)`
   (`…/Core/Controller/WMController.swift` 1048) turns the **outer gaps into
   `Struts`** on `monitor.visibleFrame` (top strut = `max(0, outerGapTop −
   menuBarInset) + workspaceBarReservedInset`) and produces the
   `workingFrame`, pixel-aligned by `computeWorkingArea`
   (`…/Core/Layout/Niri/NiriLayoutEngine.swift` 53).
3. `LayoutRefreshController.buildMonitorSnapshot`
   (`…/Core/Controller/LayoutRefreshController.swift` 467) bakes
   `workingFrame` + `fullscreenLayoutFrame` into the `LayoutMonitorSnapshot`
   consumed by **both** engines — dwindle tiles into
   `snapshot.monitor.workingFrame` exactly like niri
   (`DwindleLayoutHandler.swift` 1429, `NiriLayoutHandler.swift` 1240).

So outer gaps (global and per-monitor) work identically under both engines.
What differs: `DwindleSettings`/`ResolvedDwindleSettings` carry only
`innerGap` (with the `useGlobalGaps` switch), while niri has no engine-local
gap fields at all — it receives the inner gap per pass
(`controller.innerGap(for:)`, `WMController.swift` 1033) and, notably, the
`LayoutGaps.outer` field that `NiriLayoutHandler` plumbs into the engine
(`NiriLayoutHandler.swift` 561, 1237, 3015) is **never read inside the layout
code** — `gaps.outer` has no consumer outside construction sites (verified by
repo-wide search: only `CanonicalTOMLConfig`, `IPCQueryRouter`, `WMController`,
`LayoutBoundary`, `WorkspaceManager` touch it). Dead plumbing.

`fullscreenLayoutFrame` = visibleFrame minus workspace-bar inset only, unless
`fullscreenUsesOuterGaps` (then = workingFrame) (`WMController.swift` 1064).

Engine-only vs shared settings, complete table:

| Setting | Scope | File |
|---|---|---|
| inner gap (`gaps.size`), clamp 0–64 | shared (both engines) | `SettingsStore.swift` 1324, `WorkspaceManager.swift` `setGaps` |
| outer gaps L/R/T/B | shared via workingFrame struts | `WMController.swift` 1048 |
| per-monitor gap overrides + `fullscreenUsesOuterGaps` | shared | `MonitorGapSettings.swift` |
| `singleWindowFit` | per-engine value, shared concept | `SingleWindowFit.swift` (mode `containerPrimarySpan` niri-only in UI) |
| `smartSplit`, `defaultSplitRatio`, `splitWidthMultiplier`, `useGlobalGaps`, dwindle `innerGap` | dwindle-only | `MonitorDwindleSettings.swift` |
| `resizeStep` | dwindle-only, **hardcoded** | `DwindleSettings.swift` |
| `visibleContainerCount`, `centerFocusedColumn`, `alwaysCenterSingleColumn`, `infiniteLoop`, span presets, `defaultContainerPrimarySpan` | niri-only | `MonitorNiriSettings.swift`, `NiriLayoutEngine.swift` |
| monitor orientation | niri-only effect | `MonitorOrientationSettings.swift`, `NiriMonitor.swift` |
| tab rail width | shared constant (`TabRailManager.tabIndicatorWidth`) | `DwindleLayoutHandler.swift` 1717, `…/Core/Surface/TabRail.swift` |

### Per-workspace layout choice & what survives a toggle

- `WorkspaceConfiguration { name, displayName, monitorAssignment, layoutType }`
  (`WorkspaceConfig.swift`) — layout is a **persisted per-workspace setting**,
  stored in the settings file with the workspace list.
- `toggleWorkspaceLayout` (`CommandHandler.swift` 935): flips the *active*
  workspace `niri|default → dwindle`, `dwindle → niri`, writes it back via
  `setWorkspaceLayout` (mutates `settings.workspaceConfigurations`, requests
  relayout with reason `.workspaceLayoutToggled`, publishes IPC
  `layoutChanged`). Only works for configured workspaces
  (`firstIndex(where: name == …)` guard).
- **Both engines keep their per-workspace state permanently.** Engine state is
  only dropped when the workspace itself is removed
  (`…/Core/Workspace/WorkspaceManager.swift` 3263:
  `niriEngine?.removeWorkspaceState(id)` + `dwindleEngine?.removeLayout(for:
  id)`). Toggling to niri leaves the BSP tree (groups, ratios, orientations)
  frozen in `DwindleLayoutEngine.states`; toggling back runs `syncWindows`
  (`DwindleLayoutEngine.swift` 811) which diffs tokens — windows opened while
  in niri get dwindle-inserted, closed ones removed, everything else keeps its
  tree position. Same in reverse for niri columns and the workspace's
  `ViewportState`. So a round-trip toggle restores the previous arrangement
  modulo membership changes.
- Layout partitioning per refresh: `partitionWorkspacesByLayoutType` splits the
  affected workspace set and each handler lays out only its own
  (`LayoutRefreshController.swift` 1040;
  `DwindleLayoutHandler.layoutWithDwindleEngine` re-checks
  `layoutType == .dwindle` per workspace, 368).
- Hotkey gating: every command has a `layoutCompatibility`
  (`shared | niri | dwindle`); a mismatch returns `ignoredLayoutMismatch`
  (`CommandHandler.swift` 44). Note `(.dwindle, .defaultLayout)` is treated as
  a mismatch — `default` workspaces are niri for gating purposes.

### Floating windows

- `WindowState.mode` = `tiling | floating`; `FloatingState { lastFrame,
  normalizedOrigin, referenceMonitorId, restoreToFloating }`
  (`…/Core/Workspace/WindowState.swift` 82). Floats belong to a workspace like
  tiles (hidden/shown with it), keep a monitor-relative normalized origin, and
  are re-anchored when their workspace changes monitor
  (`WorkspaceManager+MonitorRouting.swift` `translatedFloatingStates`;
  relocation frames applied by
  `LayoutRefreshController+WorkspaceMonitorTransition.swift`).
- Ways to float: app rules / `DefaultFloatingApps`
  (`…/Core/Ax/DefaultFloatingApps.swift`, `…/Core/Rules/WindowRuleEngine.swift`)
  or the manual override `toggleFocusedWindowFloating` →
  `ManualWindowOverride.forceFloat/forceTile` (`WMController.swift` 2627) —
  the override re-runs the full disposition evaluation, so rules and overrides
  compose.
- Raise: `raiseAllFloatingWindows` hotkey/IPC fronts every visible floating
  surface (including window-server modals) in z-order
  (`WindowActionHandler.swift` 187–395). There is no per-window raise-on-focus
  toggle in the layout engines; float stacking is otherwise macOS-native.
- **Scratchpad: exactly one window.** `assignFocusedWindowToScratchpad`
  refuses if a scratchpad token already exists (`WMController.swift` 2664 →
  `.notFound`); `toggleScratchpadWindow` shows/hides it on the interaction
  monitor. Assigning a tiled window force-floats it; unassigning force-tiles.

### Fullscreen (both kinds)

- **Layout fullscreen** (`toggleFullscreen`, layout-managed): dwindle sets the
  active tile member's `isFullscreen` → tile occupies `fullscreenLayoutFrame`
  (`DwindleLayoutEngine.swift` 2062, 1155); niri sets
  `window.sizingMode = .fullscreen`
  (`NiriLayoutEngine+Sizing.swift` 510). Other windows keep their slots (the
  fullscreen window just covers them). Niri additionally has
  `SizingMode.maximized` in the model (`NiriNode.swift` 13) — reachable via
  full-width/height toggles, not a separate hotkey.
- **Native macOS fullscreen** (`toggleNativeFullscreen`,
  `CommandHandler.swift` 756): sets the AX fullscreen attribute; the window
  moves to its own macOS Space, its entry is suspended from layout
  (`layoutReason = .nativeFullscreen`,
  `…/Core/Layout/LayoutBoundary.swift` `isNativeFullscreenSuspended`) and a
  **placeholder** window holds its slot in the tiling layout
  (`…/Core/Controller/NativeFullscreenPlaceholderManager.swift`,
  `WorkspaceManager+NativeFullscreenLifecycle/Topology.swift`). Exit restores
  the original slot.
- **Notch:** layout never enters it — both frames derive from
  `visibleFrame`, which excludes the menu-bar/notch band. `Monitor.notchRange`
  (`…/Core/Monitor/Monitor.swift` 145) is consumed only by the workspace bar
  to split itself around the notch
  (`…/UI/WorkspaceBar/WorkspaceBarGeometry.swift` 68). Only native fullscreen
  (macOS-managed) uses the full panel.

---

## 4. Monitors & hotplug

### Identity & model

`Monitor` = frame, visibleFrame, `hasNotch`/`notchRange`, name, `displayId`,
and a SkyLight `displayUUID`; duplicate UUIDs across monitors are discarded to
avoid ambiguous matching (`Monitor.swift` `discardingAmbiguousDisplayUUIDs`).
All per-monitor settings match by UUID first, else displayId+name, and refuse
ambiguous multi-matches (`…/Core/Config/MonitorSettingsType.swift`
`uniqueMatch` — returns nil if two entries match).

### Workspace → monitor assignment

Each configured workspace has `monitorAssignment`:
`main | secondary | specificDisplay(OutputId)` (`WorkspaceConfig.swift`),
resolved by `MonitorDescription.resolveMonitor`
(`…/Core/Monitor/MonitorDescription.swift`): `main` = the CG main display;
`secondary` = first non-main (nil with one monitor);
`specificDisplay` matches by OutputId (`…/Core/Monitor/OutputId.swift`).

Effective monitor for a workspace (`WorkspaceManager.swift`
`resolvedWorkspaceMonitorId` → `effectiveMonitor`, 3490–3583), in order:

1. the monitor currently *showing* it;
2. `runtimeMonitorOverride` (an `OutputId` set when the user moved the
   workspace to a non-home monitor at runtime; cleared when moved home);
3. the configured home;
4. nearest monitor to the workspace's last anchor point, else the first.

`moveWorkspaceToMonitor` (`WorkspaceManager.swift` 2650): moving a
**configured** workspace off its home returns `.conflict` unless `force` —
the hotkey path always forces (`CommandHandler.swift` 173), the IPC path
exposes the flag and maps `.conflict` →
`workspaceAssignmentConflict` (`IPCCommandRouter.swift` 249). Floating windows
are re-anchored to the target monitor; a replacement workspace becomes visible
on the source. `swapWorkspaceWithMonitor` swaps the two monitors' visible
workspaces (`WorkspaceNavigationHandler.swift` 484).

### Directional monitor focus & the "same-slot" behavior

Monitor-directional commands use either macOS geometry or, in
`monitorRoutingMode == .custom`, a user-defined **grid** of
`(gridColumn, gridRow)` per monitor (`…/Core/Monitor/MonitorRouting.swift`).
`completeLayout` returns nil — silently falling back to macOS geometry, not
throwing — if any current monitor has no routing entry **or two monitors
occupy the same grid cell** (`guard occupiedCells.insert(cell).inserted`).
So a same-slot conflict doesn't error; it disables the custom grid wholesale.
(The settings UI is what prevents/reports duplicates —
`…/UI/MonitorSettingsTab.swift`.)

### Connect / disconnect / reconfigure

`DisplayConfigurationObserver` diffs `NSScreen.screens` on
`didChangeScreenParameters`, debounced 100 ms, emitting
`connected | disconnected | reconfigured`
(`…/Core/Monitor/DisplayConfigurationObserver.swift`). Handling
(`…/Core/Controller/ServiceLifecycleManager.swift` 390):

- disconnect additionally cleans the niri engine's monitor record and pending
  animations (`handleMonitorDisconnect` → `cleanupRemovedMonitor`);
- every event then runs `applyMonitorConfigurationChanged`: topologies with
  zero monitors or degenerate frames are ignored (`isUsableMonitorConfiguration`)
  — a "lid closed, nothing else" blip does not destroy state;
- `WorkspaceManager.applyMonitorConfigurationChange` →
  `recordTopologyChange` → `rearrangeWorkspacesOnMonitors`
  (`WorkspaceManager.swift` 3397): snapshots which workspace was visible on
  which physical monitor (keyed by UUID, else displayId+name+geometry,
  `…/Core/Monitor/MonitorRestoreAssignments.swift`), then re-picks each
  monitor's visible workspace — exact-UUID matches first, then a greedy
  name/geometry-scored assignment, else the monitor's first assigned
  workspace;
- runtime overrides pointing at a **returning** monitor re-attach their
  workspaces to it (`runtimeOverrideReconnectAssignments`,
  `WorkspaceManager+MonitorRouting.swift` 77);
- afterwards: niri engine monitor sync, workspace GC of empty unconfigured
  workspaces, quake-terminal re-anchor.

### Mapping to Omacchiato's convention (1–9 main, 11–19 secondary)

- Workspace **names must be positive integers** (`WorkspaceIDPolicy`,
  `Sources/OmniWMIPC/WorkspaceAddressing.swift` — `normalizeRawID` requires
  `Int > 0`; `displayName` is cosmetic only). So "11–19 on secondary" encodes
  directly: configure workspaces named `11`…`19` with
  `monitorAssignment = .secondary` (or `.specificDisplay` for a pinned
  external). Built-in default is 1–5 main + 6–7 secondary
  (`BuiltInSettingsDefaults.swift`).
- **Undock:** `.secondary` resolves to nil with one monitor, so 11–19 fall
  through to the anchor-nearest/first monitor — i.e. they all collapse onto
  the internal display **keeping their numbers**. There is no folding of
  guests into free 1–9 slots and no renumbering; OmniWM never renames or
  merges workspaces at runtime. Hotkeys/bar just show more workspaces on main.
- **Redock:** home resolution (step 3 above) immediately re-resolves 11–19 to
  the secondary again; the restore-assignment pass re-picks the visible
  workspace per monitor. Runtime overrides survive the unplug and re-attach on
  replug via `runtimeOverrideReconnectAssignments`.
- Net: Omacchiato's *intent* (guests go home on redock) is native behavior; the
  *mechanism* (temporary renumber into 1–9) is impossible and unnecessary —
  the workspaces simply coexist on main under their own numbers. Anything that
  depends on "workspace 4 now holds what was on 14" has no equivalent.

---

## 5. Hard limits

Structurally impossible today, with evidence. "Not exposed" = code exists but
no config/hotkey/IPC path; "not implemented" = no code.

1. **No close-window command** — not implemented as a hotkey or IPC verb.
   `HotkeyCommand` (`…/Core/Input/HotkeyCommand.swift` 29–117) has no close
   case; IPC window requests are only `focus | navigate | summonRight`
   (`IPCCommandRouter.swift` 286). The only close path is clicking the ✕ in
   Overview, which presses the AX close button
   (`WindowActionHandler.swift` `closeWindowFromOverview`, 168).
2. **No engine-level outer-gap divergence** — outer gaps are shared
   (global + per-monitor `MonitorGapSettings`) and baked into the working
   frame for both engines; you cannot give dwindle and niri different outer
   gaps on the same monitor, and the `LayoutGaps.outer` the niri engine
   receives is dead (no reader — §3). Per-*workspace* gaps of any kind: not
   implemented (gap resolution is monitor-scoped only,
   `SettingsStore.swift` 1312).
3. **Single-window `fill` ignores outer gaps** unless
   `fullscreenUsesOuterGaps = true` — both engines, because `fill` maps to the
   fullscreen layout frame (`SingleWindowFit.usesFullscreenLayoutFrame`;
   `DwindleLayoutEngine.swift` 1646, `NiriLayout.swift` 626).
4. **Niri `visibleContainerCount` hard-clamped 1–5**
   (`NiriLayoutEngine.swift` `updateConfiguration`); inner gap hard-capped 64
   on the shared path (`SettingsStore.swift` 1324, `WorkspaceManager.swift`
   `setGaps`) — the dwindle-specific `innerGap` override path skips the cap.
5. **One scratchpad window, total** — a second assignment returns `.notFound`
   while one exists (`WMController.swift` 2664).
6. **Workspaces are numeric-only** — names must be positive integers, ordering
   is numeric (`WorkspaceIDPolicy.normalizeRawID`); named workspaces exist
   only as cosmetic `displayName`. No runtime renumbering/merging.
7. **Dwindle groups are flat, reorder is vertical-only** — members live in one
   leaf tile (`DwindleNode.swift`); `moveGroupMember` rejects left/right
   (`DwindleLayoutEngine.swift` 745). No nested groups.
8. **Dwindle tuning gaps**: `resizeStep` hardcoded 0.1 (in `DwindleSettings`
   but absent from config/UI — implemented, not exposed);
   `cycleSplitRatio` presets hardcoded `[0.3, 0.5, 0.7]` in ratio units,
   which — given `fraction = ratio/2` — yield 15/25/35 % splits rather than
   the presumably intended 30/50/70 (`DwindleLayoutEngine.swift` 2301,
   `DwindleSettings.swift` `ratioToFraction`). No set-ratio-to-value command
   for dwindle (niri has `setContainerPrimarySpan` with absolute values;
   dwindle only steps/cycles/balances).
9. **Custom monitor routing dies silently on same-slot conflicts** — duplicate
   grid cell or a monitor missing from the layout invalidates the whole
   custom grid and falls back to macOS geometry; nothing throws or warns at
   the routing site (`MonitorRouting.completeLayout`).
10. **Configured workspaces resist off-home moves** — `.conflict` without
    `force` (`WorkspaceManager.swift` 2678); mid-transition moves return
    `.stateConflict` (`isWorkspaceMonitorMoveUnsafe`).
11. **No layout persistence across restarts** — BSP trees, niri columns, and
    viewport offsets are engine memory only; disk state is limited to the
    settings file (workspace list + layoutType) and the window-restore catalog
    (`…/Core/Config/RuntimeStateStore.swift` `RuntimeState`), so a relaunch
    rebuilds layouts from scratch.
12. **Cross-engine command surface is gated, not translated** — dwindle-only
    and niri-only hotkeys are dropped (`ignoredLayoutMismatch`) on the other
    layout, and `default`-layout workspaces count as niri for gating
    (`CommandHandler.swift` 46). The same `move` binding changes meaning
    (niri: move window; dwindle: group/ungroup —
    `DwindleLayoutHandler.swift` 523).
13. **Dwindle has no viewport** — nothing scrolls; overflow protection is only
    min-size clamping. Scroll gestures, `centerColumn`, spans, infinite loop,
    and monitor orientation all have no dwindle counterpart (structural, not
    an omission).
14. **`secondary` is binary** — with ≥3 monitors, `.secondary` means "first
    non-main by sort order" (`MonitorDescription.swift`); three-monitor
    setups need `specificDisplay` assignments.
