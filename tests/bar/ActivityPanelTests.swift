import Foundation
import Testing
@testable import ActivityPanel
@testable import omacchiato_bar

@Suite struct ActivityPanelTests {
    func ticks(_ user: UInt64, _ system: UInt64, _ idle: UInt64, _ nice: UInt64 = 0) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test("the CPU load comes from the ticks between two samples")
    func load() throws {
        let old: [CPUTicks] = [ticks(100, 50, 850), ticks(0, 0, 1000)]
        // core 0: 60 user + 20 nice + 20 system of 200; core 1: idle
        let new: [CPUTicks] = [ticks(160, 70, 950, 20), ticks(0, 0, 1200)]
        let result = try #require(cpuLoad(from: old, to: new))
        #expect(result.cores == [0.5, 0])
        #expect(result.load.user == 0.2)
        #expect(result.load.system == 0.05)
        #expect(result.load.total == 0.25)
        #expect(cpuLoad(from: [], to: new) == nil)
        #expect(cpuLoad(from: old, to: [ticks(1, 1, 1)]) == nil)
        #expect(cpuLoad(from: old, to: old)?.load.total == 0)
    }

    @Test("a tick counter that wraps at 32 bits still gives the load")
    func wrap() throws {
        let old: [CPUTicks] = [ticks(UInt64(UInt32.max) - 9, 0, 0)]
        let new: [CPUTicks] = [ticks(10, 0, 20)]
        #expect(try #require(cpuLoad(from: old, to: new)).load.user == 0.5)
        #expect(counterDelta(UInt32.max - 4, 5) == 10)
    }

    @Test("a process share counts one full core as 1")
    func processShare() {
        let old = [ProcessSample(pid: 1, path: "/a", cpuTime: 1_000_000_000, memory: 0),
                   ProcessSample(pid: 2, path: "/b", cpuTime: 5_000_000_000, memory: 0)]
        let new = [ProcessSample(pid: 1, path: "/a", cpuTime: 4_000_000_000, memory: 0),
                   ProcessSample(pid: 2, path: "/b", cpuTime: 1_000, memory: 0),      // a new process on an old pid
                   ProcessSample(pid: 3, path: "/c", cpuTime: 9_000_000_000, memory: 0)]
        #expect(processCPU(from: old, to: new, seconds: 1.5) == [1: 2])
        #expect(processCPU(from: old, to: new, seconds: 0).isEmpty)
    }

    @Test("helpers count in their app, and a command in a terminal keeps its own row")
    func grouping() {
        #expect(appBundle(of: "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper")
                == "/Applications/Google Chrome.app")
        #expect(appBundle(of: "/Applications/Xcode.app") == "/Applications/Xcode.app")
        #expect(appBundle(of: "/usr/bin/swift-frontend") == nil)
        let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/"
            + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        #expect(groupKey(ProcessSample(pid: 1, path: webContent, responsible: "/Applications/Safari.app/Contents/MacOS/Safari",
                                       cpuTime: 0, memory: 0)) == "/Applications/Safari.app")
        #expect(groupKey(ProcessSample(pid: 2, path: "/opt/homebrew/bin/node",
                                       responsible: "/Applications/Ghostty.app/Contents/MacOS/ghostty",
                                       cpuTime: 0, memory: 0)) == "/opt/homebrew/bin/node")
        #expect(processName("/Applications/Safari.app") == "Safari")
        #expect(processName("/usr/libexec/trustd") == "trustd")
    }

    @Test("the list sums each app's processes and ranks by CPU, then memory")
    func ranking() {
        let samples = [ProcessSample(pid: 1, path: "/Applications/Safari.app/Contents/MacOS/Safari", cpuTime: 0, memory: 100),
                       ProcessSample(pid: 2, path: "/Applications/Safari.app/Contents/XPC/x.app/Contents/MacOS/x",
                                     cpuTime: 0, memory: 50),
                       ProcessSample(pid: 3, path: "/usr/bin/node", cpuTime: 0, memory: 10),
                       ProcessSample(pid: 4, path: "/usr/libexec/idle", cpuTime: 0, memory: 500),
                       ProcessSample(pid: 5, path: "/usr/libexec/tiny", cpuTime: 0, memory: 1)]
        let rows = rankProcesses(samples, cpu: [1: 0.1, 2: 0.3, 3: 0.5], limit: 3)
        #expect(rows.map(\.key) == ["/usr/bin/node", "/Applications/Safari.app", "/usr/libexec/idle"])
        #expect(rows[1].memory == 150 && rows[1].count == 2)
        #expect(abs(rows[1].cpu - 0.4) < 1e-9)
    }

    @Test("the network rate adds the physical interfaces")
    func network() {
        #expect(countsTraffic("en0") && countsTraffic("pdp_ip0"))
        #expect(!countsTraffic("lo0") && !countsTraffic("utun3") && !countsTraffic("bridge0"))
        let old: [String: (rx: UInt32, tx: UInt32)] = ["en0": (1_000, 500)]
        let new: [String: (rx: UInt32, tx: UInt32)] = ["en0": (4_000, 1_100), "en1": (9_999, 9_999)]
        let rate = networkRate(from: old, to: new, seconds: 2)
        #expect(rate.down == 1_500 && rate.up == 300)
    }

    @Test("memory counts app memory, wired memory and the compressor")
    func memory() {
        #expect(memoryUsed(anonymous: 100, purgeable: 20, wired: 30, compressor: 10, pageSize: 16_384) == 120 * 16_384)
        #expect(memoryUsed(anonymous: 5, purgeable: 20, wired: 0, compressor: 0, pageSize: 4_096) == 0)
    }

    @Test("the history keeps the newest samples")
    func history() {
        #expect(appending(4, to: [1, 2, 3], limit: 3) == [2, 3, 4])
        #expect(appending(1, to: [], limit: 3) == [1])
    }

    @Test("sizes and rates read as Activity Monitor writes them")
    func text() {
        #expect(byteText(11 * 1_073_741_824 + 268_435_456) == "11.2 GB")
        #expect(byteText(640 * 1_048_576) == "640 MB")
        #expect(byteText(512) == "512 B")
        #expect(rateText(1_234_567) == "1.2 MB/s")
        #expect(rateText(nil) == "–")
        #expect(percentText(3.984) == "398%")
    }

    @Test("two samples of this Mac give a load and a process list")
    func liveSample() {
        let sampler = ActivitySampler()
        let first = sampler.sample()
        #expect(first.load == nil && first.processes.isEmpty)
        Thread.sleep(forTimeInterval: 0.3)
        let second = sampler.sample()
        #expect(second.load.map { (0...1).contains($0.total) } == true)
        #expect(!second.cores.isEmpty)
        #expect(!second.processes.isEmpty)
        #expect(second.memoryTotal > 0 && second.memoryUsed > 0 && second.memoryUsed <= second.memoryTotal)
        #expect(second.history.count == 1)
    }
}
