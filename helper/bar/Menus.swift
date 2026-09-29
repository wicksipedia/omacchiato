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

// --- menu bar apps -------------------------------------------------------
// Third-party menu bar icons, read from each app's AXExtrasMenuBar. OmniWM's
// MenuBarExtrasScanner reads the same attribute on macOS 27.
struct MenuBarItem {
    let app: NSRunningApplication
    let element: AXUIElement
    let label: String
    let parked: Bool // the notch hides it: macOS parks such an icon at x = -1
}

// Call menuBarItems() off the main thread. A hung app can block an AX call
// for the default 6 s timeout. axTimeout lowers this to 0.25 s per call.
let axTimeout: Float = 0.25

func menuBarItems() -> [MenuBarItem] {
    let own = ProcessInfo.processInfo.processIdentifier
    var items: [MenuBarItem] = []
    for app in NSWorkspace.shared.runningApplications {
        guard app.processIdentifier != own,
              let id = app.bundleIdentifier, !id.hasPrefix("com.apple.") else { continue }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, axTimeout)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &ref) == .success,
              let extras = ref, CFGetTypeID(extras) == AXUIElementGetTypeID() else { continue }
        for element in axChildren(extras as! AXUIElement) {
            let title = axString(element, "AXTitle")
            items.append(MenuBarItem(app: app, element: element,
                                     label: title.isEmpty ? axString(element, "AXDescription") : title,
                                     parked: (axFrame(element)?.minX ?? -1) < 0))
        }
    }
    return items
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    var pos: CFTypeRef?, size: CFTypeRef?
    var origin = CGPoint.zero, extent = CGSize.zero
    // the cast to AXValue is unchecked, so check the type ID before it
    guard AXUIElementCopyAttributeValue(element, "AXPosition" as CFString, &pos) == .success,
          AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &size) == .success,
          let pos, let size,
          CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
          AXValueGetValue(pos as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
    return CGRect(origin: origin, size: extent)
}

// A point behind the notch is not clickable: the notch hides icons that
// don't fit, and a click there hits nothing.
func menuBarPointIsClickable(_ point: CGPoint) -> Bool {
    for screen in NSScreen.screens {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
        let bounds = CGDisplayBounds(id) // global, top-left origin, like AX
        guard bounds.contains(point), point.y - bounds.minY < 60 else { continue }
        let left = screen.auxiliaryTopLeftArea, right = screen.auxiliaryTopRightArea
        if left == nil && right == nil { return true } // no notch
        let x = point.x - bounds.minX + screen.frame.minX
        return [left, right].compactMap { $0 }.contains { x >= $0.minX && x <= $0.maxX }
    }
    return false
}

// macOS parks the hidden menu bar window just above its display (y = -39 on
// the main one) and slides it down to show it. True once it is fully in place
// over the given x.
func menuBarIsShown(overX x: CGFloat) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    for w in list where (w[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)) {
        guard let bounds = w[kCGWindowBounds as String],
              let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
              frame.minX <= x, x < frame.maxX else { continue }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: x, y: frame.maxY - 1), 1, &display, &count)
        if count > 0, abs(frame.minY - CGDisplayBounds(display).minY) < 1 { return true }
    }
    return false
}

// Clicks the icon the way OmniWM's HiddenBarClickForwarder does. Returns
// false without clicking if the icon has no clickable position. Call off
// the main thread: it waits for the menu bar to appear.
func clickMenuBarItem(_ item: MenuBarItem) -> Bool {
    guard let before = axFrame(item.element),
          let source = CGEventSource(stateID: .hidSystemState),
          let start = CGEvent(source: nil)?.location else { return false }
    func post(_ type: CGEventType, _ at: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left)
        if type != .mouseMoved { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
        event?.post(tap: .cghidEventTap)
    }
    defer { CGWarpMouseCursorPosition(start) }
    let t0 = DispatchTime.now().uptimeNanoseconds
    post(.mouseMoved, CGPoint(x: before.midX, y: 0))
    let deadline = t0 + 600_000_000
    while !menuBarIsShown(overX: before.midX), DispatchTime.now().uptimeNanoseconds < deadline {
        usleep(15_000)
    }
    tlog(String(format: "menubar click %@: menu bar ready after %.0f ms", item.app.localizedName ?? "?",
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
    guard let frame = axFrame(item.element) else { return false }
    let point = CGPoint(x: frame.midX, y: frame.midY)
    guard menuBarPointIsClickable(point) else { return false }
    post(.mouseMoved, point)
    usleep(10_000)
    post(.leftMouseDown, point)
    post(.leftMouseUp, point)
    usleep(50_000)
    return true
}

// The popup shows the last scan at once, and a new scan refreshes it.
var menuBarCache: [MenuBarItem]?
var menuBarScanning = false
var menuBarScannedAt = Date.distantPast

// The first line of an icon's label, without the app's name in front:
// "OneDrive — TinaCMS" becomes "TinaCMS".
func menuBarLabel(_ raw: String, app: String) -> String {
    var label = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    for sep in [" — ", " - ", ": "] where label.hasPrefix(app + sep) {
        label = String(label.dropFirst(app.count + sep.count))
    }
    return label.trimmingCharacters(in: .whitespaces)
}

// refreshPopup() calls panelView, which calls back in here, so a finished
// scan must not start another.
func scanMenuBar() {
    guard !menuBarScanning, Date().timeIntervalSince(menuBarScannedAt) > 2 else { return }
    menuBarScanning = true
    DispatchQueue.global(qos: .userInitiated).async {
        let items = menuBarItems()
        DispatchQueue.main.async {
            let keys = { (list: [MenuBarItem]) in list.map { "\($0.app.processIdentifier)|\($0.label)" } }
            let changed = menuBarCache.map(keys) != keys(items)
            menuBarCache = items
            menuBarScanning = false
            menuBarScannedAt = Date()
            if changed, openPopup == "menubar" { refreshPopup() }
        }
    }
}

func menuBarAppName(_ item: MenuBarItem) -> String {
    item.app.localizedName ?? item.app.bundleIdentifier ?? "?"
}

func menuBarReport() -> MenuBarReport {
    guard AXIsProcessTrusted() else { return MenuBarReport(items: nil, access: false) }
    scanMenuBar()
    guard let items = menuBarCache else { return MenuBarReport(items: nil) }
    return MenuBarReport(items: menuBarTitles(items.map { (menuBarAppName($0), $0.label) }).map { index, text in
        MenuBarReport.Item(id: index, title: text, app: menuBarAppName(items[index]),
                           icon: items[index].app.icon, hidden: items[index].parked)
    })
}

let menuBarActions: MenuBarActions = {
    var actions = MenuBarActions()
    actions.click = { index in
        guard let items = menuBarCache, items.indices.contains(index) else { return }
        let item = items[index]
        closePopup()
        // A real click, not AXPress: AXPress on an icon behind the notch
        // leaves the menu bar stuck on screen until that app quits. An
        // icon with no clickable position opens its app instead.
        DispatchQueue.global(qos: .userInitiated).async {
            guard item.parked || !clickMenuBarItem(item) else { return }
            tlog("menubar: \(menuBarAppName(item)) has no clickable icon, opening the app")
            DispatchQueue.main.async {
                guard let url = item.app.bundleURL else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
    actions.grantAccess = {
        closePopup()
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    return actions
}()

// MARK: - Activity popup

// The activity popup samples the system only while it is open. A scan of
// every process takes about 10 ms, so the samples run on their own queue.
let activityQueue = DispatchQueue(label: "com.omacchiato.bar.activity", qos: .utility)
let activityHost = mach_host_self()
let activityInterval = 1.5
var activityTimer: DispatchSourceTimer?
var activityGeneration = 0                  // a sample from an older opening is dropped
var activityLatest: ActivityReport?
var activitySampler = ActivitySampler()     // activityQueue only
var activityIcons: [String: NSImage] = [:]

// The kernel's name for the process it charges another process to. It is
// private, so the lookup gives up quietly on a macOS without it.
let responsibleFor: (@convention(c) (pid_t) -> pid_t)? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
    else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
}()

func readCPUTicks() -> [CPUTicks] {
    var count: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    guard host_processor_info(activityHost, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
          let info else { return [] }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                      vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
    }
    return (0..<Int(count)).map { core in
        func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[core * Int(CPU_STATE_MAX) + Int(state)])) }
        return CPUTicks(user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                        idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
    }
}

func readMemory() -> (used: UInt64, compressed: UInt64, swap: UInt64, pressure: ActivityReport.Pressure) {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(activityHost, HOST_VM_INFO64, $0, &count) }
    }
    let page = UInt64(vm_kernel_page_size)
    let used = result == KERN_SUCCESS
        ? memoryUsed(anonymous: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                     wired: UInt64(stats.wire_count), compressor: UInt64(stats.compressor_page_count), pageSize: page)
        : 0
    var swap = xsw_usage()
    var swapSize = MemoryLayout<xsw_usage>.size
    if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) != 0 { swap = xsw_usage() }
    var level: Int32 = 1
    var levelSize = MemoryLayout<Int32>.size
    _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)
    let pressure: ActivityReport.Pressure = level >= 4 ? .critical : (level >= 2 ? .warning : .normal)
    return (used, result == KERN_SUCCESS ? UInt64(stats.compressor_page_count) * page : 0, swap.xsu_used, pressure)
}

func readNetwork() -> [String: (rx: UInt32, tx: UInt32)] {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return [:] }
    defer { freeifaddrs(list) }
    var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let ifa = entry.pointee
        guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data else { continue }
        let name = String(cString: ifa.ifa_name)
        guard countsTraffic(name) else { continue }
        let link = data.assumingMemoryBound(to: if_data.self).pointee
        counters[name] = (link.ifi_ibytes, link.ifi_obytes)
    }
    return counters
}

final class ActivitySampler {
    var ticks: [CPUTicks] = []
    var processes: [ProcessSample] = []
    var network: [String: (rx: UInt32, tx: UInt32)] = [:]
    var sampledAt: TimeInterval?
    var history: [ActivityReport.Load] = []
    var networkHistory: [Double] = []
    var paths: [pid_t: (start: UInt64, path: String, responsible: String?)] = [:]
    var names: [String: String] = [:]
    let nanosPerTick: Double = {
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(max(1, timebase.denom))
    }()

    // proc_pid_rusage fails for processes of other users, such as
    // WindowServer. The total CPU load still counts them.
    func readProcesses() -> [ProcessSample] {
        let size = proc_listallpids(nil, 0)
        guard size > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(size) + 32)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        var samples: [ProcessSample] = []
        var live: [pid_t: (start: UInt64, path: String, responsible: String?)] = [:]
        var info = rusage_info_v4()
        for pid in pids.prefix(Int(max(0, found))) where pid > 0 {
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { continue }
            // a pid that macOS gives to a new process has a new start time
            var known = paths[pid]
            if known?.start != info.ri_proc_start_abstime {
                guard let path = processPath(pid) else { continue }
                var responsible: String?
                if appBundle(of: path) == nil, path.contains(".xpc/"), let owner = responsibleFor?(pid), owner != pid {
                    responsible = processPath(owner)
                }
                known = (info.ri_proc_start_abstime, path, responsible)
            }
            guard let known else { continue }
            live[pid] = known
            let ticks = Double(info.ri_user_time &+ info.ri_system_time)
            samples.append(ProcessSample(pid: pid, path: known.path, responsible: known.responsible,
                                         cpuTime: UInt64(ticks * nanosPerTick), memory: info.ri_phys_footprint))
        }
        paths = live
        return samples
    }

    func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    func name(_ key: String) -> String {
        if let name = names[key] { return name }
        let name = key.hasSuffix(".app") ? FileManager.default.displayName(atPath: key) : processName(key)
        let clean = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        names[key] = clean
        return clean
    }

    func sample() -> ActivityReport {
        let now = ProcessInfo.processInfo.systemUptime
        let newTicks = readCPUTicks()
        let newProcesses = readProcesses()
        let newNetwork = readNetwork()
        var load: ActivityReport.Load?
        var cores: [Double] = []
        var rows: [ActivityReport.Process] = []
        var rates: (down: Double, up: Double)?
        if let then = sampledAt {
            let seconds = now - then
            if let result = cpuLoad(from: ticks, to: newTicks) {
                load = result.load
                cores = result.cores
                history = appending(result.load, to: history, limit: activityHistoryLimit)
            }
            let cpu = processCPU(from: processes, to: newProcesses, seconds: seconds)
            rows = rankProcesses(newProcesses, cpu: cpu, limit: 10).map {
                ActivityReport.Process(id: $0.key, name: name($0.key), cpu: $0.cpu, memory: $0.memory, count: $0.count)
            }
            let rate = networkRate(from: network, to: newNetwork, seconds: seconds)
            rates = rate
            networkHistory = appending(rate.down + rate.up, to: networkHistory, limit: activityHistoryLimit)
        }
        ticks = newTicks
        processes = newProcesses
        network = newNetwork
        sampledAt = now
        let memory = readMemory()
        return ActivityReport(
            load: load, history: history, cores: cores,
            memoryUsed: memory.used, memoryTotal: ProcessInfo.processInfo.physicalMemory,
            compressed: memory.compressed, swapUsed: memory.swap, pressure: memory.pressure,
            download: rates?.down, upload: rates?.up, networkHistory: networkHistory, processes: rows,
            hot: ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue)
    }
}

// The first sample only sets a baseline. The second comes soon after, so
// the popup shows a load at once.
func startActivitySampling() {
    guard activityTimer == nil else { return }
    activityGeneration += 1
    let generation = activityGeneration
    let timer = DispatchSource.makeTimerSource(queue: activityQueue)
    timer.schedule(deadline: .now() + 0.5, repeating: activityInterval, leeway: .milliseconds(100))
    timer.setEventHandler {
        let report = activitySampler.sample()
        DispatchQueue.main.async {
            guard generation == activityGeneration else { return }
            activityLatest = report
            if openPopup == "activity" { refreshPopup() }
        }
    }
    activityQueue.async { _ = activitySampler.sample() }
    timer.resume()
    activityTimer = timer
}

func stopActivitySampling() {
    activityTimer?.cancel()
    activityTimer = nil
    activityGeneration += 1
    activityLatest = nil
    activityQueue.async { activitySampler = ActivitySampler() }
}

func activityReport() -> ActivityReport {
    startActivitySampling()
    var report = activityLatest ?? {
        let memory = readMemory()
        return ActivityReport(load: nil, memoryUsed: memory.used, memoryTotal: ProcessInfo.processInfo.physicalMemory,
                              compressed: memory.compressed, swapUsed: memory.swap, pressure: memory.pressure)
    }()
    for i in report.processes.indices where report.processes[i].id.hasSuffix(".app") {
        let key = report.processes[i].id
        if activityIcons[key] == nil { activityIcons[key] = NSWorkspace.shared.icon(forFile: key) }
        report.processes[i].icon = activityIcons[key]
    }
    return report
}

let activityActions: ActivityActions = {
    var actions = ActivityActions()
    actions.openActivityMonitor = {
        closePopup()
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    if FileManager.default.isExecutableFile(atPath: btopBin) {
        actions.openTerminalMonitor = {
            closePopup()
            DispatchQueue.global(qos: .userInitiated).async {
                _ = shell("/usr/bin/open", ["-na", terminalApp, "--args", "--title=omacchiato-activity", "--command=\(btopBin)"])
            }
        }
    }
    return actions
}()

// Sort by name: scan order is not stable across rescans. The offset
// tiebreak keeps one app's icons in menu-bar order. A duplicate name gets
// a suffix — its label, or a number when the label is empty.
func menuBarTitles(_ entries: [(name: String, label: String)]) -> [(index: Int, text: String)] {
    let perApp = Dictionary(grouping: entries, by: \.name).mapValues(\.count)
    var nth: [String: Int] = [:]
    return entries.enumerated().sorted { a, b in
        let order = a.element.name.localizedCaseInsensitiveCompare(b.element.name)
        return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
    }.map { index, entry in
        guard perApp[entry.name, default: 0] > 1 else { return (index, entry.name) }
        nth[entry.name, default: 0] += 1
        let label = menuBarLabel(entry.label, app: entry.name)
        return (index, entry.name + (label.isEmpty ? " \(nth[entry.name]!)" : " · " + label))
    }
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &ref) == .success,
          let children = ref as? [AXUIElement] else { return [] }
    // A timeout holds for one element only, so each child needs its own.
    for child in children { AXUIElementSetMessagingTimeout(child, axTimeout) }
    return children
}

private func axString(_ element: AXUIElement, _ attr: String) -> String {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return "" }
    return ref as? String ?? ""
}

private func axInt(_ element: AXUIElement, _ attr: String) -> Int {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return 0 }
    return (ref as? NSNumber)?.intValue ?? 0
}

// AXMenuItemCmdModifiers is a bit mask. Bit 3 means the shortcut has no
// command key. Without that check, Lock Screen and Log Out both read as ⌘Q.
func menuShortcut(_ item: AXUIElement) -> String {
    shortcutText(axString(item, "AXMenuItemCmdChar"), axInt(item, "AXMenuItemCmdModifiers"))
}

func shortcutText(_ key: String, _ mods: Int) -> String {
    guard !key.isEmpty else { return "" }
    var out = ""
    if mods & 4 != 0 { out += "⌃" }
    if mods & 2 != 0 { out += "⌥" }
    if mods & 1 != 0 { out += "⇧" }
    if mods & 8 == 0 { out += "⌘" }
    return out + key
}

// AX gives no icon for a Recent Items entry. Its title is an app or
// document name, and Launch Services can resolve that name to an icon.
// The section ("Applications", "Documents", or "Servers") picks the lookup.
func recentItemIcon(_ title: String, section: String) -> NSImage? {
    if section == "Applications" {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == title }),
           let icon = app.icon { return icon }
        // no current API finds an app by name, so look in the usual folders
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        if let path = dirs.map({ "\($0)/\(title).app" }).first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
    if section == "Documents" {
        let ext = (title as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
    return nil
}

// Builds one menu's rows, for both the app menu and the apple menu columns.
// AXEnabled is unreliable for a closed menu: apps validate items only when
// a menu opens, so closed menus often read as disabled (for example, Arc's
// whole Tabs menu). Render every leaf as enabled; AXPress on a truly
// disabled item just does nothing.
func rowsForMenu(_ element: AXUIElement, context: String = "", depth: Int,
                 collapseAlternates: Bool = false) -> [PopupRow] {
    let container = axChildren(element).first ?? element
    var rows: [PopupRow] = []
    var section = ""
    var prevTitle = ""
    let recents = context == "Recent Items"
    for item in axChildren(container) {
        let title = axString(item, "AXTitle")
        if title.isEmpty {
            if rows.last?.separator != true { rows.append(PopupRow(separator: true)) }
            prevTitle = ""
            continue
        }
        // The Apple menu holds hidden alternates (hold Option): "Restart…"
        // becomes "Restart", "Force Quit…" becomes "Force Quit Arc". AX
        // lists them flat; an alternate's title extends its predecessor's,
        // minus the ellipsis.
        if collapseAlternates, !prevTitle.isEmpty {
            let base = prevTitle.replacingOccurrences(of: "…", with: "")
            if title.hasPrefix(base) { continue }
        }
        prevTitle = title
        // Recent Items has its own hold-Option alternates ("Show X in
        // Finder"), a different shape than the root menu's. This match is
        // English-only; on another locale the alternates just reappear.
        if recents, title.hasPrefix("Show “"), title.hasSuffix("” in Finder") { continue }
        if recents, ["Applications", "Documents", "Servers"].contains(title) {
            section = title
            rows.append(PopupRow(text: title, dim: true))
            continue
        }
        if !axChildren(item).isEmpty {
            rows.append(submenuRow(title, item, depth: depth))
        } else {
            rows.append(PopupRow(image: recents ? recentItemIcon(title, section: section) : nil,
                                 text: title, detail: menuShortcut(item), action: {
                closePopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    AXUIElementPerformAction(item, "AXPress" as CFString)
                }
            }, hover: { openSubmenu(nil, depth: depth, after: 0.2) }))
        }
    }
    return rows
}

// the frontmost app's AX menu bar, resolved the popup-safe way
func frontAppAXMenuBar() -> AXUIElement? {
    guard !model.frontApp.isEmpty,
          let app = NSWorkspace.shared.runningApplications.first(where: {
              $0.localizedName == model.frontApp
                  && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
          })
    else { return nil }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, axTimeout)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(ax, "AXMenuBar" as CFString, &ref) == .success,
          let bar = ref, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    AXUIElementSetMessagingTimeout(bar as! AXUIElement, axTimeout)
    return (bar as! AXUIElement)
}

// The real Apple menu is child 0 of the front app's menu bar. appMenuRows
// skips it because the apple pill covers it. This function builds it with
// rowsForMenu, like the app menu, then appends omacchiato's own extras. It
// falls back to hand-rolled rows when Accessibility is off or AX returns
// nothing.
func appleMenuRows() -> [PopupRow] {
    guard AXIsProcessTrusted(),
          let menubar = frontAppAXMenuBar(),
          let apple = axChildren(menubar).first
    else { return appleRows() }
    var rows = rowsForMenu(apple, depth: 0, collapseAlternates: true)
    guard !rows.isEmpty else { return appleRows() }
    // "Log Out <full name>…" names the user, so demo mode drops the name.
    if demoMode {
        rows = rows.map { var row = $0; row.text = row.text.replacingOccurrences(of: " " + NSFullUserName(), with: ""); return row }
    }
    if rows.last?.separator != true { rows.append(PopupRow(separator: true)) }
    rows.append(PopupRow(text: "Omacchiato Settings…", dim: true, action: showSettings,
                         hover: { openSubmenu(nil, depth: 0, after: 0.2) }))
    return rows
}

// theme-set lives in the clone, next to the themes: follow its link there.
let themesDir = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/theme-set")
    .resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("themes")

func themeReport() -> ThemeReport {
    ThemeReport(directory: themesDir, spec: readConf("theme.conf")["theme"] ?? "",
                darkNow: app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
}

// theme-set writes theme.conf, so the choice outlives a restart. The
// settings window then reads the themes again, so Apply turns off.
let themeActions: ThemeActions = {
    var actions = ThemeActions()
    actions.apply = { light, dark in
        let spec = ThemeReport.spec(light: light, dark: dark)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell(NSHomeDirectory() + "/.local/bin/theme-set", [spec])
            DispatchQueue.main.async {
                settingsThemes = themeReport()
                refreshSettings()
            }
        }
    }
    return actions
}()

func appMenuRows() -> [PopupRow] {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(opts) else {
        return [PopupRow(text: "Grant Accessibility to omacchiato-bar", hero: true),
                PopupRow(text: "System Settings opened the pane — toggle the bar on,", dim: true),
                PopupRow(text: "Then click the app name again", dim: true)]
    }
    // Not NSWorkspace.frontmostApplication: the click that opens this
    // popup makes the bar itself frontmost for a moment, so that call
    // returns empty. model.frontApp tracks the real front app instead.
    guard let menubar = frontAppAXMenuBar() else {
        tlog("appmenu: no menu bar for '\(model.frontApp)'")
        return []
    }
    // No title row: the popup hangs from the pill that already shows the
    // app's name. Index 0 is the Apple menu, which the apple pill covers,
    // so this list skips it.
    var rows: [PopupRow] = []
    for item in axChildren(menubar).dropFirst() {
        let title = axString(item, "AXTitle")
        guard !title.isEmpty else { continue }
        rows.append(submenuRow(title, item, depth: 0))
    }
    return rows
}

// Opens a submenu at once on a click or →, or after a short hover delay.
// The delay lets a pointer cross other rows on its way into an open
// submenu without closing it.
func submenuRow(_ title: String, _ item: AXUIElement, depth: Int) -> PopupRow {
    PopupRow(icon: "›", text: title,
             action: { openSubmenu((title, item), depth: depth, after: 0) },
             hover: { openSubmenu((title, item), depth: depth, after: 0.2) })
}

var cascadeWork: DispatchWorkItem?

// Keep the submenus above `depth` open, and open `menu` after them.
func openSubmenu(_ menu: (title: String, element: AXUIElement)?, depth: Int, after delay: Double) {
    cascadeWork?.cancel()
    let work = DispatchWorkItem {
        let kept = Array(appMenuStack.prefix(depth))
        let next = kept + (menu.map { [$0] } ?? [])
        let same = next.count == appMenuStack.count
            && zip(next, appMenuStack).allSatisfy { CFEqual($0.element, $1.element) }
        guard !same else { return }
        appMenuStack = next
        popupSelection = nil
        refreshPopup()
        // → and a click select the first item of the new submenu, as macOS does
        if menu != nil, delay == 0 {
            popupSelection = popupShownRows.indices.first { popupShownRows[$0].action != nil }
            refreshPopup()
        }
    }
    cascadeWork = work
    if delay == 0 { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
}

// The columns of an open Apple menu or app menu: the menu, then each open submenu.
var popupColumns: [[PopupRow]] = []

func cascadePanel(_ name: String) -> AnyView? {
    var columns = [popupRows(for: name)]
    guard !columns[0].isEmpty else { return nil }
    for (i, level) in appMenuStack.enumerated() {
        columns.append(rowsForMenu(level.element, context: level.title, depth: i + 1))
    }
    popupColumns = columns
    popupShownRows = columns.last ?? []
    if let i = popupSelection, !popupShownRows.indices.contains(i) { popupSelection = nil }
    let open = columns.indices.map { i in
        i < appMenuStack.count ? columns[i].firstIndex { $0.icon == "›" && $0.text == appMenuStack[i].title } : nil
    }
    let limit = (NSScreen.main?.visibleFrame.height ?? 800) - 40
    return AnyView(CascadePanel(columns: columns.map { $0.map(panelRow) }, open: open,
                                selected: popupSelection, maxHeight: limit))
}

// The focused app's menu bar, read over Accessibility and shown in the
// popup. A click on an item runs its AXPress, so no native menu appears.
// The stack holds the open submenus, one column each.
var appMenuStack: [(title: String, element: AXUIElement)] = []
