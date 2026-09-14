# OmniWM IPC/CLI capability audit

Audit of the complete OmniWM automation surface, from source at `BarutSRB/OmniWM`
HEAD (2026-08-26) plus live verification against the running OmniWM 0.6.2 on this
machine (`/opt/homebrew/bin/omniwmctl`, IPC enabled, protocol version 11 on both
sides). Where `docs/IPC-CLI.md` and the code disagree, code wins; discrepancies
are flagged.

Source files referenced:

- Shared protocol: `Sources/OmniWMIPC/IPCModels.swift`, `IPCWire.swift`,
  `IPCSocketPath.swift`, `IPCAutomationManifest.swift`, `WorkspaceAddressing.swift`,
  `IPCRuleValidator.swift`
- Server: `Sources/OmniWM/IPC/IPCServer.swift`, `IPCConnection.swift`,
  `IPCApplicationBridge.swift`, `IPCCommandRouter.swift`, `IPCQueryRouter.swift`,
  `IPCRuleRouter.swift`, `IPCEventBroker.swift`, `ExternalCommandResult.swift`
- CLI: `Sources/OmniWMCtl/CLIParser.swift`, `CLIRuntime.swift`, `IPCClient.swift`
- Event triggers: `Sources/OmniWM/Core/Controller/WMController.swift`,
  `Sources/OmniWM/Core/Surface/SurfaceReconciler.swift`

---

## 1. Commands

Request kinds are a closed enum: `ping`, `version`, `command`, `query`, `rule`,
`workspace`, `window`, `subscribe` (`IPCModels.swift:21`, `IPCRequestKind`).
**There is no exec, no config-get/set, no arbitrary-payload kind.** The full
command registry is data-driven from `IPCAutomationManifest.commandDescriptors`
(`IPCAutomationManifest.swift:442-893`); the CLI parses against it and the server
routes each name 1:1 into `WMController.commandHandler.performCommand(...)`
(`IPCCommandRouter.swift:17-218`). Everything below verified present in both the
HEAD manifest and the installed 0.6.2 `--help`.

### `omniwmctl command ...` (act on focused window/workspace/monitor)

Layout tags: shared = any layout, niri/dwindle = only that layout, else
`layout_mismatch`.

**Focus** — `focus <left|right|up|down>` (shared), `focus previous`,
`focus down-or-left`, `focus up-or-right` (niri), `focus-window-in-column <n>`,
`focus-window top|bottom` (niri), `focus-window down-or-top|up-or-bottom`
(shared), `focus-window-or-workspace-down|-up` (niri),
`focus-column <n>|first|last` (niri).

**Move** — `move <dir>` (shared, layout-aware consume/expel or Dwindle
join/extract), `move-window-down|-up` (shared),
`move-window-down-or-to-workspace-down` / `-up-or-to-workspace-up` (niri),
`consume-or-expel-window-left|-right`, `consume-window-into-column`,
`expel-window-from-column` (niri).

**Workspace switching** — `switch-workspace <n>|next|prev|back-and-forth` and
`switch-workspace anywhere <n>` (cross-monitor). Workspace IDs are positive
numeric strings (`WorkspaceAddressing.swift`, `WorkspaceIDPolicy`); IPC supports
10+ even though hotkeys stop at 9. The router compares active-workspace id
before/after and returns `not_found` if nothing changed
(`IPCCommandRouter.swift:454-492`) — i.e. switching to the already-active
workspace reports `not_found`, not success.

**Move to workspace** — `move-to-workspace <n>|up|down`,
`move-to-workspace on-monitor <n> <dir>`.

**Monitors** — `focus-monitor prev|next|last`, `move-to-monitor <dir>`,
`swap-workspace-with-monitor <dir>`. Same no-op⇒`not_found` semantics
(`IPCCommandRouter.swift:372-390`).

**Niri columns/spans** — `center-column`, `center-visible-columns`,
`move-column <dir>`, `move-column-to-first|-last`, `move-column-to-index <n>`,
`move-column-to-workspace <n>|up|down`, `toggle-column-tabbed`,
`cycle-window-primary-span forward|backward`, `cycle-window-secondary-span ...`,
`toggle-container-full-primary-span`,
`expand-container-to-available-primary-span`, `reset-window-secondary-span`,
`set-container-primary-span <size-change>`, `set-window-primary-span ...`,
`set-window-secondary-span ...`. `<size-change>` grammar: `100`, `50%`, `+10`,
`-10%` (`IPCSizeChange`, `IPCModels.swift:293-326`).

**Dwindle** — `move-to-root`, `toggle-split`, `swap-split`,
`resize <horizontal|vertical> <grow|shrink>`, `resize-focused <grow|shrink>`,
`preselect <dir>`, `preselect clear`.

**Layout/sizing (shared)** — `balance-sizes`, `cycle-size forward|backward`,
`toggle-workspace-layout`, `set-workspace-layout <default|niri|dwindle>`,
`toggle-fullscreen` (WM-managed), `toggle-native-fullscreen`.

**Window management** — `toggle-focused-window-floating`,
`raise-all-floating-windows`, `rescue-offscreen-windows`, `scratchpad assign`,
`scratchpad toggle`.

**UI toggles** — the answers to "can IPC trigger X":

| Surface | Command | Yes/no |
|---|---|---|
| Overview | `command toggle-overview` | **Yes — open only.** While Overview is open, *every* IPC command (incl. another `toggle-overview`) is rejected with `ignored_overview` (`IPCCommandRouter.swift:322-326` `validateControllerState`, plus the same guard inside `CommandHandler`). IPC cannot close Overview or drive its selection. |
| Quake terminal | `command toggle-quake-terminal` | **Yes** (toggle only, no show/hide split, no way to choose which terminal). |
| Command palette | `command open-command-palette` | **Yes** (toggle). |
| Menu anywhere | `command open-menu-anywhere` | Yes. |
| Workspace bar | `command toggle-workspace-bar` | Yes (runtime visibility toggle). |
| Hidden-bar panel | `command hidden-bar panel` | Yes. |
| System stats popup | `command toggle-system-stats` | Yes, only when a workspace-bar System Stats button exists. |

**Exec:** the server exposes **no exec of any kind**. The only process spawning
in the whole surface is client-side: `omniwmctl watch --exec` forks the child in
the CLI process (`CLIRuntime.swift:280-370`), never in OmniWM.

**Config at runtime:** there is **no config query and no config-set command**.
The only persisted-settings mutation reachable over IPC is the window-rule store
(`rule add/replace/remove/move` writes `controller.settings.appRules`,
`IPCRuleRouter.swift:32-80`). Config-adjacent state is readable only as
projections: bar settings (enabled/opacity/height/labels) via `query
workspace-bar`, gaps and fullscreen-gap policy via `query displays`. Nothing
else in `Settings` is reachable; config reload cannot be triggered over IPC.

### `omniwmctl workspace ...` (act on a named workspace)

- `workspace focus-name <name>` — raw numeric ID first, else unambiguous
  configured display name (`ambiguous ⇒ invalid_arguments`,
  `IPCCommandRouter.swift:536-551`).
- `workspace move-to-monitor <workspace> <left|right|up|down> [--force]` —
  direction relative to the workspace's current monitor; `--force` temporarily
  overrides configured monitor assignment (runtime-only, cleared on restart /
  config reapply / return home). Failure codes:
  `workspace_assignment_conflict`, `workspace_state_conflict`, `not_found`.

### `omniwmctl window ...` (act on a specific window)

`window focus <opaque-id>`, `window navigate <opaque-id>` (switches workspace if
needed), `window summon-right <opaque-id>` (pulls the window next to the focused
one). Opaque IDs are `ow_` + base64url(`sessionToken:pid:windowId`)
(`IPCModels.swift`, `IPCWindowOpaqueID`); they die with the OmniWM process
(`stale_window_id`). **There is no IPC way to set a window's frame/position, no
close/minimize, no move-specific-window-to-workspace (only the focused window
can be moved), no resize of an arbitrary window.**

### `omniwmctl rule ...` (persisted window rules)

`rule add|replace <id>|remove <id>|move <id> <pos>|apply
[--focused|--window <id>|--pid <pid>]`. Matchers: `--bundle-id`,
`--app-name-substring`, `--title-substring`, `--title-regex`, `--ax-role`,
`--ax-subrole`; effects: `--layout auto|tile|float`,
`--assign-to-workspace <name>`, `--initial-container-primary-span 0.05..1.0`,
`--min-width`, `--min-height` (`IPCAutomationManifest.swift:932-1040`,
validation in `IPCRuleValidator.swift`). Every rule mutation returns the full
updated rule list. `rule apply` is the only path that moves already-managed
windows.

---

## 2. Queries

`omniwmctl query <name> [selectors] [--fields csv]`, default output JSON. Full
registry (`IPCQueryName`, `IPCModels.swift:1316`): `workspace-bar`,
`active-workspace`, `focused-monitor`, `apps`, `focused-window`, `windows`,
`workspaces`, `displays`, `rules`, `rule-actions`, `queries`, `commands`,
`subscriptions`, `capabilities`. There are no queries beyond these fourteen.
Selectors/fields validated server-side against the manifest
(`IPCApplicationBridge.swift:287-324`); unknown selector/field ⇒
`invalid_arguments`; boolean selectors must be `true`.

All payload field names below are from `IPCModels.swift` structs; keys are
camelCase on the wire even where the `--fields` token is kebab-case (e.g.
`window-counts` token selects the `counts` JSON key, `is-app-hidden` ⇒
`isAppHidden`).

Common refs: `IPCWorkspaceRef {id (UUID string), rawName, displayName, number?}`,
`IPCDisplayRef {id ("display:N"), name, isMain}`, `IPCAppRef {name, bundleId?}`,
`IPCRect {x,y,width,height}` (raw CGRect values, global screen points,
`IPCQueryRouter.swift:602`).

### windows (selectors: --window --workspace --display --focused --visible --floating --scratchpad --app --bundle-id)

`{windows: [IPCWindowQuerySnapshot]}` — per window: `id` (opaque), `pid`,
`workspace` (ref), `display` (ref), `app` (ref), `title`, `frame` (rect),
`mode` (`tiling|floating`), `layoutReason` (`standard|native-fullscreen`),
`manualOverride?` (`force-tile|force-float`), `isFocused`, `isVisible`,
`isAppHidden`, `isScratchpad`, `hiddenReason?`
(`workspace-inactive|layout-transient|scratchpad`). `isVisible` = workspace
visible ∧ no hiddenReason ∧ app not macOS-hidden. **Live-verified 0.6.2:**
`query windows --focused` returned exactly this shape (absent optionals omitted).

### workspaces (selectors: --workspace --display --current --visible --focused)

`{workspaces: [...]}` — `id`, `rawName`, `displayName`, `number?`, `layout`
(`default|niri|dwindle`), `display` (ref), `isFocused`, `isVisible`,
`isCurrent`, `counts {total,tiled,floating,scratchpad}`, `focusedWindowId?`.
**Live-verified** (`query workspaces --current`), including `counts` and
`focusedWindowId`.

### displays (selectors: --display --main --current)

`{displays: [...]}` — `id`, `name`, `isMain`, `isCurrent`, `frame`,
`visibleFrame`, `hasNotch`, `orientation` (`horizontal|vertical`), `innerGap`,
`outerGapLeft/Right/Top/Bottom`, `fullscreenUsesOuterGaps`, `activeWorkspace`
(ref). **Live-verified** except `fullscreenUsesOuterGaps`, which the installed
0.6.2 does not emit and does not list in its field catalog — it is a HEAD
addition made **without a protocol bump** (both sides say 11); consumers must
treat it as optional.

### workspace-bar (no selectors/fields)

The richest projection — this is the status-bar feed.
`{interactionMonitorId?, monitors: [...]}`; per monitor: `id`, `name`,
`enabled`, `isVisible`, `showLabels`, `backgroundOpacity`, `barHeight`,
`scratchpad? {window, isVisible}`, `workspaces: [{id, rawName, displayName,
number?, isFocused, windows: [{id, appName, isFocused, windowCount,
allWindows: [{id, title, isFocused}]}]}]` (`IPCModels.swift:2052-2163`).
Windows are grouped per app; each group carries the leading window's opaque id.
**Live-verified**: full multi-monitor/multi-workspace tree with per-window
opaque ids and titles even for the bar-disabled monitor (`enabled: false` still
lists everything).

### active-workspace / focused-monitor

`active-workspace`: `{display?, workspace?, focusedApp?}` — focusedApp only when
the focused window is on the active workspace. `focused-monitor`: `{display?,
activeWorkspace?}`. **Live-verified** both.

### focused-window

`{window?: {id, pid?, workspace?, display?, app?, title?, frame?}}` — a slimmer
snapshot than `windows` (no mode/visibility flags).

### apps

`{apps: [{bundleId, appName, windowSize {width,height}}]}` — managed-app summary
(`windowSize` is the size used by OmniWM surfaces, not a count).

### Introspection: rules / rule-actions / queries / commands / subscriptions / capabilities

`rules`: `{rules: [{id, position, bundleId, appNameSubstring?, titleSubstring?,
titleRegex?, axRole?, axSubrole?, layout, assignToWorkspace?,
initialContainerPrimarySpan?, minWidth?, minHeight?, specificity, isValid,
invalidRegexMessage?, validationMessages}]}`. `commands` returns the full
descriptor registry for the `command`/`workspace`/`window` surfaces (paths,
argument kinds, layout compatibility). `capabilities` returns everything at
once: `{protocolVersion, appVersion?, authorizationRequired, windowIdScope,
queries, commands, ruleActions, workspaceActions, windowActions, subscriptions}`
(`IPCModels.swift:2544`). A client can therefore discover the entire surface at
runtime instead of hardcoding it.

---

## 3. Events (subscribe / watch)

### Channels — the complete set

Exactly seven (`IPCSubscriptionChannel`, `IPCModels.swift:88`); each event's
`result` is a **full snapshot of the same payload as the corresponding query**,
not a delta:

| Channel | result.kind | Snapshot | Trigger (code) |
|---|---|---|---|
| `focus` | `focused-window` | focused-window query | `handleSessionStateChanged` when `changeSet.focusChanged` (`WMController.swift:1232-1252`) |
| `active-workspace` | `active-workspace` | active-workspace query | same handler, `workspaceChanged || monitorChanged` |
| `focused-monitor` | `focused-monitor` | focused-monitor query | same handler, `monitorChanged` |
| `display-changed` | `displays` | displays query | `monitorChanged`, plus gap-setting changes (`setGapSize`/`setOuterGaps`/`updateMonitorGapSettings`, `WMController.swift:555-571,846-857`) |
| `workspace-bar` | `workspace-bar` | workspace-bar query | `publishWorkspaceDataChanged`, fired by `SurfaceReconciler.applyFull` when the desired bar scene differs from the applied one (`SurfaceReconciler.swift:508-516`) |
| `windows-changed` | `windows` | windows query (unfiltered) | same `publishWorkspaceDataChanged` |
| `layout-changed` | `workspaces` | workspaces query | same `publishWorkspaceDataChanged` |

Note `workspace-bar`/`windows-changed`/`layout-changed` are one trigger fanned
into three payload shapes — they always fire together and share granularity.

### Events that do NOT exist

No `window-created` / `window-destroyed` / `window-title-changed` (only the
coalesced `windows-changed` inventory snapshot — you must diff snapshots
yourself, and title-only changes fire it only if they alter the bar projection).
No `config-reloaded`, no `rules-changed`, no `overview-opened/closed`, no
`fullscreen-changed`, no per-window `moved/resized` events, no
`monitor-connected/disconnected` distinct from `display-changed`, no
mode/scratchpad events. `layout-changed` means "workspace data changed", not
specifically "the layout algorithm switched".

### Delivery mechanics & reliability

- Subscribe upgrades the same NDJSON connection: one `IPCResponse`
  (`status: "subscribed"`, payload = accepted channel list), then per-channel
  initial snapshots (unless `--no-send-initial`), then live `IPCEventEnvelope`
  lines (`IPCConnection.swift:76-119`). **Live-verified**: handshake + initial
  `focus` snapshot exactly as modeled.
- **Coalescing, not a log**: each subscriber stream is an `AsyncStream` with
  `bufferingPolicy: .bufferingNewest(1)` (`IPCEventBroker.swift:59`). A slow
  consumer sees only the newest pending snapshot per channel; intermediate
  states are silently dropped. Snapshot payloads make this safe (last write
  wins) but event *counting* is meaningless.
- Initial snapshot is best-effort seed state and can race a live update — no
  ordering barrier (also stated in docs).
- **Demand gating**: workspace-bar/windows/layout refresh work is only produced
  while something consumes it (`hasWorkspaceBarDataConsumers`,
  `WMController.swift:1136-1142` — UI bar, status bar, or an IPC subscriber).
  First subscriber may therefore need one real state change before events flow.
- Events are point-in-time reads of live controller state at publish time
  (`IPCApplicationBridge.eventEnvelope`, bridge lines 353-405).
- Duplicate channels in one subscribe are deduped; a second subscribe on the
  same connection adds only channels not already streaming
  (`IPCConnection.swift:88-95`).
- `watch <channels> --exec argv...`: CLI-side loop, strictly sequential — one
  child per event, waits for exit before the next (further events meanwhile
  coalesce to newest); event JSON on child stdin (one NDJSON line); env
  `OMNIWM_EVENT_CHANNEL`, `OMNIWM_EVENT_KIND`, `OMNIWM_EVENT_ID`
  (`CLIRuntime.swift:327-331`); non-zero exits reported to stderr without
  killing the watcher; bare command names resolved via `PATH`.

---

## 4. Envelope, security, versioning

### Wire format

NDJSON over a Unix stream socket; one JSON object per `0x0A`-terminated line;
sorted camelCase keys; max request line **64 KB**
(`IPCConnection.maxRequestLineBytes`; oversize ⇒ `kind:"error"`,
`code:"invalid_request"`, empty id). Responses/events have no size cap.

Request: `{version, id, kind, authorizationToken, payload?}` — payload key
varies by kind (`command`/`query`/`rule` are `{name, ...}` objects; `workspace`
uses the flat `{name, workspaceTarget {kind: raw-id|display-name, value},
direction?, force?}` shape from `WorkspaceAddressing.swift`; `window` is
`{name, windowId}`; `subscribe` is `{channels, allChannels, sendInitial}`).

Response: `{version, id, kind, ok, status, code?, result?}` with
`status ∈ success|executed|ignored|error|subscribed` and result
`{kind, payload}`. Event envelope: `{version, id, kind:"event", channel, ok,
status, code?, result}`. Error codes (complete, `IPCErrorCode`):
`invalid_request`, `invalid_arguments`, `protocol_mismatch`, `ignored_disabled`,
`ignored_overview`, `layout_mismatch`, `unauthorized`, `stale_window_id`,
`not_found`, `workspace_assignment_conflict`, `workspace_state_conflict`,
`internal_error`. CLI exit codes: 0 ok, 1 rejected, 2 transport, 3 args,
4 internal; CLI-local failures emit a distinct `{ok, source:"cli", status,
code, message, exitCode}` envelope (no version/id).

### Security model (all verified in `IPCServer.swift`)

- Socket `~/Library/Caches/com.barut.OmniWM/ipc.sock` (override:
  `OMNIWM_SOCKET`; secret always `<socket>.secret`). IPC is **off by default**;
  menu toggle creates/removes socket + secret.
- Socket chmod `0600` after bind (line 279); new socket dirs `0700`; secret
  written `0600` then re-chmodded (lines 198-204).
- `getpeereid()` euid check on accept — mismatched-uid connections are dropped
  before a single byte is processed (lines 148-161, 348-355).
- Authorization token: random UUID per server start, plaintext in the secret
  file, required on every request; checked before version check
  (`IPCApplicationBridge.swift:29-53`).
- `FD_CLOEXEC` + `SO_NOSIGPIPE` on all fds; stale-socket detection via probe
  connect (`isActiveSocket`); refuses to unlink a non-socket at the path.
- Trust boundary = the macOS user account. Any same-user process can read the
  secret and drive the full surface. Window opaque ids additionally embed a
  separate per-process session token, so ids can't be replayed across restarts.

### Versioning

`OmniWMIPCProtocol.version = 11` at HEAD; installed 0.6.2 also speaks 11
(live-verified via `version`). Strict equality: any other version ⇒
`protocol_mismatch` (except `version` requests, which succeed and return
`{protocolVersion, appVersion}` so clients can negotiate). Note the
`fullscreenUsesOuterGaps` case above: additive payload fields do land within a
protocol version, so clients should ignore unknown keys and treat new ones as
optional.

### Docs-vs-code discrepancies found

1. **`docs/IPC-CLI.md` "Aliases" section is not implemented.** The docs claim
   `query monitors`, `query --monitor`, `command focus-monitor previous`,
   `command switch-workspace previous`, `command switch-workspace back` all
   resolve transparently. No alias code exists anywhere in `Sources/OmniWMCtl/`
   or the manifest (parser matches manifest words exactly,
   `CLIParser.swift:210-233`; normalize() only strips `--format`/`--json`), and
   **live 0.6.2 rejects `query monitors` and `--monitor` with
   `invalid_arguments`**. Use the canonical forms only.
2. `fullscreen-uses-outer-gaps` display field: in HEAD manifest + docs, absent
   from the running 0.6.2 (undocumented skew, not a code bug).
3. Minor: docs say the consume-or-expel commands "cannot be assigned as
   shortcuts" — an app-side statement, not visible in the IPC layer; everything
   else in the docs matched code exactly (commands, queries, channels, error
   codes, wire shapes, security notes).

Nothing was found in code that the docs omit entirely — the surface is
data-driven from one manifest, and the docs track it closely; the drift is in
the other direction (docs promising aliases that don't exist).

---

## 5. Assessment against our external-tool needs

### (a) Status bar (per-monitor workspace state + window lists + instant focus events)

**Covered well — this is the strongest part of the surface.**

- One subscription (`subscribe workspace-bar,focus,active-workspace` or
  `--all`) delivers: full per-monitor workspace tree with per-app window groups,
  titles, focus flags, scratchpad state (`workspace-bar`); focused-window
  snapshots (`focus`); interaction monitor + active workspace
  (`active-workspace`). Initial snapshots mean no cold-start query needed.
- Persistent-socket integration is trivial (NDJSON, self-describing envelopes);
  sketchybar-style shell integration works via `watch --exec` (sequential
  children — fine for a bar).
- Gaps: (1) coalescing means a busy burst collapses to the final state — fine
  for a bar; (2) no per-window app *bundle id* in the workspace-bar payload
  (only `appName`; join against `query windows` if icons need bundle ids);
  (3) `workspace-bar` fires only when the projection changes, and the demand
  gating means the first event may lag until a real change; (4) no
  urgent/attention flag on windows.

### (b) External overview (window thumbnails/positions + focus/move)

**Partially covered; thumbnails are the hard missing piece.**

- Have: `query windows --visible` gives frames (screen points), titles, apps,
  pids, workspace/display mapping; `window focus/navigate/summon-right` and
  `rule apply --window` act on specific windows; opaque id ⇄ pid+windowId is
  even decodable (base64url) if CGWindowID-based capture is needed.
- Missing: **no thumbnail/screenshot surface** (would need our own
  ScreenCaptureKit/CGWindowList capture keyed by pid+frame matching — the
  opaque id's embedded windowId is OmniWM's internal AX id, not guaranteed to be
  a CGWindowID); **no move-arbitrary-window-to-workspace** (only the *focused*
  window moves; an external overview must focus-then-move, two steps, with
  focus-flap side effects); **no set-frame**; and the killer interaction:
  OmniWM's own Overview being open blackholes all IPC (`ignored_overview`), so
  an external overview must ensure the built-in one stays closed. No
  window-geometry-changed events — poll or re-query on `windows-changed`.

### (c) Gesture daemon (trigger workspace switches + overview)

**Covered.**

- `command switch-workspace next|prev|<n>` and `switch-workspace anywhere <n>`,
  `focus-monitor next|prev|last`, `command toggle-overview` all exist and take
  the same semantic path as hotkeys (no PhysicalHotkeyTrigger metadata — note
  any OmniWM behavior keyed to physical triggers, e.g. Overview's
  toggle-to-close, won't apply: IPC can only *open* Overview, and once open all
  further IPC is rejected until the user dismisses it locally).
- No-op switches return exit 1 / `not_found` — a gesture daemon should treat
  that as benign.
- No "switch with animation direction hint" or continuous-swipe progress API —
  discrete commands only.

### (d) Scripting surface

What a script can and cannot do over IPC:

- **Available**: queries for windows, workspaces, displays and apps (with
  selectors, `--fields`, and json or tsv output), focus, move, move to a
  workspace (focused window only), switch to workspace `<n>`, workspace
  back-and-forth, move a workspace to a monitor, fullscreen, layout
  (floating/tiling toggle and niri/dwindle selection), resize, balance sizes,
  focus-monitor, swap (via move-column/swap-split), runtime discovery through
  `query capabilities`, and an event loop (`watch`, with 7 channels and JSON
  payloads).
- **Missing**: an exec command (deliberately absent), reload-config, an
  enable/disable toggle (IPC only reports `ignored_disabled` and cannot flip
  it), close and close-all-but-current, moving a *non-focused* window to a
  workspace, native-minimize handling, binding modes, trigger-binding, debug
  dumps of the window tree, and reading the config. Rule add/apply is
  persistent, not per invocation.
- **Strengths**: an authenticated socket, typed JSON envelopes with stable
  error codes, full runtime introspection (`capabilities`), snapshot
  subscriptions with initial state, a per-monitor bar projection, and window
  rules CRUD over IPC.

**Net for omacosy**: bar and gesture integrations can build on this today; an
external overview needs its own capture pipeline plus a focus-then-move dance;
anything needing exec, config mutation, per-window placement, or window-created
granularity needs upstream work (candidate asks: move-window-by-id-to-workspace,
set-frame, window lifecycle events, close-window, and honoring IPC while
Overview is open).
