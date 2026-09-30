# Todo: keep awake, lid closed, quit on close

Plan: `tasks/plan.md`. Design: `docs/plans/2026-09-30-keep-awake-and-quit-on-close-design.md`.

## Phase 1: keep awake from the command line
- [x] T1 Spike: which posted event resets the idle time (XS)
- [x] T2 State file, command and always-on pill (S)
- [ ] T3 The bar holds the assertion from the state file (M)
- [ ] Checkpoint A: assertion follows the command; review with the user

## Phase 2: every way in, and Vorssaint's options
- [ ] T4 Super+Esc and the keep-awake HUD (M)
- [ ] T5 Right-click on a plugin pill (S)
- [ ] T6 On/off and time buttons in the popup (M)
- [ ] T7 Mouse jiggle, paused while locked (S)
- [ ] T8 Battery limit (S)
- [ ] T9 Keep Awake settings page and docs (M)
- [ ] Checkpoint B: release; turn off keep awake in Vorssaint

## Phase 3: lid closed
- [ ] T10 Sudoers rule in install.sh and uninstall.sh (S)
- [ ] T11 The bar sets disablesleep with keep awake (S)
- [ ] Checkpoint C: release; remove Vorssaint's lid setting

## Phase 4: quit on close
- [ ] T12 Spike: AX windows with OmniWM parked windows (XS)
- [ ] T13 The quit decision as a pure function (S)
- [ ] T14 Watch windows and quit the app (M)
- [ ] T15 Seed the exceptions from Vorssaint (S)
- [ ] T16 Quit on Close settings page and docs (M)
- [ ] Checkpoint D: release; turn off quit on close in Vorssaint
