import SwiftUI

// What the activity popup shows: CPU load and its last minute, memory in
// use, network rates, and the busiest processes. The bar samples this
// while the popup is open; the previews build it by hand.
public struct ActivityReport {
    public struct Load: Equatable {
        public var user: Double             // 0...1 of all cores
        public var system: Double

        public init(user: Double, system: Double) {
            self.user = user
            self.system = system
        }

        public var total: Double { min(1, user + system) }
    }

    public struct Process: Identifiable {
        public var id: String               // the app bundle, or the executable
        public var name: String
        public var icon: NSImage?
        public var cpu: Double              // 1 is one full core
        public var memory: UInt64           // bytes
        public var count: Int               // the processes that make up the row

        public init(id: String, name: String, icon: NSImage? = nil, cpu: Double, memory: UInt64, count: Int = 1) {
            self.id = id
            self.name = name
            self.icon = icon
            self.cpu = cpu
            self.memory = memory
            self.count = count
        }
    }

    public enum Pressure: Int {
        case normal, warning, critical
    }

    public var load: Load?                  // nil until two samples exist
    public var history: [Load]              // oldest first
    public var cores: [Double]              // the load of each core
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var compressed: UInt64
    public var swapUsed: UInt64
    public var pressure: Pressure
    public var download: Double?            // bytes a second
    public var upload: Double?
    public var networkHistory: [Double]     // download plus upload, oldest first
    public var processes: [Process]         // by CPU, most first
    public var hot: Bool                    // macOS slows the CPU to cool the Mac

    public init(load: Load?, history: [Load] = [], cores: [Double] = [],
                memoryUsed: UInt64, memoryTotal: UInt64, compressed: UInt64 = 0, swapUsed: UInt64 = 0,
                pressure: Pressure = .normal, download: Double? = nil, upload: Double? = nil,
                networkHistory: [Double] = [], processes: [Process] = [], hot: Bool = false) {
        self.load = load
        self.history = history
        self.cores = cores
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.compressed = compressed
        self.swapUsed = swapUsed
        self.pressure = pressure
        self.download = download
        self.upload = upload
        self.networkHistory = networkHistory
        self.processes = processes
        self.hot = hot
    }

    public var memoryShare: Double { memoryTotal == 0 ? 0 : min(1, Double(memoryUsed) / Double(memoryTotal)) }
}

public struct ActivityActions {
    public var openActivityMonitor: () -> Void = {}
    public var openTerminalMonitor: (() -> Void)?   // nil when btop is not installed
    public var quitOnClose: Bool?                    // nil draws no switch
    public var setQuitOnClose: (Bool) -> Void = { _ in }

    public init() {}
}

// MARK: - Sampling arithmetic

// The tick counters of one core, as host_processor_info reports them.
public struct CPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

// The load between two samples, for all cores and for each core. The
// counters are 32 bits wide in the kernel, so a delta wraps.
public func cpuLoad(from old: [CPUTicks], to new: [CPUTicks]) -> (load: ActivityReport.Load, cores: [Double])? {
    guard !old.isEmpty, old.count == new.count else { return nil }
    func delta(_ a: UInt64, _ b: UInt64) -> Double { Double(UInt32(truncatingIfNeeded: b &- a)) }
    var user = 0.0, system = 0.0, all = 0.0
    var cores: [Double] = []
    for (a, b) in zip(old, new) {
        let u = delta(a.user, b.user) + delta(a.nice, b.nice)
        let s = delta(a.system, b.system)
        let total = u + s + delta(a.idle, b.idle)
        user += u
        system += s
        all += total
        cores.append(total > 0 ? (u + s) / total : 0)
    }
    guard all > 0 else { return (ActivityReport.Load(user: 0, system: 0), cores) }
    return (ActivityReport.Load(user: user / all, system: system / all), cores)
}

// One process at one sample.
public struct ProcessSample {
    public var pid: Int32
    public var path: String
    public var responsible: String?         // the path of the process that macOS charges it to
    public var cpuTime: UInt64              // nanoseconds of CPU since launch
    public var memory: UInt64               // the physical footprint, in bytes

    public init(pid: Int32, path: String, responsible: String? = nil, cpuTime: UInt64, memory: UInt64) {
        self.pid = pid
        self.path = path
        self.responsible = responsible
        self.cpuTime = cpuTime
        self.memory = memory
    }
}

// The outermost app bundle on a path, so a helper app inside Chrome.app
// counts as Chrome.
public func appBundle(of path: String) -> String? {
    guard let range = path.range(of: ".app/") else { return path.hasSuffix(".app") ? path : nil }
    return String(path[..<path.index(before: range.upperBound)])
}

// The row a process counts in. An XPC service outside any app, such as
// the WebKit content process, counts in the app that macOS charges it to.
// A command that a terminal starts keeps a row of its own.
public func groupKey(_ sample: ProcessSample) -> String {
    if let app = appBundle(of: sample.path) { return app }
    if sample.path.contains(".xpc/"), let owner = sample.responsible.flatMap(appBundle(of:)) { return owner }
    return sample.path
}

// The CPU of each process between two samples, where 1 is one full core.
// A process that is new since the last sample has no share yet.
public func processCPU(from old: [ProcessSample], to new: [ProcessSample], seconds: Double) -> [Int32: Double] {
    guard seconds > 0 else { return [:] }
    let before = Dictionary(old.map { ($0.pid, $0.cpuTime) }, uniquingKeysWith: { a, _ in a })
    var shares: [Int32: Double] = [:]
    for sample in new {
        guard let then = before[sample.pid], sample.cpuTime >= then else { continue }
        shares[sample.pid] = Double(sample.cpuTime - then) / 1e9 / seconds
    }
    return shares
}

// The rows of the process list: one row for each app or command, with the
// CPU and the memory of all its processes, by CPU and then by memory.
public func rankProcesses(_ samples: [ProcessSample], cpu: [Int32: Double], limit: Int)
    -> [(key: String, cpu: Double, memory: UInt64, count: Int)] {
    var rows: [String: (cpu: Double, memory: UInt64, count: Int)] = [:]
    for sample in samples {
        let key = groupKey(sample)
        var row = rows[key] ?? (0, 0, 0)
        row.cpu += cpu[sample.pid] ?? 0
        row.memory += sample.memory
        row.count += 1
        rows[key] = row
    }
    return rows.map { (key: $0.key, cpu: $0.value.cpu, memory: $0.value.memory, count: $0.value.count) }
        .sorted { ($0.cpu, $0.memory, $1.key) > ($1.cpu, $1.memory, $0.key) }
        .prefix(limit)
        .map { $0 }
}

// The name of a row: the app without ".app", or the command.
public func processName(_ key: String) -> String {
    let last = (key as NSString).lastPathComponent
    return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
}

// The bytes that an interface counter moved. The counters are 32 bits wide
// and wrap.
public func counterDelta(_ old: UInt32, _ new: UInt32) -> UInt64 { UInt64(new &- old) }

// Wi-fi, Ethernet and cellular count. A VPN tunnel or a bridge carries
// the same bytes a second time.
public func countsTraffic(_ interface: String) -> Bool {
    interface.hasPrefix("en") || interface.hasPrefix("pdp_ip")
}

// The download and upload rates in bytes a second, from the received and
// sent counters of each interface. An interface that is new since the
// last sample has no rate yet.
public func networkRate(from old: [String: (rx: UInt32, tx: UInt32)], to new: [String: (rx: UInt32, tx: UInt32)],
                        seconds: Double) -> (down: Double, up: Double) {
    guard seconds > 0 else { return (0, 0) }
    var down: UInt64 = 0, up: UInt64 = 0
    for (name, now) in new {
        guard let then = old[name] else { continue }
        down += counterDelta(then.rx, now.rx)
        up += counterDelta(then.tx, now.tx)
    }
    return (Double(down) / seconds, Double(up) / seconds)
}

// Memory in use as Activity Monitor counts it: app memory, wired memory
// and the compressor. All values are pages.
public func memoryUsed(anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressor: UInt64,
                       pageSize: UInt64) -> UInt64 {
    ((anonymous > purgeable ? anonymous - purgeable : 0) + wired + compressor) * pageSize
}

// Keep the last `limit` values, oldest first.
public func appending<T>(_ value: T, to history: [T], limit: Int) -> [T] {
    Array((history + [value]).suffix(limit))
}

// MARK: - Text

// 11.24 GiB reads as 11.2 GB, as Activity Monitor writes it.
public func byteText(_ bytes: UInt64) -> String {
    let d = Double(bytes)
    let (kb, mb, gb): (Double, Double, Double) = (1024, 1024 * 1024, 1024 * 1024 * 1024)
    if d >= gb { return String(format: "%.1f GB", d / gb) }
    if d >= mb { return String(format: "%.0f MB", d / mb) }
    if d >= kb { return String(format: "%.0f KB", d / kb) }
    return "\(bytes) B"
}

public func rateText(_ bytesPerSecond: Double?) -> String {
    guard let rate = bytesPerSecond else { return "–" }
    let d = max(0, rate)
    if d >= 1e9 { return String(format: "%.1f GB/s", d / 1e9) }
    if d >= 1e6 { return String(format: "%.1f MB/s", d / 1e6) }
    if d >= 1e3 { return String(format: "%.0f KB/s", d / 1e3) }
    return String(format: "%.0f B/s", d)
}

// 0.234 reads as 23%. A process share uses the same text, so a process on
// two full cores reads 200%, as in Activity Monitor.
public func percentText(_ share: Double) -> String { "\(Int((max(0, share) * 100).rounded()))%" }
