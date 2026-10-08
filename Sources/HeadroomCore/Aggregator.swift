// Folds the flat process list into one AgentInstance per running agent session.

public enum Aggregator {
    /// Finds agent roots, folds each descendant tree into one AgentInstance (an agent that is a
    /// descendant of another agent is a separate instance and is NOT double counted in its parent's tree).
    ///
    /// One refinement: a process classified as the SAME kind as its DIRECT parent is folded into the
    /// parent instead of becoming its own instance. That is the launcher pattern (`node .../@openai/codex/bin/codex.js`
    /// exec'ing the native `codex`, gemini-cli relaunching itself with a bigger heap), where one
    /// session would otherwise count twice. An agent started from another agent's shell tool has a
    /// shell in between, so it is still counted separately.
    ///
    /// Runs in O(n). Self-parenting, missing parents and ppid cycles (pid reuse between scans) are safe:
    /// every process is visited at most once.
    public static func agents(from procs: [ProcInfo]) -> [AgentInstance] {
        let n = procs.count
        if n == 0 { return [] }

        // pid -> index; on duplicate pids keep the first entry so the result is deterministic.
        var indexOf: [Int32: Int] = [:]
        indexOf.reserveCapacity(n)
        for (i, p) in procs.enumerated() where indexOf[p.pid] == nil {
            indexOf[p.pid] = i
        }

        let kinds = procs.map(AgentClassifier.classify)

        // parent index per process (nil when missing, self, or a duplicate-pid shadow).
        var parent = [Int?](repeating: nil, count: n)
        var children = [[Int]](repeating: [], count: n)
        for i in 0..<n {
            guard indexOf[procs[i].pid] == i else { continue } // duplicate pid: ignore entirely
            guard let pi = indexOf[procs[i].ppid], pi != i else { continue }
            parent[i] = pi
            children[pi].append(i)
        }

        // A classified process is folded into its parent when the parent is the same kind.
        func isFolded(_ i: Int) -> Bool {
            guard let k = kinds[i], let pi = parent[i] else { return false }
            return kinds[pi] == k
        }

        var visited = [Bool](repeating: false, count: n)
        var result: [AgentInstance] = []
        var stack: [Int] = []

        func collect(root: Int, kind: AgentKind) {
            var bytes: UInt64 = 0
            var count = 0
            visited[root] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(root)
            while let i = stack.popLast() {
                bytes &+= procs[i].footprintBytes
                count += 1
                for c in children[i] where !visited[c] {
                    // A nested agent of another kind (or behind a shell) is its own instance.
                    if let kc = kinds[c], kc != kinds[i] { continue }
                    visited[c] = true
                    stack.append(c)
                }
            }
            let p = procs[root]
            result.append(AgentInstance(kind: kind, pid: p.pid, tty: p.tty, treeBytes: bytes, processCount: count))
        }

        // Pass 1: ordinary roots.
        for i in 0..<n where indexOf[procs[i].pid] == i {
            if let k = kinds[i], !isFolded(i), !visited[i] { collect(root: i, kind: k) }
        }
        // Pass 2: same-kind cycles have no ordinary root; the first unvisited member becomes the root.
        for i in 0..<n where indexOf[procs[i].pid] == i {
            if let k = kinds[i], !visited[i] { collect(root: i, kind: k) }
        }

        result.sort { a, b in a.treeBytes != b.treeBytes ? a.treeBytes > b.treeBytes : a.pid < b.pid }
        return result
    }
}
