import SwiftUI

// What the stats popup shows: one metric (CPU, memory or disk), its share
// in use, the metric's own parts, and the processes using most of it. The
// bar decodes this from omacchiato-stats; the previews build it by hand.
public struct StatsReport {
    public enum Metric: String { case cpu, ram, disk }

    public struct Process: Identifiable {
        public var name: String
        public var value: Double     // a CPU share (1 = one core) for cpu, bytes for ram
        public var id: String { name }

        public init(name: String, value: Double) {
            self.name = name
            self.value = value
        }
    }

    public var metric: Metric
    public var percent: Double       // 0...1
    public var cores: Int            // cpu
    public var used: UInt64          // ram, disk
    public var total: UInt64         // ram, disk
    public var app: UInt64           // ram
    public var wired: UInt64         // ram
    public var compressed: UInt64    // ram
    public var free: UInt64          // disk
    public var top: [Process]        // cpu, ram
    public var settings: URL?        // disk

    public init(metric: Metric, percent: Double, cores: Int = 0, used: UInt64 = 0, total: UInt64 = 0,
                app: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, free: UInt64 = 0,
                top: [Process] = [], settings: URL? = nil) {
        self.metric = metric
        self.percent = percent
        self.cores = cores
        self.used = used
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.free = free
        self.top = top
        self.settings = settings
    }
}

public struct StatsActions {
    public var open: (URL) -> Void = { _ in }

    public init() {}
}

// The "panel" object that omacchiato-stats prints. Keep in sync with
// panel() in bin/omacchiato-stats.
extension StatsReport {
    public init?(json: [String: Any]) {
        guard json["kind"] as? String == "stats",
              let metric = (json["metric"] as? String).flatMap({ Metric(rawValue: $0) }) else { return nil }
        func num(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? 0 }
        self.metric = metric
        self.percent = num(json["percent"])
        self.cores = Int(num(json["cores"]))
        self.used = UInt64(max(0, num(json["used"])))
        self.total = UInt64(max(0, num(json["total"])))
        self.app = UInt64(max(0, num(json["app"])))
        self.wired = UInt64(max(0, num(json["wired"])))
        self.compressed = UInt64(max(0, num(json["compressed"])))
        self.free = UInt64(max(0, num(json["free"])))
        self.top = (json["top"] as? [[String: Any]] ?? []).map {
            Process(name: $0["name"] as? String ?? "", value: num($0["value"]))
        }
        self.settings = (json["settings"] as? String).flatMap(URL.init(string:))
    }
}
