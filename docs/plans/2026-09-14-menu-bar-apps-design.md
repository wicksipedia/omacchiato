# Menu bar apps pill: design

Date: 2026-09-14. Status: approved.

## Problem

omacosy hides the native macOS menu bar. Third-party menu bar apps, such as
Vorssaint, Karabiner and CleanShot X, put their icons there, so you cannot see
or open them while the menu bar is hidden. The app-name pill already gives you
the running app's menus. This design does the same for menu bar apps.

## Scope

In scope: third-party menu bar apps. Out of scope: Control Center modules, and
the items that omacosy already shows as pills (Wi-Fi, Bluetooth, sound,
battery and clock).

## What you see

- A new right-cluster pill, `menubar`, at the left end of the cluster, with a
  small grid icon. `menubar = hide` in `bar-pills.conf` removes it.
- A click opens a popup in the style of the app-name menu. It has one row for
  each menu bar icon, with the app's icon and name. When an app has more than
  one icon, the row adds that icon's label, for example
  `Vorssaint · Keep Awake`.
- A click on a row closes the popup and opens that app's own menu or panel.
- The last row, `Show menu bar ⌃F8`, shows the native menu bar with keyboard
  focus on its icons.
- With no menu bar apps running, the popup shows `No menu bar apps running`
  and the `Show menu bar` row.

## How it works

- Discovery runs when the popup opens, on a background queue. For each
  running app outside `com.apple.*`, the bar reads the app's
  `AXExtrasMenuBar` attribute. OmniWM's `MenuBarExtrasScanner` uses the same
  attribute on macOS 27. Each app gets a 0.25 s Accessibility messaging
  timeout, so a hung app cannot stall the bar.
- A row's extra label comes from the item's `AXTitle`, or from its
  `AXDescription` when the title is empty.
- A click closes the popup, waits 50 ms and sends `AXPress` to the item, as
  the app-name menu does for its items.
- If `AXPress` fails, or the app has quit since the list was built, the bar
  posts Ctrl+F8 (key code 100 with the Control flag) instead.
- The feature needs Accessibility only, which the bar already has. Without
  it, the popup shows the same rows that ask for the permission as the
  app-name menu does.

## Risk and first step

Nobody has tested `AXPress` on a menu bar icon while the menu bar is hidden.
The first implementation step is a test against the real apps on this Mac.
If `AXPress` does not open the menu, the click changes to this: show the menu
bar with Ctrl+F8, post a click at the item's `AXPosition`, and put the cursor
back. OmniWM's `HiddenBarClickForwarder` forwards clicks the same way.

## Not in this design

- Copying an app's menu into the popup. Many menu bar apps open panels, and
  Accessibility cannot read a status menu until the menu opens.
- Capturing the apps' real icons, which needs Screen Recording.
- Search, reordering and hiding single apps.

## Testing

Test by hand on this Mac: open the popup, check the rows, open each app's
menu, and take screenshots. Check the empty list and the missing permission.
Update the README and the list of pill names in `bar-pills.conf`.

## Outcome

The test changed one decision. `AXPress` opens most menus, but a press on an
icon that the notch hides left the native menu bar stuck on screen until that
app quit. So the pill does not press icons:

- A row for a visible icon posts a real click. The pointer moves to the top
  edge so the menu bar slides in, the bar clicks the icon once the menu bar
  is in place (about 0.25 s, set by macOS's animation), and the pointer moves
  back.
- A row for an icon behind the notch says `opens app` and opens the app.
- `Show menu bar ⌃F8` posts Ctrl+F8 with the Fn flag, as a real function key
  carries it.

macOS has no setting for the menu bar's slide-in, so 0.25 s is the floor for a
real click. Details are in `tasks/plan.md`.
