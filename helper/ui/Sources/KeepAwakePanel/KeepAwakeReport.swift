import Foundation

// What the keep-awake popup shows: everything holding a power assertion.
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

    public var holders: [Holder]

    public init(holders: [Holder] = []) {
        self.holders = holders
    }
}

public struct KeepAwakeActions {
    public var openSettings: () -> Void = {}

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
        self.init(holders: holders)
    }
}
