// Shared data model. This file is the contract between the probes (HeadroomMac),
// the pure logic (HeadroomCore) and the UI (Headroom). Change it only with care.

/// One process as seen by the probe.
public struct ProcInfo: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    /// Controlling terminal device name, e.g. "ttys011"; nil when the process has none.
    public var tty: String?
    /// Basename of the executable, e.g. "claude", "codex", "Python".
    public var name: String
    /// Full argv (argv[0] first). May be empty when the kernel refuses (other users' processes).
    public var args: [String]
    /// Physical footprint in bytes (what Activity Monitor shows as "Memory"); RSS as fallback.
    public var footprintBytes: UInt64

    public init(pid: Int32, ppid: Int32, tty: String?, name: String, args: [String], footprintBytes: UInt64) {
        self.pid = pid; self.ppid = ppid; self.tty = tty; self.name = name; self.args = args; self.footprintBytes = footprintBytes
    }
}

public enum AgentKind: String, CaseIterable, Codable, Sendable {
    case claude, codex, gemini, hermes, aider, opencode, goose, cursor, amp, copilot, droid, crush, qwen
    public var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .hermes: return "Hermes"
        case .aider: return "Aider"
        case .opencode: return "opencode"
        case .goose: return "Goose"
        case .cursor: return "Cursor Agent"
        case .amp: return "Amp"
        case .copilot: return "Copilot CLI"
        case .droid: return "Droid"
        case .crush: return "Crush"
        case .qwen: return "Qwen Code"
        }
    }
}

/// One running agent session: the agent's root process plus every descendant
/// (MCP servers, language servers, shells it spawned).
public struct AgentInstance: Equatable, Codable, Sendable {
    public var kind: AgentKind
    public var pid: Int32
    public var tty: String?
    /// Sum of physical footprint over the agent process and all its descendants.
    public var treeBytes: UInt64
    /// Number of processes in the tree.
    public var processCount: Int
    public init(kind: AgentKind, pid: Int32, tty: String?, treeBytes: UInt64, processCount: Int) {
        self.kind = kind; self.pid = pid; self.tty = tty; self.treeBytes = treeBytes; self.processCount = processCount
    }
}

public enum PressureLevel: String, Codable, Sendable { case normal, warning, critical }

public struct MemoryState: Equatable, Codable, Sendable {
    public var totalBytes: UInt64
    /// Memory the system can hand out without swapping hard:
    /// totalBytes * memorystatus_level / 100 (same number `memory_pressure` prints).
    public var availableBytes: UInt64
    /// kern.memorystatus_level, 0...100.
    public var freePercent: Int
    public var compressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressure: PressureLevel
    public init(totalBytes: UInt64, availableBytes: UInt64, freePercent: Int, compressedBytes: UInt64,
                swapUsedBytes: UInt64, swapTotalBytes: UInt64, pressure: PressureLevel) {
        self.totalBytes = totalBytes; self.availableBytes = availableBytes; self.freePercent = freePercent
        self.compressedBytes = compressedBytes; self.swapUsedBytes = swapUsedBytes; self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
    }
}

public struct TerminalState: Equatable, Codable, Sendable {
    /// Distinct ttys that have at least one process: one per terminal tab, split pane or tmux pane.
    public var sessions: Int
    /// Sessions grouped by host app ("Terminal", "iTerm2", "Ghostty", "tmux", "VS Code", ...).
    public var byApp: [String: Int]
    public init(sessions: Int, byApp: [String: Int]) { self.sessions = sessions; self.byApp = byApp }
}

public enum HeadroomLevel: String, Codable, Sendable {
    /// 4 or more agents fit.
    case ok
    /// 1 to 3 agents fit.
    case tight
    /// 0 fit, or the system is already under critical pressure / swap nearly full.
    case danger
}

public struct Snapshot: Equatable, Codable, Sendable {
    public var takenAt: Double // seconds since 1970
    public var memory: MemoryState
    public var terminals: TerminalState
    public var agents: [AgentInstance]
    /// Bytes one more agent is expected to cost (median of running agent trees, or the default).
    public var perAgentBytes: UInt64
    /// How many more agents fit before the reserve is hit. Never negative.
    public var headroomAgents: Int
    public var level: HeadroomLevel
    public init(takenAt: Double, memory: MemoryState, terminals: TerminalState, agents: [AgentInstance],
                perAgentBytes: UInt64, headroomAgents: Int, level: HeadroomLevel) {
        self.takenAt = takenAt; self.memory = memory; self.terminals = terminals; self.agents = agents
        self.perAgentBytes = perAgentBytes; self.headroomAgents = headroomAgents; self.level = level
    }
}

/// User settings that change the math.
public struct HeadroomSettings: Equatable, Codable, Sendable {
    /// Memory kept free for the OS, browser tabs, and bursts. Default 3 GiB.
    public var reserveBytes: UInt64 = 3 << 30
    /// Cost per agent when none are running to measure. Default 600 MiB.
    public var defaultPerAgentBytes: UInt64 = 600 << 20
    /// Swap used / total above which the level is forced to danger. Default 0.85.
    public var swapDangerRatio: Double = 0.85
    public init() {}
}
