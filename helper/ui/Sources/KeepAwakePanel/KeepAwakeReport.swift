import Foundation

// What the keep-awake popup shows: the bar's own keep awake, and every
// other process that holds a power assertion.
// The bar decodes this from omacchiato-keep-awake; the previews build it by hand.
public struct KeepAwakeReport {
    public struct Holder: Identifiable {
        public var name: String
        public var pid: Int32?
        public var duration: String
        public var id: String { name }

        public init(name: String, pid: Int32? = nil, duration: String) {
            self.name = name
            self.pid = pid
            self.duration = duration
        }
    }

    public var on: Bool
    public var until: Date?          // the end of a timed run
    public var holders: [Holder]

    public init(on: Bool = false, until: Date? = nil, holders: [Holder] = []) {
        self.on = on
        self.until = until
        self.holders = holders
    }
}

public struct KeepAwakeActions {
    public var openSettings: () -> Void = {}
    // Runs omacchiato-keep-awake with "on", "off" or "for <minutes>".
    public var set: (String) -> Void = { _ in }

    public init() {}
}

// The "panel" object that omacchiato-keep-awake prints. Keep in sync with
// panel_holder() in bin/omacchiato-keep-awake.
extension KeepAwakeReport {
    public init?(json: [String: Any]) {
        guard json["kind"] as? String == "keep-awake" else { return nil }
        let holders = (json["holders"] as? [[String: Any]] ?? []).map { h in
            Holder(name: h["name"] as? String ?? "",
                   pid: (h["pid"] as? Int).map(Int32.init),
                   duration: h["duration"] as? String ?? "")
        }
        self.init(on: json["on"] as? Bool ?? false,
                  until: (json["until"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
                  holders: holders)
    }
}
