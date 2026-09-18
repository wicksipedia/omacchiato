// omacchiato-helper — tiny compiled utility replacing four brew dependencies
// (cliclick, desktoppr, switchaudio-osx, blueutil):
//   cursor                  print the cursor position as "x,y" (CG top-left)
//   cursor set <x> <y>      warp it there (no synthetic movement, so
//                           focus-follows-mouse cannot react)
//   displays                per display (arrangement order): "index<TAB>notched"
//   wallpaper <path>        set the desktop picture on every screen
//   audio list              output devices: "*<TAB>name" (current) / "-<TAB>name"
//   audio set <name>        make <name> the default output device
//   bt power                print bluetooth power state (0/1)
//   bt power <on|off|toggle>
//   bt devices              paired devices: "<1|0 connected><TAB>address<TAB>name<TAB>kind"
//                           kind is a coarse class-of-device keyword
//                           (headphones/speaker/mic/keyboard/pointer/
//                           combo/phone/watch/device) for popup icons
//   bt connect <address> / bt disconnect <address>
//   brightness              print the built-in display's brightness (0-100)
//   brightness set <0-100>  set it (DisplayServices — built-in/Apple
//                           displays only; external DDC is out of scope)
//   nightshift              print night shift state (on/off)
//   nightshift <on|off|toggle>
//   lock                    lock the screen NOW (SACLockScreenImmediate)
//   capslock off            clear the HID-system caps-lock latch (with the
//                           key remapped to Super, a latched LED is
//                           otherwise permanent)
// Built by install.sh with swiftc (present wherever Homebrew is).
// Bluetooth subcommands need the Bluetooth privacy permission of the
// *responsible* process (sketchybar, for bar plugins).
import AppKit
import CoreAudio
import IOBluetooth
import IOKit.hidsystem

// private but stable power API — the same symbols blueutil links
@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func BTGetPower() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
func BTSetPower(_ state: Int32)

// AirPods carry their battery only in these private IOBluetoothDevice
// methods. system_profiler reports none at all for AirPods Max.
@objc private protocol BatteryInfo {
    @objc optional func batteryPercentSingle() -> Int
    @objc optional func batteryPercentLeft() -> Int
    @objc optional func batteryPercentRight() -> Int
    @objc optional func batteryPercentCase() -> Int
}

// DisplayServices (private) — the same calls Control Center makes;
// covers the built-in panel and Apple externals
@_silgen_name("DisplayServicesGetBrightness")
func DSGetBrightness(_ display: CGDirectDisplayID, _ value: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
func DSSetBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Int32

func builtinDisplayID() -> CGDirectDisplayID {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var n: UInt32 = 0
    guard CGGetActiveDisplayList(8, &ids, &n) == .success else { return CGMainDisplayID() }
    for i in 0..<Int(n) where CGDisplayIsBuiltin(ids[i]) != 0 {
        return ids[i]
    }
    return CGMainDisplayID()
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

// --- CoreAudio ---------------------------------------------------------

func audioProperty(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

func defaultOutputDevice() -> AudioDeviceID {
    var addr = audioProperty(kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

func outputDevices() -> [AudioDeviceID] {
    var addr = audioProperty(kAudioHardwarePropertyDevices)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.filter { id in
        var streamsAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var streamsSize = UInt32(0)
        AudioObjectGetPropertyDataSize(id, &streamsAddr, 0, nil, &streamsSize)
        return streamsSize > 0
    }
}

func deviceName(_ id: AudioDeviceID) -> String {
    var addr = audioProperty(kAudioObjectPropertyName)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    withUnsafeMutablePointer(to: &name) { ptr in
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
    }
    return name as String
}

// --- dispatch ----------------------------------------------------------

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "cursor":
    // `cursor set X Y` warps without synthesising movement, which is
    // exactly what a script wants: focus-follows-mouse is movement-gated,
    // so placing the pointer this way cannot make it steal focus.
    if args.count > 2, args[2] == "set" {
        guard args.count > 4, let x = Double(args[3]), let y = Double(args[4])
        else { fail("usage: cursor set <x> <y>") }
        CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
        break
    }
    guard let e = CGEvent(source: nil) else { exit(1) }
    print("\(Int(e.location.x)),\(Int(e.location.y))")

case "ghostty-reload":
    // AppleScript addresses an app by bundle, so it reaches ONE instance.
    // omacchiato opens a Ghostty instance per window, so a theme switch left
    // every other window on the old colours. An Apple Event can be aimed at
    // a process instead, so aim one at each.
    let code = { (s: String) -> OSType in
        s.unicodeScalars.reduce(0) { $0 << 8 | OSType($1.value) }
    }
    func specifier(want: OSType, form: OSType, data: NSAppleEventDescriptor,
                   container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let r = NSAppleEventDescriptor.record()
        r.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: AEKeyword(keyAEDesiredClass))
        r.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        r.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        r.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return r.coerce(toDescriptorType: DescType(typeObjectSpecifier)) ?? r
    }
    // "terminal 1" of the application, not of its front window: an
    // instance whose windows hold no terminal fails the front-window form.
    // The action reloads the whole config but still wants a surface.
    let terminal = specifier(want: code("Gtrm"), form: code("indx"),
                             data: NSAppleEventDescriptor(int32: 1), container: NSAppleEventDescriptor.null())

    var reloaded = 0, targets = 0
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty") {
        let event = NSAppleEventDescriptor(
            eventClass: code("Ghst"), eventID: code("PfAc"),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setDescriptor(NSAppleEventDescriptor(string: "reload_config"), forKeyword: AEKeyword(keyDirectObject))
        event.setDescriptor(terminal, forKeyword: AEKeyword(code("GonT")))
        // A handler error comes back inside the reply, not as a throw.
        let err: Int32
        do {
            let reply = try event.sendEvent(options: [.waitForReply], timeout: 2)
            err = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
        } catch { err = Int32((error as NSError).code) }
        // no terminal in this instance, so nothing to repaint
        if err == Int32(errAENoSuchObject) { continue }
        targets += 1
        if err == 0 { reloaded += 1 }
        else { FileHandle.standardError.write("ghostty-reload: pid \(app.processIdentifier) failed (\(err))\n".data(using: .utf8)!) }
    }
    print("\(reloaded)/\(targets)")

case "displays":
    // arrangement-ordered (left to right):
    // "<index><TAB><1 if notched else 0>"
    let screens = NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    for (i, scr) in screens.enumerated() {
        let notched = scr.safeAreaInsets.top > 0 ? 1 : 0
        print("\(i + 1)\t\(notched)")
    }

case "wallpaper":
    guard args.count > 2 else { fail("usage: wallpaper <path> | wallpaper get") }
    // `get` prints each screen's current wallpaper path in arrangement
    // order — install.sh records these so uninstall.sh can put the
    // pre-omacchiato picture back instead of leaving the theme wallpaper
    // as a souvenir.
    if args[2] == "get" {
        for screen in NSScreen.screens.sorted(by: { $0.frame.origin.x < $1.frame.origin.x }) {
            print(NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "")
        }
        break
    }
    let url = URL(fileURLWithPath: args[2])
    var failures = 0
    for screen in NSScreen.screens {
        do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
        catch { failures += 1 }
    }
    exit(failures == 0 ? 0 : 1)

case "nightshift":
    // CBBlueLightClient (private CoreBrightness) — what Control Center
    // itself calls. Only the leading `active`/`enabled` fields of the
    // status struct are read; the rest is layout padding per the OSS
    // `nightlight` tool.
    guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
        let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
    else { fail("nightshift: CoreBrightness unavailable") }
    let client = cls.init()
    struct BLStatus {
        var active: ObjCBool = false
        var enabled: ObjCBool = false
        var sunSchedulePermitted: ObjCBool = false
        var mode: Int32 = 0
        var schedule: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
        var disableFlags: UInt64 = 0
        var available: ObjCBool = false
    }
    func blEnabled() -> Bool {
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard let m = class_getInstanceMethod(cls, sel) else { return false }
        typealias GetFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let f = unsafeBitCast(method_getImplementation(m), to: GetFn.self)
        var st = BLStatus()
        _ = withUnsafeMutablePointer(to: &st) { f(client, sel, UnsafeMutableRawPointer($0)) }
        return st.enabled.boolValue
    }
    func blSet(_ on: Bool) {
        let sel = NSSelectorFromString("setEnabled:")
        guard let m = class_getInstanceMethod(cls, sel) else { fail("nightshift: setEnabled missing") }
        typealias SetFn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let f = unsafeBitCast(method_getImplementation(m), to: SetFn.self)
        _ = f(client, sel, on)
    }
    switch args.count > 2 ? args[2] : "status" {
    case "on": blSet(true)
    case "off": blSet(false)
    case "toggle": blSet(!blEnabled())
    case "status": break
    default: fail("usage: nightshift [on|off|toggle]")
    }
    print(blEnabled() ? "on" : "off")

case "lock":
    // `pmset displaysleepnow` was standing in for this and is not a lock
    // at all: it darkens the panel, and whether that ever locks depends
    // on the screenLock delay — 300s on the author's machine, so the
    // screen came back unlocked. SACLockScreenImmediate is what the
    // native Lock Screen menu item calls, and it ignores that delay.
    guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
        let sym = dlsym(h, "SACLockScreenImmediate")
    else { fail("lock: SACLockScreenImmediate unavailable") }
    typealias LockFn = @convention(c) () -> Int32
    let rc = unsafeBitCast(sym, to: LockFn.self)()
    if rc != 0 { fail("lock: SACLockScreenImmediate returned \(rc)") }

case "capslock":
    guard args.count > 2, args[2] == "off" else { fail("usage: capslock off") }
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    var conn: io_connect_t = 0
    guard IOServiceOpen(svc, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS
    else { fail("capslock: IOHIDSystem open failed") }
    guard IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), false) == KERN_SUCCESS
    else { fail("capslock: set failed") }
    IOServiceClose(conn)

case "brightness":
    let display = builtinDisplayID()
    if args.count > 3, args[2] == "set" {
        guard let pct = Int(args[3]), (0...100).contains(pct) else {
            fail("usage: brightness set <0-100>")
        }
        guard DSSetBrightness(display, Float(pct) / 100.0) == 0 else {
            fail("brightness: set failed (unsupported display?)")
        }
    }
    var level: Float = -1
    guard DSGetBrightness(display, &level) == 0, level >= 0 else {
        fail("brightness: unreadable (unsupported display?)")
    }
    print(Int((level * 100).rounded()))

case "omniwm-overview-close":
    // Swipe-down's half of the overview gesture. OmniWM rejects every
    // IPC command while its overview is open (ignored_overview), so no
    // gesture can close it through the socket — but the overview
    // listens for Escape. Post one, guarded on the overview actually
    // being on screen (an OmniWM-owned window tall enough to be the
    // panel, not the workspace bar), so a stray swipe-down can never
    // fire Escape into whatever app is focused.
    //
    // CGEventPost needs Accessibility, judged by the RESPONSIBLE
    // process: run from omacchiato-gesture's handler (which holds
    // the grant) this works; run from a bare shell it may not.
    guard let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    let overviewUp = wins.contains { w in
        (w[kCGWindowOwnerName as String] as? String) == "OmniWM"
            && ((w[kCGWindowBounds as String] as? [String: CGFloat])?["Height"] ?? 0) > 400
    }
    guard overviewUp else { exit(0) }
    // don't post Escape — synthetic key events depend on the caller's
    // Accessibility responsibility and OmniWM ignored them in testing.
    // The overview dismisses ITSELF when another app takes focus (its
    // own documented behavior), and activating an app needs no
    // permission: hand focus to the topmost normal window's app.
    for w in wins {
        guard (w[kCGWindowLayer as String] as? Int) == 0,
            let pid = w[kCGWindowOwnerPID as String] as? pid_t,
            let app = NSRunningApplication(processIdentifier: pid) else { continue }
        app.activate()
        break
    }

case "audio":
    let sub = args.count > 2 ? args[2] : "list"
    if sub == "list" {
        let current = defaultOutputDevice()
        for id in outputDevices() {
            print("\(id == current ? "*" : "-")\t\(deviceName(id))")
        }
    } else if sub == "set", args.count > 3 {
        guard let id = outputDevices().first(where: { deviceName($0) == args[3] }) else {
            fail("audio: no output device named '\(args[3])'")
        }
        var addr = audioProperty(kAudioHardwarePropertyDefaultOutputDevice)
        var dev = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &dev) == noErr else {
            fail("audio: failed to set default output")
        }
    } else {
        fail("usage: audio list | audio set <name>")
    }

case "bt":
    let sub = args.count > 2 ? args[2] : ""
    switch sub {
    case "power":
        if args.count > 3 {
            let want: Int32
            switch args[3] {
            case "on": want = 1
            case "off": want = 0
            case "toggle": want = BTGetPower() == 0 ? 1 : 0
            default: fail("usage: bt power [on|off|toggle]")
            }
            BTSetPower(want)
            // the preference call is async; give it a moment
            for _ in 0..<20 where BTGetPower() != want { usleep(100_000) }
        }
        print(BTGetPower())
    case "devices":
        // Coarse class-of-device keyword from the CoD major/minor
        // fields (Bluetooth Assigned Numbers). Only buckets the popup
        // can pick an icon for — everything else is "device".
        func kind(_ d: IOBluetoothDevice) -> String {
            switch d.deviceClassMajor {
            case 0x04: // audio/video
                switch d.deviceClassMinor {
                case 0x04: return "mic"
                case 0x05, 0x07, 0x08, 0x0A: return "speaker" // loudspeaker / portable / car / hifi
                default: return "headphones" // headset / hands-free / headphones
                }
            case 0x05: // peripheral: bits 4-5 of the minor field
                switch d.deviceClassMinor & 0x30 {
                case 0x10: return "keyboard"
                case 0x20: return "pointer"
                case 0x30: return "combo"
                default: return "device"
                }
            case 0x02: return "phone"
            case 0x07: return "watch"
            default: return "device"
            }
        }
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
            let name = d.name ?? "unknown"
            let addr = d.addressString ?? "?"
            print("\(d.isConnected() ? 1 : 0)\t\(addr)\t\(name)\t\(kind(d))")
        }
    case "battery":
        // percent per part, 0 where the device reports none
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where d.isConnected() {
            let b = unsafeBitCast(d, to: BatteryInfo.self)
            let parts = [b.batteryPercentSingle?(), b.batteryPercentLeft?(),
                         b.batteryPercentRight?(), b.batteryPercentCase?()]
            print(([d.addressString ?? "?"] + parts.map { String($0 ?? 0) }).joined(separator: "\t"))
        }
    case "connect", "disconnect":
        guard args.count > 3 else { fail("usage: bt \(sub) <address>") }
        guard let d = IOBluetoothDevice(addressString: args[3]) else { fail("bt: bad address") }
        let status = sub == "connect" ? d.openConnection() : d.closeConnection()
        exit(status == kIOReturnSuccess ? 0 : 1)
    default:
        fail("usage: bt power [on|off|toggle] | bt devices | bt battery | bt connect <addr> | bt disconnect <addr>")
    }

default:
    fail("usage: omacchiato-helper cursor | displays | wallpaper <path> | audio ... | bt ... | brightness [set <0-100>]")
}
