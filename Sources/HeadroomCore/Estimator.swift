// The "how many more agents fit" math.

public enum Estimator {
    public static let minPerAgentBytes: UInt64 = 150 << 20
    public static let maxPerAgentBytes: UInt64 = 4 << 30

    /// Median of agent treeBytes, clamped to [150 MiB, 4 GiB]; settings.defaultPerAgentBytes when no agents run.
    public static func perAgentBytes(_ agents: [AgentInstance], settings: HeadroomSettings) -> UInt64 {
        if agents.isEmpty { return settings.defaultPerAgentBytes }
        let sorted = agents.map(\.treeBytes).sorted()
        let mid = sorted.count / 2
        let median: UInt64
        if sorted.count % 2 == 1 {
            median = sorted[mid]
        } else {
            let a = sorted[mid - 1], b = sorted[mid]
            median = a / 2 + b / 2 + (a % 2 + b % 2) / 2 // overflow-safe mean
        }
        return min(max(median, minPerAgentBytes), maxPerAgentBytes)
    }

    /// floor((available - reserve) / perAgent), min 0.
    public static func headroom(memory: MemoryState, perAgentBytes: UInt64, settings: HeadroomSettings) -> Int {
        guard memory.availableBytes > settings.reserveBytes else { return 0 }
        let spare = memory.availableBytes - settings.reserveBytes
        let n = spare / max(perAgentBytes, 1)
        return n > UInt64(Int.max) ? Int.max : Int(n)
    }

    public static func level(headroom: Int, memory: MemoryState, settings: HeadroomSettings) -> HeadroomLevel {
        if headroom <= 0 || memory.pressure == .critical { return .danger }
        if memory.swapTotalBytes > 0,
           Double(memory.swapUsedBytes) / Double(memory.swapTotalBytes) >= settings.swapDangerRatio {
            return .danger
        }
        if headroom <= 3 || memory.pressure == .warning { return .tight }
        return .ok
    }

    public static func snapshot(procs: [ProcInfo], memory: MemoryState, terminals: TerminalState,
                                settings: HeadroomSettings, now: Double) -> Snapshot {
        let agents = Aggregator.agents(from: procs)
        let per = perAgentBytes(agents, settings: settings)
        let fit = headroom(memory: memory, perAgentBytes: per, settings: settings)
        return Snapshot(takenAt: now, memory: memory, terminals: terminals, agents: agents,
                        perAgentBytes: per, headroomAgents: fit,
                        level: level(headroom: fit, memory: memory, settings: settings))
    }
}
