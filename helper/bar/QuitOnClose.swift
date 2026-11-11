import AppKit

// --- quit on close --------------------------------------------------------------
// When the last window of an app closes, the bar quits the app, except for
// the apps in quit-on-close.conf.

// Windows that OmniWM parks off screen on other workspaces are still in
// AXWindows, as AXStandardWindow. A minimized window keeps its subrole,
// so it counts. A settings window is often AXDialog.
let countedSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]

// Finder never quits for real, and the bar must not quit itself or the
// window manager.
let neverQuitPrefixes = ["com.apple.finder", "com.omacchiato.", "com.barut.OmniWM"]

// A menu bar app (LSUIElement) turns into a regular app while its settings
// window shows, and an app with a menu bar icon keeps working with no
// window, as OrbStack does. Neither quits.
func shouldQuit(windows: [String], bundleID: String?, exceptions: Set<String>,
                everShowedWindow: Bool, menuBarOnly: Bool = false, hasMenuBarIcon: Bool = false) -> Bool {
    guard let bundleID, everShowedWindow, !menuBarOnly, !hasMenuBarIcon, !exceptions.contains(bundleID),
          !neverQuitPrefixes.contains(where: { bundleID.hasPrefix($0) }) else { return false }
    return !windows.contains(where: countedSubroles.contains)
}

// One bundle ID per line. `#` starts a comment.
func parseExceptions(_ text: String) -> Set<String> {
    Set(text.split(separator: "\n").compactMap { line in
        let id = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return id.isEmpty ? nil : id
    })
}

let quitOnCloseFile = configDir.appendingPathComponent("quit-on-close.conf")

// An AXObserver per app with regular activation policy. A new window gets a
// destroyed notification of its own, because AX sends that one only to the
// element that goes away.
final class QuitWatch {
    var observers: [pid_t: AXObserver] = [:]
    var showedWindow: Set<pid_t> = []
    var pending: [pid_t: DispatchWorkItem] = [:]

    func start() {
        NSWorkspace.shared.runningApplications.forEach(add)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            // a new app can take a moment to answer AX
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.add(app) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.remove(app.processIdentifier)
        }
    }

    func add(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, !app.isTerminated, observers[pid] == nil, pid != getpid() else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, _ in
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            quitWatch.changed(pid, element, notification as String)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 0.25)
        AXObserverAddNotification(observer, ax, kAXWindowCreatedNotification as CFString, nil)
        let open = windows(ax)
        for window in open { watchWindow(observer, window) }
        if !open.isEmpty { showedWindow.insert(pid) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    func remove(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        showedWindow.remove(pid)
        pending.removeValue(forKey: pid)?.cancel()
    }

    func windows(_ ax: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    func subrole(_ window: AXUIElement) -> String {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value)
        return value as? String ?? ""
    }

    func watchWindow(_ observer: AXObserver, _ window: AXUIElement) {
        AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, nil)
    }

    func changed(_ pid: pid_t, _ element: AXUIElement, _ notification: String) {
        if notification == kAXWindowCreatedNotification, let observer = observers[pid] {
            showedWindow.insert(pid)
            watchWindow(observer, element)
            return
        }
        guard notification == kAXUIElementDestroyedNotification else { return }
        // An app can close one window and open the next, so look again after a second.
        pending[pid]?.cancel()
        let check = DispatchWorkItem { self.check(pid) }
        pending[pid] = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: check)
    }

    func check(_ pid: pid_t) {
        pending[pid] = nil
        guard pillModes["quit_on_close"] == "on",
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 0.25)
        let exceptions = parseExceptions((try? String(contentsOf: quitOnCloseFile, encoding: .utf8)) ?? "")
        let info = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary } ?? [:]
        // a plist flag can be a boolean, a number or a "1"
        func flag(_ key: String) -> Bool { (info[key] as? NSNumber)?.boolValue ?? ((info[key] as? String) == "1") }
        let menuBarOnly = flag("LSUIElement") || flag("LSBackgroundOnly")
        var extras: AnyObject?
        let hasMenuBarIcon = AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &extras) == .success
        guard shouldQuit(windows: windows(ax).map(subrole), bundleID: app.bundleIdentifier,
                         exceptions: exceptions, everShowedWindow: showedWindow.contains(pid),
                         menuBarOnly: menuBarOnly, hasMenuBarIcon: hasMenuBarIcon) else { return }
        tlog("quit on close: \(app.bundleIdentifier ?? "\(pid)")")
        // a normal quit, so an app with unsaved work still asks
        app.terminate()
    }
}

let quitWatch = QuitWatch()
