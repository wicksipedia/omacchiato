import Darwin
import Foundation

// --- debug ---------------------------------------------------------------------
// With `debug = on` in bar-pills.conf, the bar logs its memory once a
// minute to /tmp/omacchiato-bar.log. It reads the key at each tick, so
// the log starts and stops with no restart.

func memoryLine(footprint: UInt64, mallocInUse: UInt64) -> String {
    func mb(_ bytes: UInt64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    return "memory: footprint \(mb(footprint)), malloc \(mb(mallocInUse)) in use"
}

// The figure that Activity Monitor and `footprint` show as the app's memory.
func physFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

var memoryLog: Timer?

func startMemoryLog() {
    memoryLog = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
        guard pillModes["debug"] == "on" else { return }
        tlog(memoryLine(footprint: physFootprint(), mallocInUse: UInt64(mstats().bytes_used)))
    }
}
