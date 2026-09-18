# AirPods pill: design

Date: 2026-09-17. Status: approved.

## Problem

The bar shows how many Bluetooth devices are connected, but not the battery
of AirPods or their noise control mode. To see or change either, you open
Control Center or System Settings.

## Scope

In scope: a plugin pill, `omacchiato-airpods`, that shows while AirPods Pro or
AirPods Max are connected. The pill shows the battery. The popup shows each
battery level, the noise control modes with the current one marked, and a
link to Sound settings. A click on a mode sets it.

Out of scope: Conversation Awareness, other AirPods and Beats models, and
automatic switching of the audio output.

Spatial audio: parked on 2026-09-18. `AVOutputDevice` carries
`supportsHeadTrackedSpatialAudio`, `allowsHeadTrackedSpatialAudio` with a
setter, and `headTrackedSpatialAudioMode`. They need the same shared system
audio context as the listening mode, so they need the private entitlement.
A test with the `avbypass.dylib` of `airpods-control` read them for AirPods
Max. `airpods-control` has no spatial audio command. To pick this up, ask
upstream for one, or carry a second bypass in this repo.

## Data sources

The data comes from two command-line tools, not from APIs in the bar.

| Data | Tool | Notes |
|---|---|---|
| Connected devices, model, battery | `system_profiler SPBluetoothDataType -json` | Part of macOS. 0.1 s on this Mac. Keys `device_batteryLevelLeft`, `device_batteryLevelRight`, `device_batteryLevelCase` for AirPods Pro. |
| Noise control mode: read, list, set | [`airpods-control`](https://github.com/raulgg/airpods-control) | MIT. `install.sh` builds it from a pinned source release. `status --json`, `listening-mode list --json`, `listening-mode set <mode>`. Modes: `off`, `transparency`, `adaptive`, `noise-cancellation`. |

Why not in the bar: the bar can read the battery through `IOBluetoothDevice`,
but the listening mode lives in the shared system audio context of
AVFoundation. AVFoundation gives that context only to a process with the
private `com.apple.avfoundation.allow-system-wide-context` entitlement.
`airpods-control` loads a small library into its own process that answers
yes to that one entitlement check. The bar cannot do the same.

### Risks of `airpods-control`

- It is new: created 2026-07-23, v0.4.0 on 2026-09-05, 2 stars.
- Its tests ran on macOS 26. This Mac runs macOS 27.
- Its compatibility table marks the listening-mode commands as verified on
  AirPods Pro 3 and AirPods Pro 2 (Lightning), the model paired to this Mac.
  AirPods Max is "Pending".
- It uses a private API. A macOS update can break it.
- It uses `DYLD_INSERT_LIBRARIES` on its own process. Its `SECURITY.md`
  describes the library. The README must name this risk, because
  `install.sh` installs the tool for every user.

If `airpods-control` is missing or fails, the popup shows the battery rows and
no noise control rows.

## Which devices

The user can rename a device, so the script finds the model from
`device_productID`. macOS ships the Bluetooth product ID of each Apple model
as a `public.bluetooth-vendor-product-id` tag (`76:<decimal ID>`) on a type in
`/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/*/Contents/Info.plist`.
The script counts a type identifier that starts with `com.apple.airpods-pro`
or `com.apple.airpods-max`. On macOS 27 that covers `0x2014`, `0x201F`,
`0x2024`, `0x2027` and `0x202D`, and leaves out AirPods 4 and Beats. A new
model works after the macOS update that adds its type.

The tags start at `0x2014`. The script holds the two older IDs, `0x200A`
(AirPods Max, Lightning) and `0x200E` (AirPods Pro), from the
[Apple Wiki list](https://theapplewiki.com/wiki/Bluetooth_PIDs), which
`airpods-control` also uses. Reading the tags takes 3 ms, and the script
reads them only while an Apple device with a product ID is connected.

## What you see

### Pill

- Hidden while no AirPods Pro or Max is connected. The script prints
  `{"label": ""}`.
- The icon is `md-earbuds` (U+F184F) for AirPods Pro and `md-headphones`
  (U+F02CB) for AirPods Max.
- The label is the lowest battery level of the earbuds, or the AirPods Max
  battery, such as `80%`. The case does not count.
- The label is red at 20% or less.

### Popup

For each connected device:

1. A hero row: the device name, with the model as the detail.
2. Battery rows with a `bar`: Left, Right and Case for AirPods Pro, one
   Battery row for AirPods Max. A value that the device does not report gets
   no row.
3. A separator, then one row for each mode from `listening-mode list`:
   Off, Transparency, Adaptive, Noise Cancellation. The current mode has ✓ as
   its detail. A click sets the mode and refreshes the popup.

Then a separator and a "Sound settings…" row that opens
`x-apple.systempreferences:com.apple.Sound-Settings.extension`.

With two devices connected, each device header is a closed section.

## Changes to the bar

The plugin row format cannot do two of the things above.

1. **A row that runs a command.** A new row key, `run`, holds a shell
   command. A click runs it in the background with the plugin's environment,
   then runs the plugin again, so the popup shows the new mode. It runs with
   the same trust as the plugin command, like `terminal`.
2. **A link to System Settings.** A row `url` opens `https` links only.
   Also allow the `x-apple.systempreferences:` scheme, which only opens a
   System Settings page.

## Refresh

- `interval = 10` in `bar-plugins.conf`, so the pill shows within 10 s of a
  connection.
- Each run calls `system_profiler`. It calls `airpods-control` only when a
  device is connected.
- After a click on a mode, the `run` key runs the plugin at once.

## Spike before the build

Connect each device, then check these items:

1. `system_profiler SPBluetoothDataType -json`: the battery keys for AirPods
   Pro and for AirPods Max, and any charging key.
2. Whether the battery values change while the device is connected, or stay
   at the values from when it connected.
3. `airpods-control status --json` and `listening-mode list --json` on
   macOS 27, for AirPods Pro and for AirPods Max. Time each call.
4. `airpods-control listening-mode set` from a plugin command, so it runs
   as a child of the bar. The bar holds the Bluetooth grant. From a
   terminal, the terminal needs it.

If step 3 fails on macOS 27, build the battery half only.

### Results for AirPods Pro 2 (Lightning), 2026-09-17, macOS 27.0

1. `system_profiler` lists the classic device with `device_productID`
   `0x2014` and `device_batteryLevelLeft`, `device_batteryLevelRight` and
   `device_batteryLevelCase`, such as `"68%"`. It has no charging key. It also
   lists a second connected entry with the same name: a BLE entry with only
   `device_batteryLevelCase` and no product ID. The filter must match on
   `device_productID`, never on the name.
2. The battery values update while the device is connected: left went from
   68% to 67% within 76 s.
3. `airpods-control` 0.4.0 works on macOS 27 from a terminal. `status --json`
   takes 0.38 s, `listening-mode list --json` and `get --json` take 0.02 s.
   The list is `off`, `transparency`, `adaptive`, `noise-cancellation`.
   `status` also reports `leftEarPlacement` and `rightEarPlacement`.
4. `listening-mode set transparency` took 0.07 s, and `get` read the new
   mode at once. `set noise-cancellation` put it back. The test from a
   plugin command waits for the `run` key.
5. `make` builds v0.4.0 in 35 s. The SHA-256 of
   `archive/refs/tags/v0.4.0.tar.gz` is
   `53c7f9ed1846e2dab806301521bee8c3742149e2b4c45c9abf9b2550edd817ad`.

### Results for AirPods Max (USB-C), 2026-09-18, macOS 27.0

1. `system_profiler` reports `device_productID` `0x201F` and no battery key
   at all. `defaults read /Library/Preferences/com.apple.Bluetooth` and
   `ioreg` carry none either.
2. `IOBluetoothDevice.batteryPercentSingle()`, a private method, returns the
   level. So `omacchiato-helper` gets a `bt battery` subcommand that prints
   `<address> <single> <left> <right> <case>` for each connected device, and
   the script fills the gaps in the `system_profiler` values from it.
3. `airpods-control` reads and lists the modes for AirPods Max on macOS 27.
   The list is `off`, `transparency` and `noise-cancellation`, with no
   Adaptive, and the popup shows exactly those three.

## Build order

1. Spike.
2. Bar: the `run` row key and the `x-apple.systempreferences:` scheme in
   `helper/bar.swift`.
3. `bin/omacchiato-airpods`: the device filter, battery, modes and rows.
4. `install.sh`: link the script, and install `airpods-control` the way it
   installs tokscale:
   - Pin `AIRPODS_CONTROL_VERSION=0.4.0` and the SHA-256 of the tag's source
     tarball. Change both together.
   - Download
     `https://github.com/raulgg/airpods-control/archive/refs/tags/v<version>.tar.gz`,
     check the hash, run `make` and
     `make install PREFIX=~/.local/lib/airpods-control-<version>`. The
     build needs the Command Line Tools, which the bar build needs too.
   - Link `bin/airpods-control` into `~/.local/bin`. Remove older versions
     only after the new one is in place.
   - If the build fails, log a warning. The pill then shows battery only.
   - `uninstall.sh`: remove the link and `~/.local/lib/airpods-control-*`.
5. README:
   - "Plugin pills": an AirPods bullet.
   - "Adding pills": the `run` key and the `x-apple.systempreferences:`
     scheme.
   - "Plugins and scripts in this repo": an `omacchiato-airpods` row.
   - "Fetched or wired by install.sh": the `airpods-control` row, with the
     pinned version and the private API it uses.
   - A new "The AirPods pill" section: the config lines, the devices, the
     risks of `airpods-control` and the version that `install.sh` pins.
6. CLAUDE.md: the `run` key in the row key list, and a note under "Pill
   scripts".

## Testing

- No AirPods connected: the script prints `{"label": ""}`.
- AirPods Pro connected: label, battery rows, mode rows, ✓ on the current
  mode. Set each mode from the popup and check it with
  `airpods-control listening-mode get`.
- AirPods Max connected: one battery row, and no Adaptive row if the list
  leaves it out.
- `airpods-control` missing from `PATH`: battery rows only.
- `python3 -m py_compile` on the script, `bash -n install.sh`, and a
  rebuild of the bar.
