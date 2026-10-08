#if os(macOS)
import Darwin
import HeadroomCore

/// Reads system memory state from sysctl and the mach host statistics.
public final class MemoryProbe {
    /// mach_host_self() returns a send right each call; take it once.
    private let host: host_t = mach_host_self()
    private lazy var totalBytes: UInt64 = MemoryProbe.sysctlInt("hw.memsize").map { UInt64($0) } ?? 0

    public init() {}

    public func read() -> MemoryState {
        let total = totalBytes
        let freePercent = MemoryProbe.sysctlInt("kern.memorystatus_level").map { Int(min(max($0, 0), 100)) } ?? 0
        let vm = vmStats()
        // Activity Monitor's model: used = app memory (anonymous minus purgeable) + wired + compressed.
        // available = total - used. memorystatus_level alone over-reports badly once the compressor is
        // large (measured: 45% "free" while the compressor held 13.8G of RAM and swap was 91% full).
        let available: UInt64
        if let vm = vm {
            let used = vm.appBytes + vm.wiredBytes + vm.compressedBytes
            available = total > used ? total - used : 0
        } else {
            available = total / 100 * UInt64(freePercent) + (total % 100) * UInt64(freePercent) / 100
        }

        let swap = MemoryProbe.swapUsage()
        let pressure: PressureLevel
        switch MemoryProbe.sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 1: pressure = .normal
        case 2: pressure = .warning
        case 4: pressure = .critical
        default: pressure = freePercent <= 15 ? .critical : (freePercent <= 30 ? .warning : .normal)
        }

        return MemoryState(totalBytes: total, availableBytes: available, freePercent: freePercent,
                           compressedBytes: vm?.compressedBytes ?? 0, swapUsedBytes: swap.used, swapTotalBytes: swap.total,
                           pressure: pressure, diskFreeBytes: MemoryProbe.diskFree())
    }

    private struct VM { var appBytes: UInt64; var wiredBytes: UInt64; var compressedBytes: UInt64 }

    private func vmStats() -> VM? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let anon = UInt64(stats.internal_page_count), purgeable = UInt64(stats.purgeable_count)
        return VM(appBytes: (anon > purgeable ? anon - purgeable : 0) * page,
                  wiredBytes: UInt64(stats.wire_count) * page,
                  compressedBytes: UInt64(stats.compressor_page_count) * page)
    }

    /// Free space on the volume that holds the swap files. Swap can only grow while this is not near zero.
    static func diskFree() -> UInt64 {
        for path in ["/System/Volumes/VM", "/"] {
            var fs = statfs()
            if statfs(path, &fs) == 0 { return UInt64(fs.f_bavail) * UInt64(fs.f_bsize) }
        }
        return 0
    }

    static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    /// Reads an integer sysctl of 4 or 8 bytes. nil when the name does not exist or is refused.
    static func sysctlInt(_ name: String) -> Int64? {
        var raw: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &raw, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4: return Int64(Int32(truncatingIfNeeded: UInt32(truncatingIfNeeded: raw)))
        case 8: return Int64(bitPattern: raw)
        default: return nil
        }
    }
}
#endif
