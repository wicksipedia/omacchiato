# Implementation plan: menu bar apps pill

Design: `docs/plans/2026-09-14-menu-bar-apps-design.md` (approved).

## Overview

Add a `menubar` pill to the Omacchiato bar. Its popup lists the running
third-party menu bar apps, and a click on a row opens that app's own menu.
All the work is in `helper/bar.swift`, plus the README.

## Architecture decisions

- The bar finds menu bar icons through each app's `AXExtrasMenuBar`
  Accessibility attribute. OmniWM uses the same attribute on macOS 27. The
  bar already has Accessibility permission for the app-name menu.
- The scan runs when the popup opens, on a background queue, with a 0.25 s
  messaging timeout for each app. `popupRows(for:)` must return rows at once,
  so it returns the last scan's rows (or a `Looking…` row) and the new scan
  calls `refreshPopup()` when it ends. Nothing polls.
- A click sends `AXPress` to the icon, unless Task 1 shows that this does not
  work while the menu bar is hidden. The fallback is Ctrl+F8, posted as a
  keyboard event, which shows the native menu bar with focus on its icons.
- The pill sits at the left end of the right cluster, before the plugin
  pills. `menubar = hide` in `bar-pills.conf` works with no new code, because
  `rightOrder` already drops hidden pills.
- No Screen Recording, no icon capture, no copied menus.

## Dependency graph

```
Task 1: scan + press, behind a test trigger (proves AXPress)
   │
   ├── Task 2: pill + popup list + click (uses the method Task 1 chose)
   │      │
   │      └── Task 3: Show menu bar row + Ctrl+F8 fallback + edge states
   │              │
   │              └── Task 4: docs, remove the test trigger
```

## Task list

### Phase 1: prove the risky part

#### Task 1: Test AXPress on real menu bar icons while the menu bar is hidden

**Description:** Add the scan (`menuBarItems()`) and the press
(`pressMenuBarItem(_:)`) to the bar with no interface. A temporary trigger
file, `/tmp/omacchiato-bar-menubar-test`, makes the bar log every item it found
and press the item whose index the file contains. Use it on at least three
apps, including one Electron app if one is running.

**Acceptance criteria:**
- [ ] The bar log lists each third-party menu bar icon with its app name and label.
- [ ] For each tested app, the plan records whether `AXPress` opens its menu or panel, where it appears, and whether macOS shows the menu bar.
- [ ] A decision is recorded: `AXPress`, or show the menu bar and click the icon's position.

**Verification:**
- [ ] Build succeeds (the `swiftc` command in `install.sh`), and the bar restarts with `launchctl kickstart -k gui/$(id -u)/com.omacchiato.bar`.
- [ ] Manual check: screenshots of each opened menu.

**Dependencies:** none.
**Files likely touched:** `helper/bar.swift`.
**Estimated scope:** S.

#### Task 1 results (2026-09-14)

The scan found 9 icons in 204 ms: CleanShot X, Crank, ZoomIt, Vorssaint,
1Password, Velja, OneDrive (two accounts) and OmniWM.

| App | Menu opened | Where it opened | `AXPress` result |
|-----|-------------|-----------------|------------------|
| CleanShot X | yes | under its own icon | `-25204` after 1.6 s |
| 1Password (Electron) | yes | top-left corner of the screen | `-25204` after 1.6 s |
| Velja | yes | top-left corner of the screen | `-25204` after 1.6 s |
| OneDrive | nothing visible | none | `0` after 0.1 s |

Findings:
- `AXPress` waits while the menu is open and then reports `-25204`
  (cannot complete), so the press must run off the main thread and must not
  treat `-25204` as a failure.
- 1Password and Velja have icons that do not fit beside the notch, so macOS
  hides them. Their menus open at the top-left corner of the screen.
- OneDrive reports success but opens nothing, so a success result does not
  prove that a menu opened.
- macOS shows its menu bar while a menu is open. After the bar cancelled the
  menus with `AXCancel`, the native menu bar stayed on screen and covered the
  Omacchiato bar.
- Labels: most are empty or symbol names ("Pawprint"). OneDrive's label
  repeats the app name and has a second line, so a row uses the first line
  without the app name, and only when an app has several icons.
- One write to the trigger file fired the watch twice. Commands now carry a
  nonce.

Recommendation: keep `AXPress`, keep `Show menu bar` as the way out for apps
like OneDrive, and make Task 2 find out why the native menu bar stays shown.

Retest (11:04, no meeting): the bar pressed CleanShot X once and you closed
its menu with a click. Two and ten seconds later the native menu bar had
hidden itself again. So a press is safe when the menu closes the normal way.
The stuck menu bar most likely came from the bar closing menus with
`AXCancel`, or from the Teams call.

Decision: use `AXPress`, and never close an app's menu from the bar.

Real use (11:12): you pressed CleanShot X, Crank and OmniWM from the new pill
and closed each menu with a click. The native menu bar stayed on screen
again. No menu or panel was open, no press was still waiting, and Escape did
not help. This morning the same state cleared by itself after about 15 to 20
minutes.

Decision, revised: do not use `AXPress`. A row posts a real click instead,
the way OmniWM's `HiddenBarClickForwarder` does. The pointer first moves to
the top edge above the icon, so the hidden menu bar slides in. Then the bar
clicks the icon's centre and moves the pointer back. An icon with no position
on screen, or one behind the notch, gets `Show menu bar` instead.

Icon positions (11:23, menu bar showing): OneDrive 1370 and 1406, OmniWM
1442, CleanShot X 1476, Vorssaint 1510, ZoomIt 1560. Crank, 1Password and
Velja sit at -1,1157, which is where macOS parks icons that the notch hides.
Both stuck episodes included a press on one of those parked icons (1Password
and Velja, then Crank), and the retest that did not stick pressed only a
visible icon. So the likely trigger is a press on an icon behind the notch.
The real-click design never clicks those icons.

Confirmed at 11:24: quitting Crank released the stuck menu bar at once. A
press from the pill on 1Password, also behind the notch, stuck it again. So
the app whose hidden icon was pressed holds the menu bar until it quits. You
also saw an app's menu blink in and out after a row click with `AXPress`.
The pill's rows now use the real click.
Confirmed again at 11:45: quitting 1Password released the menu bar at once.

Real-click test (11:50): OmniWM, CleanShot X and a third visible icon all
opened, but a little slowly, because the bar waited a fixed 0.4 s for the
menu bar. The hidden icons did nothing, because the Ctrl+F8 event lacked the
Fn flag. The window list tells hidden from shown: hidden, the menu bar window
sits at y = -39 and is off screen; shown, it sits at y = 0.

Changes: the bar polls for the menu bar every 15 ms (at most 0.6 s) and
clicks once it is in place. An icon parked behind the notch opens its app,
and its row says so. The Ctrl+F8 event carries the Fn flag.

### Checkpoint: activation method

- [ ] You review the Task 1 results and approve the activation method.

### Phase 2: the feature

#### Task 2: A menubar pill lists menu bar apps and opens one on click

**Description:** Add the `menubar` pill with a grid icon at the left end of
the right cluster. `popupRows(for: "menubar")` returns one row for each icon,
with the app's icon and name, plus `· label` when an app has several icons.
It shows cached rows at once and refreshes after a background scan. A click
closes the popup and opens the app's menu with the method from Task 1.

**Acceptance criteria:**
- [ ] A click on the pill opens a popup that lists the running third-party menu bar apps, and no Apple items.
- [ ] A click on a row opens that app's own menu or panel.
- [ ] An app that does not answer within 0.25 s does not delay the popup.

**Verification:**
- [ ] Build succeeds, and the bar restarts.
- [ ] Manual check: screenshot of the popup, and of the menu that opens for each app from Task 1.

**Dependencies:** Task 1.
**Files likely touched:** `helper/bar.swift`.
**Estimated scope:** M.

#### Task 3: Show the menu bar on request and when a press fails

**Description:** Add the last row, `Show menu bar ⌃F8`, which posts Ctrl+F8
(key code 100 with the Control flag). Use the same call when a press fails or
the app has quit since the scan. Add the empty state, `No menu bar apps
running`, and reuse the app-name menu's rows for missing Accessibility.

**Acceptance criteria:**
- [ ] The `Show menu bar` row shows the native menu bar with focus on its icons.
- [ ] A press that fails, or an app that has quit, shows the menu bar and does not fail silently.
- [ ] With no menu bar apps, or no Accessibility permission, the popup says so.

**Verification:**
- [ ] Build succeeds, and the bar restarts.
- [ ] Manual check: the `Show menu bar` row; quit an app with the popup open and click its row.

**Dependencies:** Task 2.
**Files likely touched:** `helper/bar.swift`.
**Estimated scope:** S.

### Checkpoint: feature complete

- [ ] The whole flow works on your real apps: open the pill, choose an app, use its menu.
- [ ] `menubar = hide` removes the pill.
- [ ] You review the screenshots.

### Phase 3: finish

#### Task 4: Document the pill and remove the test trigger

**Description:** Remove the Task 1 trigger file code. Describe the pill in the
README bar section, and add `menubar` to the pill names in the README and in
the `bar-pills.conf` header comment.

**Acceptance criteria:**
- [ ] The bar has no test trigger code left.
- [ ] The README describes the pill, the click behaviour and the Ctrl+F8 fallback.

**Verification:**
- [ ] Build succeeds, and the bar restarts.
- [ ] `grep menubar-test helper/bar.swift` finds nothing.

**Dependencies:** Task 3.
**Files likely touched:** `helper/bar.swift`, `README.md`.
**Estimated scope:** XS.

### Checkpoint: complete

- [ ] All acceptance criteria are met.
- [ ] The changes are committed and pushed to the fork.

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| `AXPress` does not open a menu while the menu bar is hidden | High | Task 1 tests it first. The fallback shows the menu bar, then clicks the icon's position, as OmniWM's `HiddenBarClickForwarder` does. |
| A hung app blocks Accessibility calls | Medium | A 0.25 s messaging timeout for each app, and the scan runs off the main thread. |
| An Electron app ignores `AXPress` | Medium | Task 1 tests an Electron app if one is running. The fallback covers it. |
| You turned off the Ctrl+F8 shortcut in System Settings | Low | The README says how to turn it back on. |

## Open questions

- Which menu bar apps do you use most? Task 1 should test those.

## Outcome (2026-09-14)

All four tasks are done. The pill, the popup and `Show menu bar` work on this
Mac. Rows click visible icons for real, and rows for icons behind the notch
open the app. Task 4 removed the test trigger and the unused `AXPress` helper.
You chose to keep the click at about 0.25 s: macOS has no setting for the
menu bar's slide-in, and a click during the slide could miss.
