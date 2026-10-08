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
        let available = total / 100 * UInt64(freePercent) + (total % 100) * UInt64(freePercent) / 100

        let swap = MemoryProbe.swapUsage()
        let pressure: PressureLevel
        switch MemoryProbe.sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 1: pressure = .normal
        case 2: pressure = .warning
        case 4: pressure = .critical
        default: pressure = freePercent <= 15 ? .critical : (freePercent <= 30 ? .warning : .normal)
        }

        return MemoryState(totalBytes: total, availableBytes: available, freePercent: freePercent,
                           compressedBytes: compressedBytes(), swapUsedBytes: swap.used, swapTotalBytes: swap.total,
                           pressure: pressure)
    }

    private func compressedBytes() -> UInt64 {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return UInt64(stats.compressor_page_count) * UInt64(vm_kernel_page_size)
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
