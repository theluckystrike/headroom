// The "how many more agents fit" math.

public enum Estimator {
    public static let minPerAgentBytes: UInt64 = 150 << 20
    public static let maxPerAgentBytes: UInt64 = 4 << 30

    /// Mean of agent treeBytes, clamped to [150 MiB, 4 GiB]; settings.defaultPerAgentBytes when no agents run.
    /// Mean, not median: agent trees are right-skewed (a long Claude Code session with MCP servers can be
    /// 5x a fresh one) and the total is what has to fit in RAM.
    public static func perAgentBytes(_ agents: [AgentInstance], settings: HeadroomSettings) -> UInt64 {
        if agents.isEmpty { return settings.defaultPerAgentBytes }
        // Each tree is capped at 1 TiB before summing so the total cannot overflow.
        let total = agents.reduce(UInt64(0)) { $0 + min($1.treeBytes, 1 << 40) }
        let mean = total / UInt64(agents.count)
        return min(max(mean, minPerAgentBytes), maxPerAgentBytes)
    }

    /// Reserve actually applied: doubled under warning pressure (the compressor is already working hard).
    public static func effectiveReserve(memory: MemoryState, settings: HeadroomSettings) -> UInt64 {
        memory.pressure == .warning ? settings.reserveBytes &* 2 : settings.reserveBytes
    }

    /// floor((available - reserve) / perAgent), min 0; 0 under critical pressure.
    public static func headroom(memory: MemoryState, perAgentBytes: UInt64, settings: HeadroomSettings) -> Int {
        if memory.pressure == .critical { return 0 }
        let reserve = effectiveReserve(memory: memory, settings: settings)
        guard memory.availableBytes > reserve else { return 0 }
        let n = (memory.availableBytes - reserve) / max(perAgentBytes, 1)
        return n > UInt64(Int.max) ? Int.max : Int(n)
    }

    public static func swapRatio(_ memory: MemoryState) -> Double {
        memory.swapTotalBytes > 0 ? Double(memory.swapUsedBytes) / Double(memory.swapTotalBytes) : 0
    }

    public static func level(headroom: Int, memory: MemoryState, settings: HeadroomSettings) -> HeadroomLevel {
        let swapFull = swapRatio(memory) >= settings.swapDangerRatio
        let diskLow = memory.diskFreeBytes > 0 && memory.diskFreeBytes < settings.lowDiskBytes
        if headroom <= 0 || memory.pressure == .critical || (swapFull && diskLow) { return .danger }
        if headroom <= 3 || memory.pressure == .warning || swapFull { return .tight }
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
