# OmniWM configuration surface — full audit from source

Audited 2026-08-26 against `BarutSRB/OmniWM` HEAD (GPL-2.0). Every claim cites the
source file it was read from. File paths are relative to the repo root,
`Sources/OmniWM/` abbreviated as `…/`.

**Config file:** `$XDG_CONFIG_HOME/omniwm/settings.toml`, falling back to
`~/.config/omniwm/settings.toml` (`…/Core/Config/OmniWMStoragePaths.swift`,
`…/Core/Config/SettingsFilePersistence.swift`). Symlinks are followed
(`settingsTarget(for:)` resolves `S_IFLNK` via `realpath`); the target must be a
regular file or load fails.

**Runtime state (not settings):** `$XDG_STATE_HOME/omniwm/runtime-state.json`
(fallback `~/.local/state/omniwm/`) holds command-palette last mode, quake-terminal
custom frame, window-restore catalog, updater timestamps, monitor-setup status,
issue drafts (`…/Core/Config/RuntimeStateStore.swift`). Never mixed into
settings.toml.

---

## The decode pipeline (read this first)

Three layers (`…/Core/Config/SettingsTOMLCodec.swift`,
`…/Core/Config/CanonicalTOMLConfig.swift`, `…/Core/Config/SettingsStore.swift`):

1. `SettingsTOMLCodec.decode` → `TOMLDecoder` (mattt/swift-toml 2.x, the only file
   importing TOML) decodes the whole file into `CanonicalTOMLConfig`.
2. `CanonicalTOMLConfig.init(from:)` uses **`container.decode` (STRICT) for every
   top-level table and array** — `general`, `focus`, `mouseWarp`, `routing`,
   `gaps`, `niri`, `dwindle`, `borders`, `overview`, `workspaceBar`, `gestures`,
   `statusBar`, `hiddenBar`, `clipboard`, `quakeTerminal`, `appearance`,
   `hotkeys`, `workspaces`, `appRules`, and all six `monitor*Overrides` arrays.
   **A missing table or missing array = the whole file fails to decode.**
3. Inside each table, the nested structs use synthesized `Codable`: every
   non-Optional field is strict (`decode`), every Optional field is lenient
   (`decodeIfPresent`). Almost all fields are non-Optional (see per-table notes
   below for the few lenient ones). **A partial table — e.g. `[workspaceBar]`
   containing only `yOffset` — fails to decode, which rejects the entire file.**
4. Only after the whole file decodes does `SettingsStore.applyExport` run, which
   clamps/normalizes values (scroll sensitivity 0.1–100, border width 1–12,
   inner gap 0–64, notch zone 100–400, reveal hold 0–1000 ms, color components
   0–1, hidden-bar rehide 2–30 s) and falls back per-enum for invalid *string*
   enum values (`FocusLockModifier(rawValue:) ?? .off` etc.). So: **wrong enum
   string = silently replaced by that enum's default; missing key = whole file
   rejected.** There is no per-key defaulting for missing keys anywhere in the
   canonical schema.

Confirmed by tests: `testTOMLRejectsMissingRequiredKey`,
`testTOMLRejectsMissingRaiseOnMouseFocus`,
`testTOMLRejectsMissingFullscreenOuterGapPolicy`,
`testTOMLRejectsFileMissingAKnownHotkeyAction`
(`Tests/OmniWMTests/SettingsTOMLCodecTests.swift`).

**Unknown keys are NOT an error.** Unknown keys/tables are ignored on decode,
*preserved* on rewrite (`SettingsTOMLCodec.encode(_:preservingUnknownKeysFrom:)`
merges unknown key paths from the old file into the new canonical tree —
`TOMLNode.mergeUnknownKeys`), and surfaced as a diagnostics warning
(`…/Core/Diagnostics/SettingsConfigDiagnostics.swift` →
`unknownConfigKeys(keyPaths:)`). Comments and key ordering are **not**
preserved: any rewrite re-encodes from scratch with
`[.sortedKeys, .prettyPrinted]`.

### Cold start vs live reload — they diverge only on failure

Both paths call the same strict `SettingsTOMLCodec.decode`
(`…/Core/Config/SettingsFilePersistence.swift`):

| | decode succeeds | decode fails |
|---|---|---|
| **Cold start** (`load()`) | export applied | error logged; file **moved aside** to `settings.toml.corrupt` (second failure: `.corrupt.1`; both occupied: error), then **settings.toml is REWRITTEN with full defaults** and defaults applied |
| **Live reload** (`reloadIfChanged()`, fired by kqueue watchers on file + directory) | export applied via `applyExport`, `onExternalSettingsReloaded` fires | `"Ignoring invalid external settings edit …"` logged; **in-memory state kept unchanged; file left as-is on disk** |

There is no partial application on live reload either — an invalid file changes
nothing (`testMalformedExternalWorkspaceSwipeReloadDoesNotPartiallyApplyOrNotify`).

### Answer to the live mystery (sparse file "worked", then restart reset it)

A sparse settings.toml **never actually decoded** — the strict schema makes that
impossible. What the source says happened:

1. First launch with the sparse file: `load()` failed, silently moved your file
   to `settings.toml.corrupt`, wrote a full canonical defaults file, and started
   with defaults. It *looked* like it "decoded fine" because the app started
   normally and the file on disk was subsequently complete.
2. While running, values you changed (GUI or edits **to the now-complete file**)
   applied — a full canonical file with `[workspaceBar] yOffset` edited in
   decodes fine, so live reload accepted it.
3. If you then replaced the file with a sparse one again (e.g. re-provisioning
   from Omacchiato), live reload silently ignored it — in-memory state still held
   your values, so it *appeared* accepted.
4. On restart, `load()` hit the sparse file, failed, and fell back to defaults
   (rewriting the file again). Hence "live-reload accepted it but restart reset
   to defaults."

**Check for `~/.config/omniwm/settings.toml.corrupt` — its presence is the
fingerprint of this exact failure mode.** The Settings GUI Diagnostics tab also
reports it (`settingsFileCorrupt` issue).

Practical rule for Omacchiato provisioning: **never write a sparse settings.toml.**
Either let OmniWM generate the full file once and patch keys in place, or ship a
complete canonical file (every table, every key, every default hotkey id).

### When OmniWM rewrites the file

- Any settings change through `SettingsStore` (every property has
  `didSet { scheduleSave() }`) → deferred one-tick save of the **entire**
  canonical file, preserving unknown keys.
- Save is skipped when the on-disk fingerprint (dev+inode+mtime+ctime+size) and
  the export both match the last persisted state (`saveImmediately`).
- Cold start with no file → defaults written. Cold start with invalid file →
  corrupt-slot dance + defaults written (above).
- Save when the *existing* file can't be parsed (`cannotSafelyPreservePreviousData`)
  → existing file moved to a corrupt slot, canonical file written.
- "Reveal/Open settings file" in the GUI calls `ensureSettingsFileAvailable()` —
  writes the file if missing (`…/UI/SettingsFileWorkflow.swift`).
- External edits that decode successfully do **not** trigger a rewrite
  (`applyExport` runs with `isApplyingExport = true`, which suppresses
  `scheduleSave`). Your formatting survives until the next GUI change.

---

## Table-by-table key reference

All defaults from `SettingsExport.defaults()`
(`…/Core/Config/SettingsExport.swift`) and
`…/Core/Config/BuiltInSettingsDefaults.swift`. "Strict" = missing key rejects
the whole file. All keys below are strict unless marked *(optional)*.

### `[general]`

| key | type | default | notes |
|---|---|---|---|
| `hotkeysEnabled` | bool | `true` | |
| `systemHyperTrigger` | string | `"None"` | `"None"`, key name (CapsLock, F13–F20, Control/RightControl, Option/RightOption, Shift/RightShift, Command/RightCommand), or `"MouseButton3/4/5"`. Invalid string = **dataCorrupted → whole file rejected** (custom decoder in `HotkeyBinding.swift`) |
| `hyperKeyModifiers` | string | `"Ctrl+Alt+Shift+Cmd"` | `+`-joined modifier names, minimum 2 modifiers; invalid = **whole file rejected** |
| `defaultLayoutType` | string | `"niri"` | `default`/`niri`/`dwindle`; invalid string → falls back `.niri` |
| `preventSleepEnabled` | bool | `false` | |
| `updateChecksEnabled` | bool | `true` | |
| `ipcEnabled` | bool | `false` | toggling fires `onIPCEnabledChanged` live |
| `animationsEnabled` | bool | `true` | |

### `[focus]`

| key | type | default |
|---|---|---|
| `followsMouse` | bool | `false` |
| `raiseOnMouseFocus` | bool | `false` |
| `lockModifier` | string | `"off"` (`FocusLockModifier`; invalid → `.off`) |
| `moveMouseToFocusedWindow` | bool | `false` |
| `followsWindowToMonitor` | bool | `false` |
| `crossesMonitorAtEdge` | bool | `false` |
| `moveCrossesMonitorAtEdge` | bool | `false` |

### `[mouseWarp]`

| key | type | default |
|---|---|---|
| `margin` | int | `1` |
| `enabled` | bool | `true` |
| `constrainToArrangement` | bool | `false` (maps to `cursorContainmentEnabled`) |

### `[routing]`

| key | type | default |
|---|---|---|
| `mode` | string | `"macOS"` (`macOS`/`custom`; invalid → `.macOS`) |

### `[gaps]` + `[gaps.outer]`

| key | type | default | notes |
|---|---|---|---|
| `size` | float | `16` | inner gap; clamped 0–64 on resolve |
| `fullscreenUsesOuterGaps` | bool | `false` | |
| `outer.left/right/top/bottom` | float | `0` each | nested table, all four strict |

### `[niri]`

| key | type | default | notes |
|---|---|---|---|
| `visibleContainerCount` | int | `2` | |
| `infiniteLoop` | bool | `false` | |
| `centerFocusedColumn` | string | `"never"` | invalid → `.never` |
| `alwaysCenterSingleColumn` | bool | `false` | |
| `singleWindowFit` | string | `SingleWindowFit.fullScreen` serialized | |
| `containerPrimarySpanPresets` | float array | `[1/3, 0.5, 2/3]` | ***(optional)*** — decodeIfPresent; values clamped 0.05–1.0; fewer than 2 entries → built-in presets |
| `defaultContainerPrimarySpan` | float | `0.5` | ***(optional)***; clamped 0.05–1.0 |

### `[dwindle]`

| key | type | default |
|---|---|---|
| `smartSplit` | bool | `false` |
| `defaultSplitRatio` | float | `1.0` |
| `splitWidthMultiplier` | float | `1.0` |
| `singleWindowFit` | string | fullScreen serialized |
| `useGlobalGaps` | bool | `true` |
| `moveToRootStable` | bool | `true` |

### `[borders]` + `[borders.color]`

| key | type | default | notes |
|---|---|---|---|
| `enabled` | bool | `true` | |
| `width` | float | `5.0` | clamped 1–12 on apply |
| `color.red/green/blue/alpha` | float | ≈(0.085, 1.0, 0.979, 1.0) | all strict; clamped 0–1 |

### `[overview]`

| key | type | default |
|---|---|---|
| `zoom` | float | `1.0` (clamped 0.5–1.5) |
| `backdrop.{red,green,blue,alpha}` | floats | (0.05, 0.05, 0.08, 1.0) |
| `windowBorders.normal.*` | floats | (0.3, 0.3, 0.35, 0.5) |
| `windowBorders.hovered.*` | floats | (0.4, 0.6, 1.0, 1.0) |
| `windowBorders.selected.*` | floats | (0.3, 0.8, 0.4, 1.0) |

All color tables are strict, all four components required.

### `[workspaceBar]` — complete

Types/enums from `…/UI/WorkspaceBar/WorkspaceBarManager.swift`; defaults from
`SettingsExport.defaults()`.

| key | type | default | notes |
|---|---|---|---|
| `enabled` | bool | `true` | |
| `showLabels` | bool | `true` | |
| `showFloatingWindows` | bool | `false` | |
| `windowLevel` | string | `"popup"` | `normal`/`floating`/`status`/`popup`/`screensaver` → NSWindow levels `.normal`/`.floating`/`.statusBar`/`.popUpMenu`/`.screenSaver`; invalid → `.popup` |
| `position` | string | `"overlappingMenuBar"` | or `"belowMenuBar"`; invalid → overlapping |
| `notchMode` | string | `"moveBelowMenuBar"` | `off` / `moveBelowMenuBar` / `splitActiveLeft` / `splitActiveRight`; invalid → moveBelowMenuBar |
| `notchActiveZoneWidth` | float | `180` | clamped 100–400 |
| `systemStatsButton` | bool | `false` | global only — NOT per-monitor overridable |
| `deduplicateAppIcons` | bool | `false` | |
| `hideEmptyWorkspaces` | bool | `false` | |
| `excludedBundleIDs` | string array | `[]` | trimmed, case-insensitively deduped |
| `iconOverrides` | table (string→string) | `{}` | bundleID → icon; keys trimmed/deduped case-insensitively |
| `reserveLayoutSpace` | bool | `false` | see mechanics below |
| `revealModifier` | string | `"off"` | invalid → `.off` |
| `revealHoldMilliseconds` | float | `200` | clamped 0–1000 |
| `height` | float | `24.0` | |
| `backgroundOpacity` | float | `0.1` | |
| `xOffset` | float | `0.0` | added to centered x |
| `yOffset` | float | `0.0` | **Cocoa y-up coordinates** — see below |
| `accentColor` | color table | absent | ***(optional)*** — `{red,green,blue,alpha}`; if the table is present all 4 components are required |
| `textColor` | color table | absent | ***(optional)*** — same |

#### yOffset / xOffset semantics (`…/UI/WorkspaceBar/WorkspaceBarGeometry.swift`)

`frame()` computes `y = originY(monitor)` then `y += yOffset`, in **AppKit
bottom-up screen coordinates**. So:

- **Negative `yOffset` moves the bar DOWN the screen; positive moves it UP.**
  Your measurement (yOffset=-30 → panel moved down from 32 px to 62 px from the
  top) is exactly `y -= 30` in Cocoa coords. This is the inverse of the
  top-down intuition a config author has.
- Baseline `originY`: `belowMenuBar` → `visibleFrame.maxY - barHeight` (bar's
  top edge flush under the menu bar); `overlappingMenuBar` → `visibleFrame.maxY`
  (bar occupies the menu-bar strip). On a notched display with
  `position = overlappingMenuBar` and `notchMode = moveBelowMenuBar`, the
  effective position silently becomes `belowMenuBar` (`effectivePosition(for:)`)
  — that is the y=32 baseline you observed.
- **Why `+30` appeared to stay at 62:** the geometry math alone would place +30
  at ≈2 px from the top, so that observation is not explained by `frame()`
  itself. Two mechanisms in source can pin it: (a)
  `WorkspaceBarPanel.constrainFrameRect` (`…/UI/WorkspaceBar/WorkspaceBarPanel.swift`)
  clamps the panel's origin into `screenFrame` whenever AppKit re-constrains
  (`origin.y = max(minY, min(y, maxY - height))`), preventing the bar from
  leaving the screen top — but that clamps to the top edge, not to 62; (b) far
  more likely given the identical 62 px readings: **the `+30` edit was never
  applied** — either the file was invalid at that moment (silent live-reload
  rejection, see decode semantics) or a subsequent restart had already reset
  `yOffset` to 0 and moved your file aside. From source alone this is the
  honest limit: the math cannot produce "62 for both -30 and +30"; a rejected
  reload can. Check the log for
  `Ignoring invalid external settings edit` and for `settings.toml.corrupt`.
- In split-notch mode (`splitFrame`) both islands get `offsetBy(dx: xOffset,
  dy: yOffset)` — same sign convention.

#### reserveLayoutSpace mechanics (`…/Core/Controller/WMController.swift` ≈ lines 1050–1096, `WorkspaceBarGeometry.resolve`)

`reservedTopInset = barHeight` only when **all** of these hold, evaluated in
`workspaceBarReservedTopInset(for:)` each layout pass:

1. `workspaceBarRevealModifier == .off` — **any reveal modifier zeroes the
   reservation unconditionally** (first guard in the function).
2. `resolved.reserveLayoutSpace == true` (global or per-monitor override).
3. The bar is visible on that monitor: `resolved.enabled`, the monitor is not in
   `hiddenWorkspaceBarMonitorIds` (the `toggleWorkspaceBarVisibility` hotkey
   hides per-monitor), and reveal is off or currently held
   (`isWorkspaceBarVisible(on:)`).

The inset feeds `layoutFrames(for:scale:)` as a top strut merged with the outer
top gap and the menu-bar inset (`normalizedTopStrut`), so it applies to **both
dwindle and niri** working frames, and to the fullscreen layout frame.

**Why it reserved live but not after restart:** there is no startup-only gate in
this code path. Given condition set above, the source-consistent explanation is
the same decode story: the restart reloaded a settings.toml that failed strict
decode (or had been replaced with defaults), so `reserveLayoutSpace` was back to
its default `false`. Secondary trap worth knowing: if you set
`revealModifier` to anything but `"off"` (even with the bar permanently shown),
reservation is disabled by guard #1 — a live GUI toggle of reserveLayoutSpace
while reveal is off would work, then a restart that restores a config with a
reveal modifier kills it. If neither applies, nothing else in
`workspaceBarReservedTopInset` distinguishes cold start from steady state —
genuinely no further gate found in source.

### `[gestures]`

| key | type | default | notes |
|---|---|---|---|
| `scrollEnabled` | bool | `true` | |
| `scrollSensitivity` | float | `5.0` | clamped 0.1–100 |
| `scrollModifierKey` | string | `"optionShift"`-style raw (`ScrollModifierKey`; invalid → `.optionShift`) | |
| `mouseMoveModifierKey` | string | option raw (invalid → `.option`) | |
| `mouseResizeModifierKey` | string | option raw (invalid → `.option`) | |
| `fingerCount` | int | `3` | invalid → 3 |
| `invertDirection` | bool | `true` | |
| `trackpadScrollStyle` | string | `"snap"` raw (invalid → `.snap`) | |
| `workspaceSwipeEnabled` | bool | `false` | |
| `workspaceSwipeFingerCount` | int | `3` | if it equals `fingerCount` while scroll gestures are on, swipe axis is forced vertical at runtime |
| `workspaceSwipeAxis` | string | `"vertical"` (invalid → vertical) | |

### `[statusBar]`

| key | type | default |
|---|---|---|
| `showWorkspaceName` | bool | `false` |
| `showAppNames` | bool | `false` |
| `useWorkspaceId` | bool | `false` |

### `[hiddenBar]`

| key | type | default | notes |
|---|---|---|---|
| `enabled` | bool | `true` | |
| `hiddenBundleIDs` | string array | `[]` | `com.apple.MenuBarAgent`, `com.apple.controlcenter`, `com.apple.systemuiserver` are silently stripped (`HiddenBarSettingsPolicy`) |
| `rehideIntervalSeconds` | float | `5` | clamped 2–30 |

### `[clipboard]`

| key | type | default |
|---|---|---|
| `historyEnabled` | bool | `false` |
| `maxItems` | int | `200` |
| `maxItemBytes` | int | `8388608` |
| `maxTotalBytes` | int | `67108864` |

### `[quakeTerminal]`

| key | type | default | notes |
|---|---|---|---|
| `enabled` | bool | `true` | |
| `position` | string | `"center"` (invalid → center) | |
| `widthPercent` / `heightPercent` | float | `50.0` | normalized by `QuakeTerminalGeometryPolicy` |
| `animationDuration` | float | `0.2` | |
| `autoHide` | bool | `false` | |
| `opacity` | float | `1.0` | ***(optional)*** |
| `backgroundEffect` | string | `"standardBlur"` raw (invalid → standardBlur) | |
| `backgroundBlurRadius` | int | disabled sentinel | ***(optional)*** |
| `monitorMode` | string | `"focusedWindow"` raw | ***(optional)***; invalid → focusedWindow |

### `[appearance]`

| key | type | default |
|---|---|---|
| `mode` | string | `"dark"` raw (`AppearanceMode`; invalid → `.dark`) |

---

## `[[hotkeys]]` array

Format (`…/Core/Input/HotkeyBinding.swift`): array of tables, each

```toml
[[hotkeys]]
id = "focus.left"
binding = "Alt+H"        # human-readable chord, or "Unassigned"
```

- `id` — required string, must be a **known assignable action id** from
  `ActionCatalog` (`…/Core/Input/ActionCatalog.swift`). Unknown id →
  `unknownActionID` decode error → **whole file rejected**. Ids marked
  unassignable in the catalog → `unassignableActionID` → rejected.
- `binding` — optional per entry (`decodeIfPresent … ?? .unassigned`). Accepts
  a human-readable string (parsed by `KeySymbolMapper.fromHumanReadable`,
  modifiers joined with `+`; "Hyper" chords re-target when `hyperKeyModifiers`
  changes) or a structured table `{ keyCode, modifiers, left?, right? }`
  (Carbon key code + modifier mask, optional left/right-sided masks). An
  unparseable string falls through to the structured decoder and, failing that,
  rejects the file.
- **Completeness is mandatory:** `HotkeyBindingRegistry.resolve` requires every
  default action id to appear **exactly once** — a missing id throws
  `missingActionID`, a duplicate throws `duplicateActionID`, and either
  **rejects the entire file** (confirmed by
  `testTOMLRejectsFileMissingAKnownHotkeyAction`, `testTOMLRejectsDuplicateHotkeyAction`).
  You cannot write a hotkeys array containing only your customizations.
- Id families (from `ActionCatalog.buildSpecs()`): `switchWorkspace.0–8` /
  `.next` / `.previous`, `moveToWorkspace.0–8`, `workspaceBackAndForth`,
  `focus.left/down/up/right`, `focusPrevious`, `focusDownOrLeft`,
  `focusUpOrRight`, `focusWindow*`, `centerColumn`, `centerVisibleColumns`,
  `move.left/down/up/right`, `moveWindow*`, `moveColumn*`,
  `consumeOrExpelWindowLeft/Right`, `consumeWindowIntoColumn`,
  `expelWindowFromColumn`, `focusMonitorNext/Previous/Last`,
  `moveWorkspaceToMonitor.left/right/up/down`, `moveWindowToMonitor.*`,
  `toggleFullscreen`, `toggleNativeFullscreen`, `toggleColumnTabbed`,
  `focusColumnFirst/Last`, `focusColumn.N`, `focusWindowInColumn.N`,
  `moveColumnToIndex.N`, `cycleSize*`, `cycleWindow*Span*`,
  `toggleContainerFullPrimarySpan`, `expandContainerToAvailablePrimarySpan`,
  `resetWindowSecondarySpan`, `setContainerPrimarySpan.±10Percent`,
  `setWindowPrimarySpan.±10Percent`, `setWindowSecondarySpan.±10Percent`,
  `balanceSizes`, `moveToRoot`, `toggleSplit`, `swapSplit`,
  `resizeGrow/Shrink.horizontal/vertical`, `resizeFocusedWindow.grow/shrink`,
  `preselect.left/right/up/down`, `preselectClear`, `openCommandPalette`,
  `raiseAllFloatingWindows`, `rescueOffscreenWindows`,
  `toggleFocusedWindowFloating`, `assignFocusedWindowToScratchpad`,
  `toggleScratchpadWindow`, `openMenuAnywhere`, `toggleWorkspaceBarVisibility`,
  `toggleHiddenBarPanel`, `toggleQuakeTerminal`, `toggleWorkspaceLayout`,
  `toggleOverview`, `toggleSystemStats`. The authoritative complete list is the
  generated settings.toml itself.

## `[[workspaces]]` array (`…/Core/Config/WorkspaceConfig.swift`)

```toml
[[workspaces]]
id = "AD36F001-C57E-41A5-AC1D-DF5249D007F0"   # required UUID — strict decode
name = "1"                                     # required
displayName = "❤️"                             # optional
layoutType = "niri"                            # "default" | "niri" | "dwindle"
[workspaces.monitorAssignment]
type = "main"                                  # "main" | "secondary" | "specificDisplay"
# output = { … }                               # OutputId, required iff type = specificDisplay
```

- `id` **is required** (synthesized `let id: UUID` decodes strictly; unlike
  `AppRule` there is no fallback UUID generation). Invalid/missing UUID rejects
  the file.
- `layoutType` and `monitorAssignment.type` are strict enums — an invalid string
  here rejects the file (real `Codable` enums, not rawValue-with-fallback).
- Post-decode normalization (`SettingsStore.normalizedWorkspaceConfigurations`):
  entries whose `name` fails `WorkspaceIDPolicy.normalizeRawID` are dropped,
  duplicate names dropped (first wins), sorted by workspace-number policy; an
  empty result is replaced by the 7 built-in workspaces (names "1"–"7", 6–7
  assigned `.secondary` with ❤️/🚀 display names —
  `BuiltInSettingsDefaults.workspaceConfigurations`).

## `[[appRules]]` array (`…/Core/Config/AppRule.swift`)

Custom decoder — the most lenient structure in the file:

| field | type | required? |
|---|---|---|
| `id` | UUID string | optional — **auto-generated if missing** (only place in the schema that does this) |
| `bundleId` | string | **required** (may be empty string) |
| `appNameSubstring`, `titleSubstring`, `titleRegex`, `axRole`, `axSubrole` | string | optional matchers |
| `layout` | string `auto`/`tile`/`float` | optional (absent = auto) |
| `assignToWorkspace` | string | optional |
| `initialContainerPrimarySpan` | float | optional; only honored if finite and in 0.05–1.0 |
| `minWidth`, `minHeight` | float | optional |

If both `titleRegex` and `titleSubstring` are non-empty, `titleSubstring` is
silently dropped (`normalizeSingleTitle`). Matching specificity: bundleId
scores 2, each other matcher 1. 13 built-in rules (Chrome, Safari, Firefox,
Zed, Ghostty, Spotify, Discord, Outlook, Messages, …) are the default set —
they live in the settings file once generated, so deleting them there removes
them.

## Monitor override arrays (`…/Core/Config/Monitor*Settings.swift`)

All six arrays share the monitor-identity header and matching logic
(`MonitorSettingsType` / `MonitorSettingsStore`, `…/Core/Config/MonitorSettingsType.swift`):

- Identity fields: `monitorName` (required string), `monitorDisplayUUID`
  (optional, canonicalized), `monitorDisplayId` (optional int). Matching prefers
  UUID; fallback is displayId + fuzzy name match. Ambiguous (multiple matches) →
  no override applied (`uniqueMatch` returns nil).
- Every override *value* field is optional (`decodeIfPresent`) and, when nil,
  falls through to the global value (`SettingsStore.resolved*Settings`).

| array | id field | override fields (all optional) |
|---|---|---|
| `[[monitorGapOverrides]]` | `id` UUID **required** | `innerGap`, `outerGapLeft/Right/Top/Bottom`, `fullscreenUsesOuterGaps`. Entries with no overrides set are filtered out on load AND on save (`filter(\.hasOverrides)`) — an identity-only entry silently vanishes |
| `[[monitorNiriOverrides]]` | `id` UUID **required** | `visibleContainerCount`, `centerFocusedColumn` (invalid string → treated as absent), `alwaysCenterSingleColumn`, `singleWindowFit`, `infiniteLoop` |
| `[[monitorDwindleOverrides]]` | `id` UUID **required** | `smartSplit`, `defaultSplitRatio`, `splitWidthMultiplier`, `singleWindowFit`, `useGlobalGaps`, `innerGap` (used only when `useGlobalGaps = false`) |
| `[[monitorBarOverrides]]` | `id` UUID **required** | `enabled`, `showLabels`, `showFloatingWindows`, `deduplicateAppIcons`, `hideEmptyWorkspaces`, `reserveLayoutSpace`, `notchMode`, `notchActiveZoneWidth`, `position`, `windowLevel`, `height`, `backgroundOpacity`, `xOffset`, `yOffset`. NOT overridable per-monitor: excludedBundleIDs, iconOverrides, systemStatsButton, reveal settings, accent/text color |
| `[[monitorOrientationOverrides]]` | no UUID (id derived from displayUUID/displayId/name) | `orientation` (strict enum if present) |
| `[[monitorRoutingOverrides]]` | no UUID (derived id) | `gridColumn`, `gridRow` — both **required** ints (only override array with required value fields). Used when `routing.mode = "custom"` |

Note the enum-valued override fields decode as
`decodeIfPresent(String) .flatMap(Enum.init)` — an invalid enum string in an
override is silently treated as "no override" rather than rejecting the file
(different from top-level strict tables, and from `orientation` which rejects).

---

## GUI round-trip

- The Settings GUI binds directly to `SettingsStore` properties; **every**
  property mutation triggers `scheduleSave()` → next-runloop-tick write of the
  **whole** canonical file (all tables, all keys, sorted, pretty-printed),
  preserving unknown keys/tables but not comments or ordering
  (`SettingsStore.swift`, `SettingsFilePersistence.scheduleSave`).
- `flushNow()` forces pending writes (called around app lifecycle);
  `RuntimeStateStore` flushes separately to runtime-state.json.
- Ways a GUI toggle can silently fail to persist (all log-only, no UI error):
  1. `save()` catches and logs any write error (`Failed to save …`).
  2. If the on-disk file is unparseable at save time and **both** corrupt slots
     (`settings.toml.corrupt`, `.corrupt.1`) are already occupied,
     `secureCorruptData` throws `corruptBackupSlotsExhausted` and the save is
     dropped — the in-memory toggle works until restart, then reverts. Delete
     the corrupt files to un-wedge this.
  3. The fingerprint short-circuit in `saveImmediately` skips writing when it
     believes disk and memory match; fingerprint is dev+inode+mtime(ns)+ctime(ns)+size,
     so this is robust against editors, but a filesystem with coarse timestamps
     could in principle suppress a needed write.
- External-edit detection: kqueue watchers on both the settings file and its
  directory; the app's own writes are recognized via `lastWrittenFingerprint`
  and do not trigger a self-reload.

---

## Traps (summary for config authors)

1. **No sparse files, ever.** Missing table, missing key inside a table, missing
   or duplicate hotkey id, unknown hotkey id, missing `id` UUID on
   workspaces/gap/niri/dwindle/bar overrides, bad `systemHyperTrigger` /
   `hyperKeyModifiers` string — each rejects the *entire* file.
2. **Cold start destroys invalid files.** Your handwritten file is moved to
   `settings.toml.corrupt` (max 2 backups, then saves fail) and replaced with
   defaults — silently, log-only. Live reload of the same invalid file instead
   keeps current in-memory settings, which makes invalid files *look* accepted
   while the app runs. This asymmetry is the whole cold-start mystery.
3. **`yOffset`/`xOffset` are Cocoa coordinates**: positive y = up, negative y =
   down. The GUI slider and TOML share this convention.
4. **`reserveLayoutSpace` is dead while `revealModifier != "off"`** — hard guard
   in `workspaceBarReservedTopInset`, regardless of whether the bar is shown.
5. **Invalid enum strings degrade differently by location**: top-level table
   enums with `rawValue` fallback → silently default (e.g. bad `windowLevel` →
   popup); custom-Codable enums (`systemHyperTrigger`, workspace `layoutType`,
   `monitorAssignment.type`, `orientation`) → whole-file rejection; enum strings
   inside monitor bar/niri/dwindle overrides → silently no-override.
6. **Rewrites lose comments and ordering** but keep unknown keys/tables — you
   can stash `[omacchiato]` metadata in the file and it survives; comments don't.
7. **Gap overrides with no set fields are garbage-collected** on load and save.
8. **Hidden-bar can never hide** Control Center / MenuBarAgent / SystemUIServer;
   those ids are stripped on apply (and re-saved stripped).
9. **Hotkeys array must be the complete catalog.** Generate the file first, then
   edit bindings in place. `binding = "Unassigned"` is the way to disable one.
10. **Per-monitor bar overrides can't change** excluded apps, icon overrides,
    stats button, reveal behavior, or colors — global only.
11. Unknown keys are not errors but do show up as Diagnostics warnings
    (`unknownConfigKeys`), as does the presence of a `.corrupt` file.
12. Numeric widths in `AppRule` (`minWidth`/`minHeight`) and most floats are
    TOML floats in the canonical file; whether bare integers coerce to Double on
    decode depends on mattt/swift-toml's `TOMLDecoder` — not verified from this
    repo's source; write `24.0` not `24` to be safe.
