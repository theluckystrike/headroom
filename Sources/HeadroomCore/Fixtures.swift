// Deterministic demo data for `--demo` mode, previews and README screenshots.

public enum Fixtures {
    /// 12 agents of mixed kinds, 31 terminals, 36 GiB Mac with 14.2 GiB available: renders as
    /// "AG 12 | TTY 31 | 14.2G free | +9". The headroom and level are computed by the Estimator,
    /// so the fixture can never disagree with the real math.
    public static let demo: Snapshot = {
        let mib: UInt64 = 1 << 20
        let gib: UInt64 = 1 << 30
        let agents: [AgentInstance] = [
            AgentInstance(kind: .claude, pid: 48211, tty: "ttys004", treeBytes: 2310 * mib, processCount: 14),
            AgentInstance(kind: .claude, pid: 51877, tty: "ttys011", treeBytes: 1980 * mib, processCount: 11),
            AgentInstance(kind: .codex, pid: 50342, tty: "ttys007", treeBytes: 1720 * mib, processCount: 9),
            AgentInstance(kind: .claude, pid: 53019, tty: "ttys015", treeBytes: 1460 * mib, processCount: 8),
            AgentInstance(kind: .hermes, pid: 49920, tty: "ttys009", treeBytes: 1330 * mib, processCount: 7),
            AgentInstance(kind: .claude, pid: 54402, tty: "ttys018", treeBytes: 1200 * mib, processCount: 7),
            AgentInstance(kind: .gemini, pid: 55130, tty: "ttys021", treeBytes: 1150 * mib, processCount: 5),
            AgentInstance(kind: .codex, pid: 55761, tty: "ttys022", treeBytes: 980 * mib, processCount: 4),
            AgentInstance(kind: .claude, pid: 56088, tty: "ttys025", treeBytes: 760 * mib, processCount: 4),
            AgentInstance(kind: .hermes, pid: 56514, tty: "ttys026", treeBytes: 540 * mib, processCount: 3),
            AgentInstance(kind: .codex, pid: 57003, tty: "ttys028", treeBytes: 410 * mib, processCount: 2),
            AgentInstance(kind: .aider, pid: 57290, tty: "ttys030", treeBytes: 260 * mib, processCount: 1),
        ]
        let memory = MemoryState(
            totalBytes: 36 * gib,
            availableBytes: 14541 * mib, // 14.2 GiB
            freePercent: 39,
            compressedBytes: 3482 * mib,
            swapUsedBytes: 2150 * mib,
            swapTotalBytes: 8 * gib,
            pressure: .normal
        )
        let terminals = TerminalState(sessions: 31, byApp: ["Terminal": 9, "iTerm2": 14, "tmux": 8])
        let settings = HeadroomSettings()
        let per = Estimator.perAgentBytes(agents, settings: settings)
        let fit = Estimator.headroom(memory: memory, perAgentBytes: per, settings: settings)
        return Snapshot(takenAt: 1_791_460_800, memory: memory, terminals: terminals, agents: agents,
                        perAgentBytes: per, headroomAgents: fit,
                        level: Estimator.level(headroom: fit, memory: memory, settings: settings))
    }()
}
