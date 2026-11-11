import Testing
@testable import omacchiato_bar

struct CheatsheetCollapseTests {
    @Test("a numbered run folds into one row in place of its first entry")
    func foldsRun() {
        var entries = [CheatEntry(group: "K", key: "Super+Enter", action: "terminal")]
        for n in 1...9 {
            entries.append(CheatEntry(group: "K", key: "Super+\(n)", action: "workspace slot \(n)"))
            entries.append(CheatEntry(group: "K", key: "Super+Shift+\(n)", action: "move to slot \(n)"))
        }
        let out = collapseCheatEntries(entries)
        #expect(out.map(\.key) == ["Super+Enter", "Super+[1-9]", "Super+Shift+[1-9]"])
        #expect(out.map(\.action) == ["terminal", "workspace slot", "move to slot"])
    }

    @Test("a short run, a gap or a number the action does not repeat stays as it is")
    func keepsOthers() {
        let short = [CheatEntry(group: "S", key: "Super+1", action: "toggle scratchpad 1"),
                     CheatEntry(group: "S", key: "Super+2", action: "toggle scratchpad 2")]
        #expect(collapseCheatEntries(short).count == 2)
        let gap = [1, 2, 4].map { CheatEntry(group: "G", key: "Alt+\($0)", action: "go \($0)") }
        #expect(collapseCheatEntries(gap).count == 3)
        let other = (1...3).map { CheatEntry(group: "O", key: "Alt+\($0)", action: "focus") }
        #expect(collapseCheatEntries(other).count == 3)
    }

    @Test("a Karabiner chord names Super only when all three modifiers are held")
    func chords() {
        #expect(karabinerChord("tab", mods: ["command", "control", "option"]) == "Super+Tab")
        #expect(karabinerChord("tab", mods: ["control", "option", "shift"]) == "Control+Option+Shift+Tab")
        #expect(karabinerChord("equal_sign", mods: ["command", "control", "option", "shift"]) == "Super+Shift+=")
    }
}
