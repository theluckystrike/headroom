# Who owns which files (parallel build)

Five sessions build Headroom in parallel. Each one edits ONLY its own paths and pushes ONLY its own branch.
`Sources/HeadroomCore/Model.swift` is the shared contract: read it, never edit it. If you need a field
that is missing, add it as an extension in your own files or note it in your NOTES file.

| Session | Branch | Owns |
|---|---|---|
| core | cloud/core | Sources/HeadroomCore/* (except Model.swift), Tests/HeadroomCoreTests/*, NOTES-core.md |
| probes | cloud/probes | Sources/HeadroomMac/*, Sources/headroom-cli/*, NOTES-probes.md |
| app | cloud/app | Sources/Headroom/*, NOTES-app.md |
| site | cloud/site | README.md, docs/*, LICENSE, NOTES-site.md |
| ship | cloud/ship | Makefile, scripts/*, .github/*, Resources/*, install.sh, NOTES-ship.md |

Core API every other session codes against (the core session implements exactly these signatures):

```swift
// HeadroomCore
public enum AgentClassifier {
    /// Returns the agent kind when `p` is the ROOT process of an interactive or headless agent session.
    /// Helper processes (codex-code-mode-host, app-server daemons, MCP servers, chrome-native-host) return nil.
    public static func classify(_ p: ProcInfo) -> AgentKind?
}
public enum Aggregator {
    /// Finds agent roots, folds each descendant tree into one AgentInstance (an agent that is a
    /// descendant of another agent is a separate instance and is NOT double counted in its parent's tree).
    public static func agents(from procs: [ProcInfo]) -> [AgentInstance]
}
public enum Estimator {
    /// Median of agent treeBytes, clamped to [150 MiB, 4 GiB]; settings.defaultPerAgentBytes when no agents run.
    public static func perAgentBytes(_ agents: [AgentInstance], settings: HeadroomSettings) -> UInt64
    /// floor((available - reserve) / perAgent), min 0.
    public static func headroom(memory: MemoryState, perAgentBytes: UInt64, settings: HeadroomSettings) -> Int
    public static func level(headroom: Int, memory: MemoryState, settings: HeadroomSettings) -> HeadroomLevel
    public static func snapshot(procs: [ProcInfo], memory: MemoryState, terminals: TerminalState,
                                settings: HeadroomSettings, now: Double) -> Snapshot
}
public enum Format {
    public static func bytes(_ b: UInt64) -> String          // "14.2G", "812M"
    public static func line(_ s: Snapshot) -> String           // "AG 12 | TTY 31 | 14.2G free | +9"
    public static func json(_ s: Snapshot) -> String           // pretty JSON, sorted keys
}

// HeadroomMac
public final class LiveProvider {
    public init(settings: HeadroomSettings)
    public var settings: HeadroomSettings
    /// Full scan. Target cost < 25 ms and < 1% CPU when called every 2 s.
    public func snapshot() -> Snapshot
}
```
