import AppKit
import CoreAudio
// swiftc builds helper/ui into this module, and SwiftPM builds it as its own.
import SwiftUI
#if canImport(StatusGauge)
import SoundPanel
import StatusPanel
#endif

// --- volume keys -----------------------------------------------------------
// The bar takes the volume keys, sets the volume itself and shows VolumeOSD,
// so the macOS HUD never shows. A key reaches the system as before when the
// output has no volume to set (an HDMI display, for example), or with Option
// alone, which opens Sound settings. `volume_hud = off` and
// `volume_click = off` in bar-pills.conf turn off the HUD and the click.

let NX_SYSDEFINED: UInt32 = 14
let NX_SUBTYPE_AUX_CONTROL_BUTTONS: Int16 = 8
enum VolumeKey: Int { case up = 0, down = 1, mute = 7 }

// The macOS HUD steps in sixteenths, and Shift+Option in quarters of that.
func nextVolume(_ percent: Int, up: Bool, fine: Bool) -> Int {
    let steps = fine ? 64.0 : 16.0
    let at = (Double(percent) / 100 * steps).rounded() + (up ? 1 : -1)
    return Int((min(steps, max(0, at)) / steps * 100).rounded())
}

func outputVolumeSettable() -> Bool {
    let dev = defaultOutputDevice()
    guard dev != 0 else { return false }
    for element in [kAudioObjectPropertyElementMain, 1] {
        var addr = volumeAddress(element)
        var settable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue { return true }
    }
    return false
}

func setMuted(_ on: Bool) {
    let dev = defaultOutputDevice()
    guard dev != 0 else { return }
    var value: UInt32 = on ? 1 : 0
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                          mScope: kAudioDevicePropertyScopeOutput,
                                          mElement: kAudioObjectPropertyElementMain)
    AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
}

func pressVolumeKey(_ key: VolumeKey, fine: Bool) {
    guard let now = readVolume() else { return }
    switch key {
    case .mute:
        toggleMute()
    case .up, .down:
        // as in macOS, a volume key ends a mute
        if now.muted { setMuted(false) }
        writeVolume(nextVolume(now.percent, up: key == .up, fine: fine))
    }
    updateVolume()
    if pillModes["volume_hud"] != "off" { showVolumeOSD() }
}

var volumeKeyTap: CFMachPort?

func startVolumeKeys() {
    guard volumeKeyTap == nil else { return }
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: CGEventMask(1) << CGEventMask(NX_SYSDEFINED),
        callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = volumeKeyTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type.rawValue == NX_SYSDEFINED, let ns = NSEvent(cgEvent: event),
                  ns.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS,
                  let key = VolumeKey(rawValue: (ns.data1 & 0xFFFF_0000) >> 16) else {
                return Unmanaged.passUnretained(event)
            }
            let mods = ns.modifierFlags.intersection([.shift, .option])
            guard mods != .option, outputVolumeSettable() else { return Unmanaged.passUnretained(event) }
            // 0xA is key down, 0xB key up. Take both, so the system sees neither.
            let down = (ns.data1 & 0xFF00) >> 8 == 0xA
            DispatchQueue.main.async {
                if down {
                    pressVolumeKey(key, fine: mods == [.shift, .option])
                } else if key != .mute {
                    // as in macOS, the click comes when the key goes up
                    playVolumeClick()
                }
            }
            return nil
        }, userInfo: nil)
    else {
        tlog("volume keys: no event tap, so no Accessibility grant")
        return
    }
    volumeKeyTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
}

var volumeOSDWindow: NSWindow?
var volumeOSDHide: DispatchWorkItem?

let volumeClick = NSSound(contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
                          byReference: true)

func playVolumeClick() {
    guard pillModes["volume_click"] != "off", let sound = volumeClick else { return }
    sound.stop()
    sound.play()
}

func showVolumeOSD() {
    guard let report = soundReport() else { return }
    showHUD(AnyView(VolumeOSD(report: report)))
}

// The HUDs share one window. It shows at the top right,
// under the bar of the screen with the pointer, where the macOS HUD shows.
func showHUD(_ view: AnyView) {
    let window: NSWindow
    if let shown = volumeOSDWindow {
        window = shown
        (window.contentView as? NSHostingView<AnyView>)?.rootView = view
    } else {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: view)
        window.alphaValue = 0
        volumeOSDWindow = window
    }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    if let frame = screen?.frame, let size = window.contentView?.fittingSize {
        window.setFrame(NSRect(x: frame.maxX - size.width - 10, y: frame.maxY - barHeight - 8 - size.height,
                               width: size.width, height: size.height), display: true)
    }
    window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = dur(0.12)
        window.animator().alphaValue = 1
    }
    volumeOSDHide?.cancel()
    let hide = DispatchWorkItem {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = dur(0.3)
            window.animator().alphaValue = 0
        }, completionHandler: {
            if window.alphaValue == 0 { window.orderOut(nil) }
        })
    }
    volumeOSDHide = hide
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: hide)
}
