import Foundation
import Testing
@testable import omacchiato_bar

@Suite struct KeepAwakeTests {
    let now = Date(timeIntervalSince1970: 100)

    @Test("the state file reads as off, on, or on until an end time, as the script reads it")
    func state() {
        #expect(keepAwakeNow(state: "", now: now) == .off)
        #expect(keepAwakeNow(state: "off\n", now: now) == .off)
        #expect(keepAwakeNow(state: "on\n", now: now) == .on(until: nil))
        #expect(keepAwakeNow(state: "400\n", now: now) == .on(until: Date(timeIntervalSince1970: 400)))
        #expect(keepAwakeNow(state: "junk", now: now) == .off)
    }

    @Test("an end time in the past reads as off")
    func expired() {
        #expect(keepAwakeNow(state: "99", now: now) == .off)
    }
}
