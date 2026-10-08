@testable import HeadroomCore

let MiB: UInt64 = 1 << 20
let GiB: UInt64 = 1 << 30

/// Builds a ProcInfo from a command line. `name` defaults to the basename of argv[0].
func proc(_ pid: Int32, _ ppid: Int32, _ args: [String], name: String? = nil, tty: String? = "ttys001",
          mb: UInt64 = 10) -> ProcInfo {
    let n = name ?? AgentClassifier.basename(args.first ?? "")
    return ProcInfo(pid: pid, ppid: ppid, tty: tty, name: n, args: args, footprintBytes: mb * MiB)
}

func kind(_ args: [String], name: String? = nil) -> AgentKind? {
    AgentClassifier.classify(proc(1, 0, args, name: name))
}

func memory(available: UInt64, total: UInt64 = 36 * GiB, swapUsed: UInt64 = 0, swapTotal: UInt64 = 8 * GiB,
            pressure: PressureLevel = .normal) -> MemoryState {
    MemoryState(totalBytes: total, availableBytes: available, freePercent: Int(available * 100 / total),
                compressedBytes: 0, swapUsedBytes: swapUsed, swapTotalBytes: swapTotal, pressure: pressure)
}

func agent(_ kind: AgentKind = .claude, pid: Int32 = 1, bytes: UInt64) -> AgentInstance {
    AgentInstance(kind: kind, pid: pid, tty: nil, treeBytes: bytes, processCount: 1)
}
