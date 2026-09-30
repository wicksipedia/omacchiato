import Testing
@testable import omacchiato_bar

@Suite struct QuitOnCloseTests {
    let none: Set<String> = []

    @Test("an app quits when its last standard window or dialog is gone")
    func lastWindow() {
        #expect(shouldQuit(windows: [], bundleID: "com.apple.TextEdit", exceptions: none, everShowedWindow: true))
        #expect(!shouldQuit(windows: ["AXStandardWindow"],
                            bundleID: "com.apple.TextEdit", exceptions: none, everShowedWindow: true))
        #expect(!shouldQuit(windows: ["AXDialog"],
                            bundleID: "com.apple.TextEdit", exceptions: none, everShowedWindow: true))
    }

    @Test("a desktop or floating panel does not count")
    func whatCounts() {
        #expect(shouldQuit(windows: ["AXFloatingWindow", "AXDesktop"], bundleID: "com.apple.TextEdit", exceptions: none, everShowedWindow: true))
    }

    @Test("never quit an exception, an app that never showed a window, Finder, Omacchiato or OmniWM")
    func neverQuit() {
        #expect(!shouldQuit(windows: [], bundleID: "com.apple.Music", exceptions: ["com.apple.Music"], everShowedWindow: true))
        #expect(!shouldQuit(windows: [], bundleID: "com.apple.TextEdit", exceptions: none, everShowedWindow: false))
        for id in ["com.apple.finder", "com.omacchiato.bar", "com.barut.OmniWM", "com.barut.OmniWM.dev", nil] {
            #expect(!shouldQuit(windows: [], bundleID: id, exceptions: none, everShowedWindow: true))
        }
    }

    @Test("the exceptions file holds one bundle ID per line, with # comments")
    func exceptionsFile() {
        #expect(parseExceptions("# keep\ncom.apple.Music\n\n  com.raycast.macos  # launcher\n")
                == ["com.apple.Music", "com.raycast.macos"])
    }

    @Test("a menu bar app, or an app with a menu bar icon, keeps working with no window, so it stays")
    func menuBarApps() {
        #expect(!shouldQuit(windows: [], bundleID: "com.raycast.macos", exceptions: none, everShowedWindow: true,
                            menuBarOnly: true))
        #expect(!shouldQuit(windows: [], bundleID: "dev.kdrag0n.MacVirt", exceptions: none, everShowedWindow: true,
                            hasMenuBarIcon: true))
    }
}
