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

func shouldQuit(windows: [String], bundleID: String?, exceptions: Set<String>,
                everShowedWindow: Bool) -> Bool {
    guard let bundleID, everShowedWindow, !exceptions.contains(bundleID),
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
