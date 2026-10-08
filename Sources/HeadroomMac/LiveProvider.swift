#if os(macOS)
import Darwin
import HeadroomCore

/// Live snapshots of this Mac: one process scan feeds both agent and terminal counts.
///
/// Not thread safe: call `snapshot()` from one thread at a time (the probes reuse buffers).
public final class LiveProvider {
    public var settings: HeadroomSettings

    private let processes = ProcessProbe()
    private let memory = MemoryProbe()

    public init(settings: HeadroomSettings) {
        self.settings = settings
    }

    /// Full scan. Target cost < 25 ms and < 1% CPU when called every 2 s.
    public func snapshot() -> Snapshot {
        let scan = processes.scan()
        let mem = memory.read()
        let terminals = TerminalProbe.state(procs: scan.procs, paths: scan.paths)
        var now = timeval()
        gettimeofday(&now, nil)
        let seconds = Double(now.tv_sec) + Double(now.tv_usec) / 1_000_000
        return Estimator.snapshot(procs: scan.procs, memory: mem, terminals: terminals, settings: settings, now: seconds)
    }
}
#endif
