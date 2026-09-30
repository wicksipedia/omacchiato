# Implementation plan: Settings layout, pill order and a memory log

## Overview

Make the bar's pills reorderable, built-in and plugin pills alike, and
reorganise the Settings window by task instead of by how a pill is
built. Add a debug log of the bar's memory. Then bring README.md and
docs/bar.md up to date with every feature added since the last release.
The findings come from a design review (apple-skills:macos,
design:design-critique), a code review of pill order, and a memory
check, all on 2026-09-30.

The keep-awake and quit-on-close plan that this file held before is in
git history (commit 257d382 and earlier).

## Findings

- **Memory:** the bar used about 45 MB after a restart this morning,
  and 104 MB after 22 minutes this evening, steady over a minute.
  `leaks` finds 144 bytes. The live heap is about 35 MB; most of the
  rest is "Malloc Small" pages that the allocator keeps after the bar
  frees them (popups, Settings, HUDs). One reading cannot show a trend,
  so S0 logs it.
- **Order:** no control can reorder pills. `pillOrder`
  (helper/bar/Plugins.swift:86) is always menubar, then the plugins in
  file order, then `rightOrderAll` (helper/bar/bar.swift:649), which the
  code fixes. A plugin can never sit between two built-in pills.
- The Layout page holds only two gap steppers, and the window opens on it.
- The sidebar groups pills by how they are built: Keep Awake is under
  Plugins, and Activity (built-in) and Stats (plugin) show the same data
  in different groups. Music is listed first, but it draws on the left.
- Hidden pills show only as a faded icon. Two controls hide a pill: the
  "Show in bar" switch and styles such as "Only while muted".
- The HUD and click switches are on three pages: Sound, Microphone and
  Keep Awake.
- Config Files sits between features and pills. "Add Plugin" is a
  sidebar row, not a button.
- Labels put units and the off value in the text: "Move the mouse
  every, in minutes (0 is off)".
- README.md does not mention the "Customize Pill" link, the Quit on
  Close switch in the Activity popup, "Other…" in Quit on Close, or
  `right_click`. docs/bar.md does not mention volume_hud, volume_click,
  mic_hud, keep_awake_*, quit_on_close, right_click, the PR swipe or
  the keep-awake command.

## Architecture decisions

- **`debug = on` in bar-pills.conf** turns on a memory line in
  `/tmp/omacchiato-bar.log` each minute: the physical footprint and the
  malloc bytes in use. The bar reads the key at each tick, so it
  switches on and off live.
- **One `order` key in bar-pills.conf** holds the right-hand order:
  `order = github, weather, clock, status`. `pillOrder` takes the named
  pills first, drops unknown names and duplicates, then adds every pill
  it did not name in today's default order. So no key gives today's bar,
  and a new pill or plugin still shows. Hidden pills keep their place
  in the key, so showing one again puts it back where it was.
- **The Bar page replaces Layout and opens first.** It holds a
  drag-to-reorder list of the right-hand pills (a `List` with `onMove`;
  Settings is a key window, so system controls work), a visibility
  switch and a link per row, a + button for plugins, a Reset Order
  button, and the gap steppers.
- **Sidebar by task:** General (Theme, Bar), Pills (in bar order, with a
  Hidden section, and Music under its own Left heading), Features (Quit
  on Close, Keep Awake, HUDs & Sounds), Advanced (Config Files).
- **No config change for the regroup.** Every key keeps its name; only
  where Settings shows it changes.

## Task list

### Phase 0: memory
- [x] S0: Log the bar's memory each minute with `debug = on`

### Phase 1: pill order
- [x] S1: The `order` key in pillOrder
- [x] S2: The Bar page, with the drag-to-reorder list

### Checkpoint A
- [ ] `bin/omacchiato-test` passes
- [ ] Dragging Clock above Status in Settings moves it in the bar at once
- [ ] A plugin can sit between two built-in pills
- [ ] Reset Order brings back today's order
- [ ] Review with the user, with a day of memory lines

### Phase 2: sidebar by task
- [x] S3: Regroup the sidebar
- [x] S4: A HUDs & Sounds page

### Checkpoint B
- [ ] Every key still has a control (SettingsCoverageTests)
- [ ] Review with the user

### Phase 3: controls
- [ ] S5: One visibility control per pill
- [ ] S6: Units and Off on number rows
- [ ] S7: Tell Activity and Stats apart

### Phase 3b: icons
- [ ] S9: A searchable Nerd Font glyph picker

### Phase 4: docs
- [ ] S8: README.md and docs/bar.md

### Checkpoint C
- [ ] `bin/omacchiato-test` passes
- [ ] Commit, push, release

## Tasks

### S0: Log the bar's memory each minute with `debug = on`

**Description:** A one-minute timer in the bar reads `task_info`
(`TASK_VM_INFO` phys_footprint) and `mstats()` bytes in use. With
`debug = on` in bar-pills.conf, it writes a `tlog` line such as
`memory: footprint 104.2 MB, malloc 35.1 MB in use`. With the key off,
it writes nothing. A switch on the Advanced page sets the key.

**Acceptance criteria:**
- [ ] One line a minute while `debug = on`, none while off, with no
      restart
- [ ] The number matches `footprint <pid>` to within a few MB

**Verification:**
- [ ] A test for the line's text from plain numbers; manual: turn it on,
      read the log, turn it off

**Dependencies:** None
**Files:** helper/bar/bar.swift or a new helper/bar/Debug.swift,
helper/bar/main.swift, helper/bar/Settings.swift, tests/bar/
**Scope:** S

### S1: The `order` key in pillOrder

**Description:** `pillOrder(modes:plugins:)` reads `modes["order"]`:
the named pills first, then the rest in today's default order, then the
hide and opt-in filter as now. `reloadConfig` and the first read of
`rightOrder` use it, so a changed order redraws live. A reorder does
not restart plugins.

**Acceptance criteria:**
- [ ] With no `order` key, the order is the same as today
- [ ] A saved order moves built-ins and plugins, for example a plugin
      after Clock; unknown names and duplicates are ignored; missing
      pills follow in default order
- [ ] A hidden pill keeps its place and comes back to it

**Verification:**
- [ ] New cases in tests/bar/ConfigTests.swift; `bin/omacchiato-test`
- [ ] Manual: add `order = clock, status` to bar-pills.conf and watch
      the bar

**Dependencies:** None
**Files:** helper/bar/Plugins.swift, helper/bar/Config.swift,
tests/bar/ConfigTests.swift
**Scope:** S

### S2: The Bar page, with the drag-to-reorder list

**Description:** A "Bar" page replaces Layout and becomes the first
page. It lists every right-hand pill in order, hidden ones dimmed, each
with its icon, a Show switch and a chevron to its page. Drag to
reorder writes `order` through `confSet`. Under the list: a + button
that opens Add Plugin, and Reset Order, which removes the key. The gap
steppers move to the bottom. `SettingsReport` gets the full order.

**Acceptance criteria:**
- [ ] A drag writes `order` and the bar redraws at once
- [ ] Show/hide from the list works as on each pill's page
- [ ] Previews show the page with sample pills

**Verification:**
- [ ] `swift build`; a test that the report's order covers every pill
- [ ] Manual: Checkpoint A

**Dependencies:** S1
**Files:** helper/ui/Sources/SettingsPanel/SettingsView.swift,
SettingsReport.swift, SettingsPreviews.swift, helper/bar/Settings.swift
**Scope:** M

### S3: Regroup the sidebar

**Description:** Sidebar sections: General (Theme, Bar); Pills in bar
order, with Music under a Left heading and hidden pills in a Hidden
section; Features (Quit on Close, Keep Awake, HUDs & Sounds); Advanced
(Config Files, and the debug switch from S0). Remove the Add Plugin row
(the + button on the Bar page replaces it). Pill summaries say where a
pill draws when that is not obvious.

**Acceptance criteria:**
- [ ] The sidebar order follows the bar order and changes with a drag
- [ ] Every page is still reachable, including a deep link from a popup

**Verification:**
- [ ] `swift build`, SettingsCoverageTests; rendered screenshots of the
      sidebar, light and dark

**Dependencies:** S2
**Files:** SettingsView.swift, helper/bar/Settings.swift,
SettingsPreviews.swift
**Scope:** M

### S4: A HUDs & Sounds page

**Description:** One page with the volume HUD, volume click, mic HUD
and keep-awake HUD switches. They leave the Sound, Microphone and Keep
Awake pages. The keys do not change.

**Acceptance criteria:**
- [ ] Each switch writes the same key as before
- [ ] The three pill pages no longer show them

**Verification:**
- [ ] SettingsCoverageTests; manual: turn each off and check its effect

**Dependencies:** S3
**Files:** helper/bar/Settings.swift, SettingsView.swift,
SettingsReport.swift
**Scope:** S

### S5: One visibility control per pill

**Description:** Fold "Show in bar" into the style choice as a Hidden
option, and draw the style as a menu or segmented picker instead of the
inline radio card. Opt-in pills (Wi-Fi, Battery) keep their rule: they
show only with a value.

**Acceptance criteria:**
- [ ] One control sets shown, hidden or a style
- [ ] Opt-in pills behave as before

**Verification:**
- [ ] SettingsCoverageTests; manual on Sound, Wi-Fi and a plugin

**Dependencies:** S3
**Files:** SettingsView.swift, SettingsReport.swift
**Scope:** M

### S6: Units and Off on number rows

**Description:** `Number` gets a unit and an optional off value, so the
row reads "Move the mouse every · 1 min" and shows "Off" at 0.

**Acceptance criteria:**
- [ ] Keep Awake and Music rows read with units; 0 shows Off where 0
      turns the option off

**Verification:**
- [ ] Rendered screenshot; `swift build`

**Dependencies:** None
**Files:** SettingsReport.swift, SettingsView.swift,
helper/bar/Settings.swift
**Scope:** S

### S7: Tell Activity and Stats apart

**Description:** Activity is the built-in CPU and memory popup with the
busiest apps. Stats is a plugin pill that shows one number in the bar.
Say so in both summaries. Do not merge them.

**Dependencies:** None. **Files:** helper/bar/Settings.swift. **Scope:** XS

### S9: A searchable Nerd Font glyph picker

**Description:** Today a plugin page offers about 30 icons and a field to
paste one. Make one picker that searches every Nerd Font glyph by name
("coffee", "github", "wifi"), from Nerd Fonts' `glyphnames.json`, which
`install.sh` downloads at a pinned version and checksum, as it does for
tokscale. The plugin Icon row uses it. The Config Files editor gets an
"Insert Icon…" button that puts the chosen glyph at the cursor
(`TextEditor(text:selection:)`). The editor font from 037c3a9 already
draws the glyphs.

**Acceptance criteria:**
- [ ] A search for "coffee" finds the cup that the keep-awake pill uses
- [ ] Insert Icon puts the glyph at the cursor in the open file
- [ ] With no glyph file, the picker falls back to today's short list

**Verification:**
- [ ] A test for the search from a small sample of glyphnames.json;
      `bash -n install.sh`; manual: insert an icon into bar-plugins.conf

**Dependencies:** None
**Files:** install.sh, SettingsView.swift, SettingsReport.swift,
helper/bar/Settings.swift, tests
**Scope:** M

### S8: README.md and docs/bar.md

**Description:** Document every feature since v2026.09.30 where a user
looks for it. README: the Customize Pill link, the Quit on Close switch
in the Activity popup, "Other…", the Bar page, pill order and the debug
log. docs/bar.md: `order`, `debug`, `volume_hud`, `volume_click`,
`mic_hud`, `keep_awake_display`, `keep_awake_jiggle`,
`keep_awake_battery`, `keep_awake_lid`, `keep_awake_hud`,
`quit_on_close`, `right_click`, the keep-awake command and state file,
and the PR swipe and mark-read.

**Acceptance criteria:**
- [ ] Every key that Settings writes appears in docs/bar.md
- [ ] stop-slop and STE rules applied

**Verification:**
- [ ] A grep of each key in docs/bar.md

**Dependencies:** S0–S7
**Files:** README.md, docs/bar.md
**Scope:** M

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| A saved order names a pill that is gone | Low | Unknown names are dropped; missing ones are added |
| `List.onMove` inside a grouped Form draws oddly | Medium | Render screenshots in both modes before commit |
| Folding Show into the style picker breaks opt-in pills | Medium | Keep their "show" value; test Wi-Fi and Battery |
| The regroup hides a page | Medium | SettingsCoverageTests, and deep links from popups |
| The memory log itself costs memory | Low | One timer and one line a minute; nothing while off |
