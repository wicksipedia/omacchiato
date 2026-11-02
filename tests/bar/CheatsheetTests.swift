import Foundation
import Testing
@testable import omacchiato_bar

struct CheatsheetTests {
    @Test("the sheet lists omacchiato's Karabiner keys and points to Defi's sheet")
    func entries() {
        let json = """
        {"profiles":[{"selected":true,"complex_modifications":{"rules":[
          {"description":"Caps Lock -> Super","manipulators":[{"from":{"key_code":"caps_lock"}}]},
          {"description":"omacchiato-keys: terminal","manipulators":[{"from":{"key_code":"return_or_enter",
            "modifiers":{"mandatory":["command","control","option"]}}}]},
          {"description":"omacchiato-keys: email","manipulators":[{"from":{"key_code":"e",
            "modifiers":{"mandatory":["command","control","option","shift"]}}}]}]}}]}
        """
        let e = cheatEntries(karabiner: Data(json.utf8))
        #expect(e.map(\.key) == ["Super+Enter", "Super+Shift+E", "Hold Ctrl+Opt"])
        #expect(e.map(\.action) == ["terminal", "email", "show Defi's window keys"])
    }
}
