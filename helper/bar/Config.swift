import AppKit
import Foundation

// --- live config: bar-pills.conf and bar-plugins.conf ------------------------

let liveConfigFiles = ["bar-pills.conf", "bar-plugins.conf"]
var configTexts = liveConfigFiles.map(confText)
var configCheck: DispatchWorkItem?

// An editor saves by a rename, which only the folder sees. A write in
// place, as `echo >>` does, only the file sees. So watch both.
func watchConfig() {
    // A global outside main.swift starts at its first read. Read it here, or
    // the first change becomes the baseline and does not reload.
    configTexts = liveConfigFiles.map(confText)
    watch(configDir.path, create: false, handler: scheduleConfigCheck)
    for name in liveConfigFiles {
        watch(configDir.appendingPathComponent(name).path, create: false, handler: scheduleConfigCheck)
    }
}

// The folder also holds the plugin caches and theme.conf, which change
// all the time, so compare the text of the two files, not the event.
func scheduleConfigCheck() {
    configCheck?.cancel()
    let check = DispatchWorkItem {
        let texts = liveConfigFiles.map(confText)
        guard texts != configTexts else { return }
        configTexts = texts
        reloadConfig()
    }
    configCheck = check
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: check)
}

func reloadConfig() {
    let t0 = DispatchTime.now().uptimeNanoseconds
    let oldPlugins = barPlugins, oldOrder = rightOrder
    pillModes = parseConf(configTexts[0])
    barPlugins = parsePlugins(configTexts[1])
    rightOrder = pillOrder(modes: pillModes, plugins: barPlugins)
    iconOnly = Set(pillModes.filter { $0.value == "icon" }.keys)

    let change = pluginChanges(old: oldPlugins, oldOrder: oldOrder, new: barPlugins, newOrder: rightOrder)
    // A plugin that restarts keeps its pill until its next run replaces it.
    let restarting = Set(change.start.map(\.name))
    change.stop.filter { !restarting.contains($0) }.forEach(stopPlugin)
    change.start.forEach(startPlugin)
    startProviders()
    // The volume pill has no timer, so a new `volume` mode applies here.
    updateVolume()
    // The jiggle interval and display sleep apply to a running keep awake.
    applyKeepAwake()

    // The popup of a pill that left the bar closes, built-in or plugin.
    if let open = openPopup, oldOrder.contains(open), !rightOrder.contains(open) { closePopup() } else { refreshPopup() }
    repaint()
    refreshSettings()
    tlog(String(format: "config reloaded: %d pills, stopped %d plugins, started %d, %.2f ms",
                rightOrder.count, change.stop.count, change.start.count,
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

// Writes a config file whole and at once, so the watcher reads a complete
// file. The watcher then reloads the bar.
func writeConfig(_ name: String, _ text: String) {
    do {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        // A dotfiles manager may link the file: write through the link, not over it.
        let file = configDir.appendingPathComponent(name).resolvingSymlinksInPath()
        try text.write(to: file, atomically: true, encoding: .utf8)
    } catch {
        tlog("config: could not write \(name): \(error.localizedDescription)")
    }
}
