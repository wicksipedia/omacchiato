import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
import ThemePanel
#endif

// The Omacchiato Settings window, laid out as System Settings: a sidebar
// of pages, and everything about one pill on its page. Unlike a popup,
// this window becomes key, so it uses the system controls.
public struct SettingsView: View {
    public enum Page: Hashable {
        case layout, theme, files, addPlugin
        case pill(String)
    }

    var report: SettingsReport
    var actions: SettingsActions
    @State private var page: Page?

    public init(report: SettingsReport, actions: SettingsActions = .init(), page: Page = .layout) {
        self.report = report
        self.actions = actions
        _page = State(initialValue: page)
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section("General") {
                    SettingsSidebarRow(title: "Theme", symbol: "paintpalette.fill", tint: "indigo").tag(Page.theme)
                    SettingsSidebarRow(title: "Layout", symbol: "rectangle.split.3x1", tint: "gray").tag(Page.layout)
                    SettingsSidebarRow(title: "Config Files", symbol: "doc.text", tint: "gray").tag(Page.files)
                }
                Section("Bar") { rows(.bar) }
                Section("Plugins") {
                    rows(.plugins)
                    SettingsSidebarRow(title: "Add Plugin", symbol: "plus", tint: "green").tag(Page.addPlugin)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch page {
            case .pill(let key)?:
                if let pill = report.pills.first(where: { $0.key == key }) {
                    SettingsPillPage(pill: pill, actions: actions,
                                     editFiles: { page = .files }, removed: { page = .layout })
                        .id(key)
                }
            case .theme?:
                ScrollView {
                    if let theme = report.theme {
                        ThemePicker(report: theme, actions: actions.theme).padding(20)
                    } else {
                        Text("No themes found").foregroundStyle(.secondary).padding(40)
                    }
                }
                .navigationTitle("Theme")
            case .files?:
                SettingsFilesPage(report: report, actions: actions)
            case .addPlugin?:
                SettingsAddPluginPage(taken: Set(report.pills.map(\.key)), actions: actions) { page = .pill($0) }
            default:
                SettingsLayoutPage(report: report, actions: actions)
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 460, idealHeight: 580)
    }

    func rows(_ group: SettingsReport.Pill.Group) -> some View {
        ForEach(report.pills.filter { $0.group == group }) { pill in
            SettingsSidebarRow(title: pill.title, symbol: pill.symbol, tint: pill.tint, dimmed: !pill.shown)
                .tag(Page.pill(pill.key))
        }
    }
}

// The coloured icon in a rounded square, as System Settings draws it.
struct SettingsIcon: View {
    var symbol: String
    var tint: String
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(settingsColor(tint).gradient, in: .rect(cornerRadius: size * 0.23))
    }
}

func settingsColor(_ name: String) -> Color {
    switch name {
    case "blue": return .blue
    case "green": return .green
    case "orange": return .orange
    case "pink": return .pink
    case "purple": return .purple
    case "red": return .red
    case "yellow": return .yellow
    case "teal": return .teal
    case "indigo": return .indigo
    default: return .gray
    }
}

struct SettingsSidebarRow: View {
    var title: String
    var symbol: String
    var tint: String
    var dimmed = false

    var body: some View {
        Label {
            Text(title).foregroundStyle(dimmed ? .secondary : .primary)
        } icon: {
            SettingsIcon(symbol: symbol, tint: tint, size: 20).opacity(dimmed ? 0.45 : 1)
        }
    }
}

struct SettingsPillPage: View {
    var pill: SettingsReport.Pill
    var actions: SettingsActions
    var editFiles: () -> Void
    var removed: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: pill.symbol, tint: pill.tint, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pill.title).font(.headline)
                        if !pill.summary.isEmpty {
                            Text(pill.summary).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                if pill.canHide {
                    Toggle("Show in bar", isOn: Binding(get: { pill.shown },
                                                        set: { actions.set(pill.key, pill.value(shown: $0)) }))
                }
            }
            if pill.shown, pill.styles.count > 1 {
                Section("Appearance") {
                    Picker("Style", selection: Binding(get: { pill.style }, set: { actions.set(pill.key, $0) })) {
                        ForEach(pill.shownStyles, id: \.self) { Text($0.title).tag($0.value) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            // The options work without the pill: the volume HUD shows with the pill hidden.
            if !pill.numbers.isEmpty || !pill.switches.isEmpty {
                Section("Options") {
                    ForEach(pill.numbers) { SettingsNumberRow(number: $0, actions: actions) }
                    ForEach(pill.switches) { s in
                        Toggle(s.title, isOn: Binding(get: { s.on }, set: { actions.set(s.key, $0 ? nil : s.off) }))
                    }
                }
            }
            if pill.shown {
                if let options = pill.aiUsage {
                    SettingsAIUsagePill(options: options) { actions.setPlugin(pill.key, "command", $0.command) }
                }
                if !pill.panelDesigns.isEmpty || pill.aiUsage != nil {
                    Section {
                        if let kind = pill.panelKind, actions.preview(kind, pill.panelValue) != nil {
                            SettingsDesignPicker(pill: pill, kind: kind, actions: actions)
                        } else if !pill.panelDesigns.isEmpty {
                            Picker("Design", selection: Binding(get: { pill.panelValue },
                                                                set: { actions.set(pill.key + "_panel", $0) })) {
                                ForEach(pill.shownPanelDesigns, id: \.self) { Text($0.title).tag($0.value) }
                            }
                        }
                        if let options = pill.aiUsage {
                            SettingsAIUsagePopup(options: options) { actions.setPlugin(pill.key, "command", $0.command) }
                        }
                    } header: {
                        Text("Popup")
                    } footer: {
                        Text("The popup that opens when you click the pill.")
                    }
                }
            }
            if let fields = pill.plugin {
                SettingsPluginSection(name: pill.key, fields: fields, hasOptions: pill.aiUsage != nil,
                                      actions: actions, editFiles: editFiles, removed: removed)
            }
        }
        .formStyle(.grouped)
        .animation(.snappy(duration: 0.2), value: pill.shown)
        .navigationTitle(pill.title)
    }
}

// The designs of a popup as thumbnails to pick from. Each is the real
// panel with the sample data of the Xcode previews, so no popup needs
// opening to compare them.
struct SettingsDesignPicker: View {
    var pill: SettingsReport.Pill
    var kind: String
    var actions: SettingsActions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
                ForEach(pill.shownPanelDesigns, id: \.self) { choice in
                    let on = choice.value == pill.panelValue
                    Button { actions.set(pill.key + "_panel", choice.value) } label: {
                        VStack(spacing: 6) {
                            thumbnail(actions.preview(kind, choice.value))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                                                  lineWidth: on ? 3 : 1))
                            Text(choice.title)
                                .font(.callout.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.title) design")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    func thumbnail(_ view: AnyView?) -> some View {
        SettingsThumbnail(view: view ?? AnyView(EmptyView()))
            .frame(width: 170, height: 230)
            .background(settingsDesktop)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

// The whole panel, scaled down to fit its box. Panels differ in height,
// so the scale comes from the panel's own size.
struct SettingsThumbnail: View {
    var view: AnyView
    @State private var size = CGSize.zero

    var body: some View {
        GeometryReader { box in
            let room = CGSize(width: box.size.width - 16, height: box.size.height - 16)
            let scale = size.width > 0 ? min(room.width / size.width, room.height / size.height, 1) : 0
            view.fixedSize()
                .allowsHitTesting(false)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .scaleEffect(scale)
                .frame(width: box.size.width, height: box.size.height)
        }
    }
}

let settingsDesktop = LinearGradient(colors: [.teal, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)

// Which providers the AI usage pill shows, and over which window: one
// menu for each provider, with Off first.
struct SettingsAIUsagePill: View {
    var options: AIUsageOptions
    var change: (AIUsageOptions) -> Void

    var body: some View {
        Section {
            ForEach(AIUsageOptions.providers, id: \.0) { id, title in
                let entry = options.pill.first { $0.id == id }
                Picker(title, selection: Binding(get: { entry?.window ?? "" }, set: { window in
                    var o = options
                    if window.isEmpty {
                        o.pill.removeAll { $0.id == id }
                    } else if let i = o.pill.firstIndex(where: { $0.id == id }) {
                        o.pill[i].window = window
                    } else {
                        let ids = AIUsageOptions.toggled(o.pill.map(\.id), id, true)
                        o.pill = ids.map { i in o.pill.first { $0.id == i } ?? .init(id: i, window: window) }
                    }
                    change(o)
                })) {
                    // The pill needs one provider, so the last one cannot turn off.
                    if !(entry != nil && options.pill.count == 1) { Text("Off").tag("") }
                    ForEach(AIUsageOptions.windows, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
            Toggle("Time to reset under the percent", isOn: Binding(get: { !options.inline }, set: { under in
                var o = options
                o.inline = !under
                change(o)
            }))
        } header: {
            Text("In the Pill")
        } footer: {
            Text("Each provider shows how much of its window you have used.")
        }
    }
}

// Which providers the AI usage popup lists, and which start open.
struct SettingsAIUsagePopup: View {
    var options: AIUsageOptions
    var change: (AIUsageOptions) -> Void

    var body: some View {
        ForEach(AIUsageOptions.providers, id: \.0) { id, title in
            let listed = options.panelIDs.contains(id)
            let state = !listed ? "hidden" : (options.openIDs.contains(id) ? "open" : "shown")
            Picker(title, selection: Binding(get: { state }, set: { new in
                var o = options
                o.panel = AIUsageOptions.toggled(o.panelIDs, id, new != "hidden")
                o.open = AIUsageOptions.toggled(o.openIDs, id, new == "open").filter { o.panelIDs.contains($0) }
                change(o)
            })) {
                // The popup needs one provider, so the last one cannot hide.
                if !(listed && options.panelIDs.count == 1) { Text("Hidden").tag("hidden") }
                Text("Shown").tag("shown")
                Text("Shown and open").tag("open")
            }
        }
    }
}

struct SettingsPluginSection: View {
    var name: String
    var fields: SettingsReport.PluginFields
    var hasOptions: Bool
    var actions: SettingsActions
    var editFiles: () -> Void
    var removed: () -> Void
    @State private var confirmRemove = false

    var body: some View {
        if fields.args == .search {
            Section {
                SettingsTextRow(title: "Search", value: fields.argument, prompt: "is:open author:@me") {
                    actions.setPlugin(name, "command", fields.with(argument: $0))
                }
            } header: {
                Text("Pull Requests")
            } footer: {
                Text("GitHub search qualifiers, added to author:@me.")
            }
        }
        if fields.args == .stats {
            Section("Stats") {
                Picker("Shows", selection: Binding(get: { fields.argument },
                                                   set: { actions.setPlugin(name, "command", fields.with(argument: $0)) })) {
                    Text("CPU").tag("cpu")
                    Text("Memory").tag("ram")
                    Text("Disk").tag("disk")
                    if !["cpu", "ram", "disk"].contains(fields.argument) { Text(fields.argument).tag(fields.argument) }
                }
            }
        }
        Section("Plugin") {
            SettingsTextRow(title: "Command", value: fields.command, font: .system(.body, design: .monospaced),
                            multiline: true) {
                actions.setPlugin(name, "command", $0)
            }
            Picker("Refresh every", selection: Binding(get: { fields.interval },
                                                       set: { actions.setPlugin(name, "interval", String($0)) })) {
                ForEach(SettingsReport.PluginFields.intervals, id: \.0) { Text($0.1).tag($0.0) }
                if !SettingsReport.PluginFields.intervals.contains(where: { $0.0 == fields.interval }) {
                    Text("\(fields.interval) seconds").tag(fields.interval)
                }
            }
            SettingsIconRow(fields: fields) { actions.setPlugin(name, "icon", $0) }
            Picker("Icon colour", selection: Binding(get: { fields.iconColor },
                                                     set: { actions.setPlugin(name, "icon_color", $0) })) {
                ForEach(SettingsReport.PluginFields.colors, id: \.0) { Text($0.1).tag($0.0) }
                if !SettingsReport.PluginFields.colors.contains(where: { $0.0 == fields.iconColor }) {
                    Text(fields.iconColor).tag(fields.iconColor)
                }
            }
            HStack {
                Button("Remove Plugin…", role: .destructive) { confirmRemove = true }
                    .foregroundStyle(.red)
                Spacer()
                Button("Edit in Config Files…", action: editFiles)
            }
        }
        .confirmationDialog("Remove the \(name) plugin?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                actions.removePlugin(name)
                removed()
            }
        } message: {
            Text("Its section in bar-plugins.conf is deleted, and its pill leaves the bar.")
        }
    }
}

// The pill's icon, drawn in the Nerd Font, and a grid to pick another.
// Automatic leaves the choice to the plugin.
struct SettingsIconRow: View {
    var fields: SettingsReport.PluginFields
    var change: (String) -> Void
    @State private var picking = false
    @State private var custom = ""

    var body: some View {
        let shown = fields.icon.isEmpty ? fields.shownIcon : fields.icon
        LabeledContent("Icon") {
            HStack(spacing: 10) {
                if !shown.isEmpty { SettingsGlyph(glyph: shown, size: 16) }
                Text(fields.icon.isEmpty ? "Automatic" : "Custom").foregroundStyle(.secondary)
                Button("Choose…") { picking = true }
                    .popover(isPresented: $picking, arrowEdge: .bottom) { picker }
            }
        }
    }

    var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                change("")
                picking = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").opacity(fields.icon.isEmpty ? 1 : 0)
                    Text("Automatic")
                }
            }
            .buttonStyle(.plain)
            Text("The plugin picks its icon.").font(.caption).foregroundStyle(.secondary)
            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 7), spacing: 4) {
                ForEach(SettingsReport.PluginFields.glyphs, id: \.0) { glyph, title in
                    Button {
                        change(glyph)
                        picking = false
                    } label: {
                        SettingsGlyph(glyph: glyph, size: 16)
                            .frame(width: 34, height: 30)
                            .background(fields.icon == glyph ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                                             : AnyShapeStyle(.fill.quaternary),
                                        in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(title)
                    .accessibilityLabel(title)
                }
            }
            Divider()
            HStack {
                TextField("Paste a glyph", text: $custom)
                    .font(.custom("JetBrainsMono Nerd Font", size: 14))
                    .frame(width: 140)
                Button("Use") {
                    change(custom.trimmingCharacters(in: .whitespaces))
                    picking = false
                }
                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }
}

// A Nerd Font glyph as an image of its ink. Text crops these glyphs,
// because they are wider than their advance.
struct SettingsGlyph: View {
    var glyph: String
    var size: CGFloat

    var body: some View {
        if let image = glyphImage(glyph, size: size) {
            Image(nsImage: image).renderingMode(.template)
        } else {
            Text(glyph).font(.custom("JetBrainsMono Nerd Font", size: size))
        }
    }
}

// A text field that saves on Return or when it loses focus, not on each key.
// The font applies to the field only, not to its title.
struct SettingsTextRow: View {
    var title: String
    var value: String
    var prompt = ""
    var font: Font = .body
    var multiline = false
    var commit: (String) -> Void
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: Binding(get: { draft ?? value }, set: { draft = $0 }), prompt: Text(prompt),
                      axis: multiline ? .vertical : .horizontal)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .lineLimit(multiline ? 1...4 : 1...1)
                .font(font)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { if !focused { save() } }
        }
    }

    func save() {
        if let draft, draft != value { commit(draft) }
        draft = nil
    }
}

struct SettingsAddPluginPage: View {
    var taken: Set<String>
    var actions: SettingsActions
    var added: (String) -> Void
    @State private var name = ""
    @State private var command = ""

    var body: some View {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let problem = key.isEmpty ? nil : (taken.contains(key) ? "A pill named \(key) exists." : nil)
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("github"))
                TextField("Command", text: $command, prompt: Text("omacchiato-github-prs"))
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
            } footer: {
                Text(problem ?? "The command prints a label, or JSON with a label, rows or a panel. It runs every 30 seconds until you change that.")
            }
            HStack {
                Spacer()
                Button("Add Plugin") {
                    actions.addPlugin(key, command.trimmingCharacters(in: .whitespaces))
                    added(key)
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.isEmpty || problem != nil || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Add Plugin")
    }
}

struct SettingsLayoutPage: View {
    var report: SettingsReport
    var actions: SettingsActions

    var body: some View {
        Form {
            Section {
                ForEach(report.numbers) { SettingsNumberRow(number: $0, actions: actions) }
            } footer: {
                Text("Changes apply at once and save to bar-pills.conf.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Layout")
    }
}

struct SettingsNumberRow: View {
    var number: SettingsReport.Number
    var actions: SettingsActions

    var body: some View {
        let value = number.value ?? number.fallback
        LabeledContent(number.title) {
            HStack(spacing: 6) {
                Text("\(value)").monospacedDigit()
                Stepper(number.title, value: Binding(get: { value }, set: {
                    actions.set(number.key, $0 == number.fallback ? nil : String($0))
                }), in: number.range)
                .labelsHidden()
            }
        }
    }
}

struct SettingsFilesPage: View {
    var report: SettingsReport
    var actions: SettingsActions
    @State private var selected = 0
    // Unsaved text by file name. No entry means the file as it is on disk.
    @State private var drafts: [String: String] = [:]

    var body: some View {
        let index = min(selected, max(0, report.files.count - 1))
        Group {
            if report.files.isEmpty {
                Text("No config files").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let file = report.files[index]
                let text = drafts[file.name] ?? file.text
                let dirty = text != file.text
                VStack(spacing: 10) {
                    Picker("File", selection: $selected) {
                        ForEach(report.files.indices, id: \.self) { Text(report.files[$0].name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    TextEditor(text: Binding(get: { text }, set: { drafts[file.name] = $0 }))
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.background, in: .rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    HStack {
                        Button("Reveal in Finder") { actions.reveal(file.url) }
                        Button("Open in Editor") { actions.open(file.url) }
                        Spacer()
                        if dirty { Text("Edited").font(.caption).foregroundStyle(.secondary) }
                        Button("Revert") { drafts[file.name] = nil }.disabled(!dirty)
                        Button("Save") {
                            actions.save(file.name, text)
                            drafts[file.name] = nil
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!dirty)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Config Files")
    }
}
