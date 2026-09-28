import ApplicationServices
import AppKit
import CoreAudio
import CoreBluetooth
import CoreLocation
import CoreWLAN
import EventKit
import IOBluetooth
import IOKit.ps
import SystemConfiguration
import UniformTypeIdentifiers
// swiftc builds helper/ui into this module, and SwiftPM builds it as its own.
import SwiftUI
#if canImport(StatusGauge)
import StatusGauge
import ActivityPanel
import BarPills
import AIUsagePanel
import CalendarPanel
import MenuBarPanel
import PRPanel
import RowsPanel
import StatusPanel
import ThemePanel
import WeatherPanel
#endif

// --- --request-permissions -------------------------------------------------
// A direct run asks for the terminal's own grants; run through
// omacchiato-permissions instead. This runs first, before the bar draws
// or subscribes to anything, so it can use only the globals declared
// above this line.

final class PermissionAnswer: NSObject, CBCentralManagerDelegate, CLLocationManagerDelegate {
    var answered = false
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if CBCentralManager.authorization != .notDetermined { answered = true }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { answered = true }
    }
    // The prompt stays open until the person answers it.
    func wait() {
        let deadline = Date().addingTimeInterval(120)
        while !answered, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    }
}

func requestPermissions() -> Never {
    func report(_ name: String, _ state: String) {
        print(name, state)
        fflush(stdout)
    }

    // AEDeterminePermissionToAutomateTarget blocks until the person answers
    for (name, bundleID) in [("automation-system-events", "com.apple.systemevents"),
                             ("automation-ghostty", "com.mitchellh.ghostty"),
                             ("automation-music", musicBundleID),
                             ("automation-calendar", "com.apple.iCal")] {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true) {
        case noErr: report(name, "granted")
        case OSStatus(errAEEventNotPermitted): report(name, "denied")
        default: report(name, "unknown") // procNotFound: the app is not running
        }
    }

    // Ask for Bluetooth even when its pill is hidden. A plugin command runs
    // as the bar's child and inherits the bar's Bluetooth grant, as the
    // AirPods pill does.
    let answer = PermissionAnswer()
    var central: CBCentralManager?
    if CBCentralManager.authorization == .notDetermined {
        central = CBCentralManager(delegate: answer, queue: .main)
        answer.wait()
    }
    _ = central
    switch CBCentralManager.authorization {
    case .allowedAlways: report("bluetooth", "granted")
    case .notDetermined: report("bluetooth", "unknown")
    default: report("bluetooth", "denied")
    }

    // The wi-fi rows and weather read location, so skip the grant when both pills are hidden.
    if pillModes["status"] != "hide" || (pillModes["wifi"] ?? "hide") != "hide"
        || pillModes["weather"] != "hide" {
        let answer = PermissionAnswer()
        let manager = CLLocationManager()
        manager.delegate = answer
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            answer.wait()
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized: report("location", "granted")
        case .notDetermined: report("location", "unknown")
        default: report("location", "denied")
        }
    }

    // The clock popup needs this to list what is left of today.
    if pillModes["clock"] != "hide" {
        let answer = PermissionAnswer()
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            EKEventStore().requestFullAccessToEvents { _, _ in answer.answered = true }
            answer.wait()
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: report("calendar", "granted")
        case .notDetermined: report("calendar", "unknown")
        default: report("calendar", "denied")
        }
    }

    // Ask last: this dialog does not block, so it stays open after the process exits.
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    report("accessibility", AXIsProcessTrustedWithOptions(prompt) ? "granted" : "denied")
    report("done", "")
    exit(0)
}
