import Foundation

// The clock pill's `clock_format` presets. Each preset has fixed patterns:
// a `dateFormat(fromTemplate:)` template puts the fields in the locale's
// order, which turned `iso` into `dd/MM/yyyy`.
public let clockPresets: [(key: String, h24: String, h12: String)] = [
    ("full", "EEE dd MMM  HH:mm", "EEE dd MMM  h:mm a"),
    ("short", "HH:mm", "h:mm a"),
    ("date", "EEE dd MMM", "EEE dd MMM"),
    ("iso", "yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a"),
]

// A format that is not a preset name is a custom pattern, which sets its own hours.
public func clockPattern(format: String?, hours: String?, systemIs24: Bool) -> String {
    let format = format.flatMap { $0.isEmpty ? nil : $0 } ?? "full"
    guard let preset = clockPresets.first(where: { $0.key == format }) else { return format }
    let is24 = hours == "24" || (hours != "12" && systemIs24)
    return is24 ? preset.h24 : preset.h12
}

// The `j` template gives the locale's hour field, and the 24-hour switch in
// System Settings reaches it through `.autoupdatingCurrent`.
public func systemUses24Hour(_ locale: Locale = .autoupdatingCurrent) -> Bool {
    !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "").contains("a")
}

// A quote starts or ends a literal, and `''` toggles twice, so it needs no case of its own.
public func clockShowsSeconds(_ pattern: String) -> Bool {
    var quoted = false
    for c in pattern {
        if c == "'" { quoted.toggle() } else if c == "s", !quoted { return true }
    }
    return false
}

// With 24-hour time on in System Settings, a formatter on the user's own
// locale turns `h:mm a` into `17:40`. A locale made from the identifier keeps
// the language and drops that override, so the pattern sets the hours.
public func makeClockFormatter(_ pattern: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: Locale.current.identifier)
    f.dateFormat = pattern
    return f
}

public func clockLabel(_ text: String) -> String { String(text.prefix(32)) }
