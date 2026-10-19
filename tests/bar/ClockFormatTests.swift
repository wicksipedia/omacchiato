import Testing
import Foundation
@testable import BarPills

@Suite struct ClockFormatTests {
    @Test("each preset gives its 24-hour and 12-hour pattern")
    func presets() {
        let expected = [
            "full": ("EEE dd MMM  HH:mm", "EEE dd MMM  h:mm a"),
            "short": ("HH:mm", "h:mm a"),
            "date": ("EEE dd MMM", "EEE dd MMM"),
            "iso": ("yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a"),
        ]
        for (key, (h24, h12)) in expected {
            #expect(clockPattern(format: key, hours: "24", systemIs24: false) == h24)
            #expect(clockPattern(format: key, hours: "12", systemIs24: true) == h12)
        }
    }

    @Test("auto and a missing hours value follow the system")
    func autoHours() {
        #expect(clockPattern(format: "short", hours: "auto", systemIs24: true) == "HH:mm")
        #expect(clockPattern(format: "short", hours: nil, systemIs24: false) == "h:mm a")
    }

    @Test("a missing or empty format gives full")
    func defaultFormat() {
        #expect(clockPattern(format: nil, hours: "24", systemIs24: false) == "EEE dd MMM  HH:mm")
        #expect(clockPattern(format: "", hours: "24", systemIs24: false) == "EEE dd MMM  HH:mm")
    }

    @Test("a custom pattern comes back unchanged, whatever the hours say")
    func custom() {
        #expect(clockPattern(format: "HH:mm:ss", hours: "12", systemIs24: false) == "HH:mm:ss")
    }

    @Test("the system hour mode comes from the locale")
    func systemHours() {
        #expect(!systemUses24Hour(Locale(identifier: "en_US")))
        #expect(systemUses24Hour(Locale(identifier: "de_DE")))
    }

    @Test("seconds count only outside a quoted literal")
    func seconds() {
        #expect(clockShowsSeconds("HH:mm:ss"))
        #expect(clockShowsSeconds("H:mm:s"))
        #expect(!clockShowsSeconds("EEE dd MMM  HH:mm"))
        #expect(!clockShowsSeconds("HH:mm 'secs'"))
        #expect(clockShowsSeconds("HH 'o''clock' ss"))
        #expect(!clockShowsSeconds("h:mm a 'it''s'"))
    }

    @Test("a label is cut at 32 characters")
    func cap() {
        #expect(clockLabel(String(repeating: "x", count: 60)).count == 32)
        #expect(clockLabel("Mon 19 Oct  16:21") == "Mon 19 Oct  16:21")
    }
}
