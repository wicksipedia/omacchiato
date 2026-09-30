# Todo: keep awake, lid closed, quit on close

Plan: `tasks/plan.md`. Design: `docs/plans/2026-09-30-keep-awake-and-quit-on-close-design.md`.

## Phase 1: keep awake from the command line
- [x] T1 Spike: which posted event resets the idle time (XS)
- [x] T2 State file, command and always-on pill (S)
- [x] T3 The bar holds the assertion from the state file (M)
- [x] Checkpoint A: assertion follows the command; review with the user

## Phase 2: every way in, and Vorssaint's options
- [x] T4 Super+Esc and the keep-awake HUD (M)
- [x] T5 Right-click on a plugin pill (S)
- [x] T6 On/off and time buttons in the popup (M)
- [x] T7 Mouse jiggle, paused while locked (S)
- [x] T8 Battery limit (S)
- [x] T9 Keep Awake settings page and docs (M)
- [x] Checkpoint B: release; turn off keep awake in Vorssaint (tested locally, release pending)

## Phase 3: lid closed
- [x] T10 Sudoers rule in install.sh and uninstall.sh (S)
- [x] T11 The bar sets disablesleep with keep awake (S)
- [x] Checkpoint C: release; remove Vorssaint's lid setting (tested with the lid, release pending)

## Phase 4: quit on close
- [x] T12 Spike: AX windows with OmniWM parked windows (XS)
- [x] T13 The quit decision as a pure function (S)
- [x] T14 Watch windows and quit the app (M)
- [ ] T15 Seed the exceptions from Vorssaint (S)
- [ ] T16 Quit on Close settings page and docs (M)
- [ ] Checkpoint D: release; turn off quit on close in Vorssaint
