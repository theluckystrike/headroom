import Foundation
import XCTest
@testable import HeadroomCore

final class AggregatorTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(Aggregator.agents(from: []), [])
    }

    func testNoAgents() {
        let procs = [proc(1, 0, ["launchd"]), proc(100, 1, ["zsh"]), proc(101, 100, ["vim"])]
        XCTAssertEqual(Aggregator.agents(from: procs), [])
    }

    func testTreeSumsDescendants() {
        let procs = [
            proc(1, 0, ["launchd"], tty: nil, mb: 30),
            proc(100, 1, ["login"], mb: 2),
            proc(101, 100, ["-zsh"], name: "zsh", mb: 3),
            proc(200, 101, ["claude"], tty: "ttys004", mb: 300),
            proc(201, 200, ["node", "/x/mcp-server-github/index.js"], mb: 60),
            proc(202, 200, ["/bin/zsh", "-c", "npm test"], mb: 4),
            proc(203, 202, ["node", "/x/jest/bin/jest.js"], mb: 200),
            proc(204, 201, ["python3", "/x/helper.py"], mb: 40),
        ]
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].kind, .claude)
        XCTAssertEqual(a[0].pid, 200)
        XCTAssertEqual(a[0].tty, "ttys004")
        XCTAssertEqual(a[0].processCount, 5)
        XCTAssertEqual(a[0].treeBytes, (300 + 60 + 4 + 200 + 40) * MiB)
    }

    func testNestedAgentIsSeparateAndNotDoubleCounted() {
        let procs = [
            proc(200, 1, ["claude"], mb: 300),
            proc(201, 200, ["/bin/zsh", "-c", "codex exec hi"], mb: 5),
            proc(202, 201, ["codex", "exec", "hi"], mb: 100),
            proc(203, 202, ["node", "/x/mcp.js"], mb: 50),
            proc(204, 200, ["node", "/x/other-mcp.js"], mb: 20),
        ]
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.count, 2)
        let claude = a.first { $0.kind == .claude }!
        let codex = a.first { $0.kind == .codex }!
        XCTAssertEqual(claude.treeBytes, (300 + 5 + 20) * MiB)
        XCTAssertEqual(claude.processCount, 3)
        XCTAssertEqual(codex.treeBytes, (100 + 50) * MiB)
        XCTAssertEqual(codex.processCount, 2)
        // Total memory is conserved across instances.
        XCTAssertEqual(a.reduce(0) { $0 + $1.treeBytes }, 495 * MiB)
    }

    func testAgentBehindShellInsideSameKindAgentIsSeparate() {
        // A claude started from another claude's Bash tool is its own session.
        let procs = [
            proc(10, 1, ["claude"], mb: 300),
            proc(11, 10, ["/bin/zsh", "-c", "claude -p hi"], mb: 5),
            proc(12, 11, ["claude", "-p", "hi"], mb: 200),
        ]
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.map(\.pid), [10, 12])
        XCTAssertEqual(a.map(\.treeBytes), [305 * MiB, 200 * MiB])
    }

    func testSameKindLauncherIsFoldedIntoOneInstance() {
        // npm-installed codex: node wrapper exec's the native binary as its direct child.
        let procs = [
            proc(10, 1, ["zsh"], mb: 3),
            proc(11, 10, ["node", "/opt/homebrew/bin/codex"], mb: 40),
            proc(12, 11, ["/opt/homebrew/lib/node_modules/@openai/codex/vendor/codex", "resume"], name: "codex", mb: 120),
            proc(13, 12, ["node", "/x/mcp.js"], mb: 30),
        ]
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].pid, 11)
        XCTAssertEqual(a[0].kind, .codex)
        XCTAssertEqual(a[0].processCount, 3)
        XCTAssertEqual(a[0].treeBytes, 190 * MiB)
    }

    func testDifferentKindDirectChildIsSeparate() {
        let procs = [
            proc(10, 1, ["claude"], mb: 300),
            proc(11, 10, ["codex", "exec", "x"], mb: 100),
        ]
        XCTAssertEqual(Aggregator.agents(from: procs).count, 2)
    }

    func testSortedByTreeBytesDescending() {
        let procs = [
            proc(10, 1, ["codex"], mb: 50),
            proc(20, 1, ["claude"], mb: 400),
            proc(30, 1, ["hermes"], mb: 90),
            proc(31, 30, ["node", "/x/mcp.js"], mb: 500),
            proc(40, 1, ["aider"], mb: 50),
        ]
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.map(\.pid), [30, 20, 10, 40], "ties broken by pid")
    }

    func testMissingParentsAndOrphans() {
        let procs = [
            proc(10, 9999, ["claude"], mb: 300), // parent not in list
            proc(11, 10, ["node", "/x/mcp.js"], mb: 10),
            proc(50, 8888, ["node", "/x/orphan.js"], mb: 10),
        ]
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].treeBytes, 310 * MiB)
    }

    func testSelfParentDoesNotLoop() {
        let procs = [proc(0, 0, ["kernel_task"], mb: 1), proc(10, 10, ["claude"], mb: 300)]
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].processCount, 1)
    }

    func testCycleOfNonAgentsUnderAgentTerminates() {
        // pid reuse can produce ppid cycles; nothing may be counted twice.
        let procs = [
            proc(10, 1, ["claude"], mb: 100),
            proc(11, 10, ["node", "a.js"], mb: 10),
            proc(12, 11, ["node", "b.js"], mb: 10),
            proc(13, 12, ["node", "c.js"], mb: 10),
        ] + [proc(11, 13, ["dup"], mb: 999)] // duplicate pid entry is ignored
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].processCount, 4)
        XCTAssertEqual(a[0].treeBytes, 130 * MiB)
    }

    func testCycleBetweenAgentsStillYieldsInstances() {
        // Two different-kind agents pointing at each other: each is a root.
        let mixed = [proc(10, 11, ["claude"], mb: 100), proc(11, 10, ["codex"], mb: 50)]
        XCTAssertEqual(Aggregator.agents(from: mixed).count, 2)

        // Same-kind cycle: neither is an ordinary root, but the session must not vanish.
        let same = [
            proc(10, 11, ["claude"], mb: 100),
            proc(11, 10, ["claude"], mb: 50),
            proc(12, 11, ["node", "x.js"], mb: 5),
        ]
        let a = Aggregator.agents(from: same)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].pid, 10)
        XCTAssertEqual(a[0].treeBytes, 155 * MiB)
        XCTAssertEqual(a[0].processCount, 3)
    }

    func testLongCycleWithoutAgents() {
        var procs: [ProcInfo] = []
        for i in 0..<100 { procs.append(proc(Int32(1000 + i), Int32(1000 + (i + 1) % 100), ["node", "x.js"])) }
        XCTAssertEqual(Aggregator.agents(from: procs), [])
    }

    func testDeepChainIsIterativeAndLinear() {
        // 50k-deep chain must not blow the stack; 200k processes overall must be fast.
        var procs: [ProcInfo] = [proc(1, 0, ["claude"], mb: 1)]
        for i in 2...50_000 { procs.append(proc(Int32(i), Int32(i - 1), ["node", "x.js"], mb: 1)) }
        for i in 50_001...200_000 { procs.append(proc(Int32(i), 1, ["node", "y.js"], mb: 1)) }
        let start = Date()
        let a = Aggregator.agents(from: procs)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].processCount, 200_000)
        XCTAssertEqual(a[0].treeBytes, 200_000 * MiB)
        XCTAssertLessThan(elapsed, 5.0)
    }

    func testRealisticMixOnAuthorsMac() {
        // Shaped after the author's 36 GB machine: Claude Code, codex (with desktop daemons), Hermes.
        var procs: [ProcInfo] = [proc(1, 0, ["/sbin/launchd"], tty: nil, mb: 20)]
        var pid: Int32 = 1000
        func next() -> Int32 { pid += 1; return pid }
        let desktop = next()
        procs.append(proc(desktop, 1, ["/Applications/Claude.app/Contents/MacOS/Claude"], name: "Claude", tty: nil, mb: 400))
        procs.append(proc(next(), desktop, ["/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"], name: "Claude Helper", tty: nil, mb: 200))
        let codexApp = next()
        procs.append(proc(codexApp, 1, ["/Applications/Codex.app/Contents/Resources/codex", "app-server"], name: "codex", tty: nil, mb: 160))
        procs.append(proc(next(), codexApp, ["/Applications/Codex.app/Contents/Resources/codex-code-mode-host"], name: "codex-code-mode-host", tty: nil, mb: 16))
        procs.append(proc(next(), 1, ["python3", "/Users/x/.local/bin/hermes", "gateway", "run"], name: "python3.11", tty: nil, mb: 110))

        for i in 0..<11 {
            let shell = next()
            procs.append(proc(shell, 1, ["-zsh"], name: "zsh", tty: "ttys0\(10 + i)", mb: 3))
            let c = next()
            procs.append(proc(c, shell, ["/Users/x/.local/bin/claude", "--resume"], tty: "ttys0\(10 + i)", mb: 120 + UInt64(i) * 25))
            procs.append(proc(next(), c, ["node", "/x/mcp.js"], tty: "ttys0\(10 + i)", mb: 60))
        }
        for i in 0..<8 {
            let shell = next()
            procs.append(proc(shell, 1, ["-zsh"], name: "zsh", tty: "ttys05\(i)", mb: 3))
            procs.append(proc(next(), shell, ["codex", "resume", "id\(i)"], tty: "ttys05\(i)", mb: 16 + UInt64(i) * 20))
        }
        for i in 0..<4 {
            let shell = next()
            procs.append(proc(shell, 1, ["bash", "-c", "hermes chat"], name: "bash", tty: "ttys07\(i)", mb: 3))
            procs.append(proc(next(), shell, ["python3", "/Users/x/.local/bin/hermes", "chat"], name: "python3.11", tty: "ttys07\(i)", mb: 20 + UInt64(i) * 30))
        }
        let a = Aggregator.agents(from: procs)
        XCTAssertEqual(a.filter { $0.kind == .claude }.count, 11)
        XCTAssertEqual(a.filter { $0.kind == .codex }.count, 8)
        XCTAssertEqual(a.filter { $0.kind == .hermes }.count, 4)
        XCTAssertEqual(a.count, 23)
        XCTAssertEqual(a.first?.kind, .claude)
        XCTAssertEqual(a.first?.treeBytes, (120 + 250 + 60) * MiB)
    }
}
