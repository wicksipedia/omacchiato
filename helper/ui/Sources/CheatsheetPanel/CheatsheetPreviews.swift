import SwiftUI

enum CheatsheetSamples {
    static var entries: [CheatEntry] {
        [CheatEntry(group: "Workspaces", key: "Super+B", action: "workspace back and forth"),
         CheatEntry(group: "Focus", key: "Super+Left", action: "focus left"),
         CheatEntry(group: "Focus", key: "Super+Right", action: "focus right"),
         CheatEntry(group: "Focus", key: "Control+Option+[1-9]", action: "focus column"),
         CheatEntry(group: "Move", key: "Hyper+Left", action: "swap window left"),
         CheatEntry(group: "Move", key: "Control+Option+Shift+Page Up", action: "move column to workspace up"),
         CheatEntry(group: "Size", key: "Option+Period", action: "cycle size forward"),
         CheatEntry(group: "Apps", key: "Super+Enter", action: "terminal"),
         CheatEntry(group: "Apps", key: "Super+[1-9]", action: "workspace slot"),
         CheatEntry(group: "Apps", key: "Super+Shift+=", action: "taller"),
         CheatEntry(group: "Apps", key: "Control+Option+Tab", action: "focus next display")]
    }
}

#Preview("Cheatsheet") {
    CheatsheetView(model: CheatsheetModel(entries: CheatsheetSamples.entries))
        .padding(40)
}

#Preview("Search") {
    let model = CheatsheetModel(entries: CheatsheetSamples.entries)
    model.filter = "focus"
    return CheatsheetView(model: model).padding(40)
}
