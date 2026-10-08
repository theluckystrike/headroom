import XCTest
@testable import HeadroomCore

final class EstimatorTests: XCTestCase {
    let settings = HeadroomSettings()

    // MARK: perAgentBytes

    func testDefaultWhenNoAgents() {
        XCTAssertEqual(Estimator.perAgentBytes([], settings: settings), 600 * MiB)
        var s = settings
        s.defaultPerAgentBytes = 1 * GiB
        XCTAssertEqual(Estimator.perAgentBytes([], settings: s), 1 * GiB)
    }

    func testMedianOdd() {
        let a = [agent(bytes: 900 * MiB), agent(bytes: 200 * MiB), agent(bytes: 400 * MiB)]
        XCTAssertEqual(Estimator.perAgentBytes(a, settings: settings), 400 * MiB)
    }

    func testMedianEven() {
        let a = [agent(bytes: 200 * MiB), agent(bytes: 400 * MiB), agent(bytes: 600 * MiB), agent(bytes: 5 * GiB)]
        XCTAssertEqual(Estimator.perAgentBytes(a, settings: settings), 500 * MiB)
    }

    func testMedianEvenOddSumNoOverflow() {
        let a = [agent(bytes: UInt64.max), agent(bytes: UInt64.max - 2)]
        XCTAssertEqual(Estimator.perAgentBytes(a, settings: settings), 4 * GiB)
        let b = [agent(bytes: 300 * MiB + 1), agent(bytes: 300 * MiB)]
        XCTAssertEqual(Estimator.perAgentBytes(b, settings: settings), 300 * MiB)
    }

    func testClamped() {
        XCTAssertEqual(Estimator.perAgentBytes([agent(bytes: 20 * MiB)], settings: settings), 150 * MiB)
        XCTAssertEqual(Estimator.perAgentBytes([agent(bytes: 0)], settings: settings), 150 * MiB)
        XCTAssertEqual(Estimator.perAgentBytes([agent(bytes: 9 * GiB)], settings: settings), 4 * GiB)
        XCTAssertEqual(Estimator.perAgentBytes([agent(bytes: 150 * MiB)], settings: settings), 150 * MiB)
        XCTAssertEqual(Estimator.perAgentBytes([agent(bytes: 4 * GiB)], settings: settings), 4 * GiB)
    }

    // MARK: headroom

    func testHeadroomFloor() {
        // (14.8G - 3G) / 1G = 11.8 -> 11
        let m = memory(available: 14 * GiB + 800 * MiB)
        XCTAssertEqual(Estimator.headroom(memory: m, perAgentBytes: 1 * GiB, settings: settings), 11)
    }

    func testHeadroomExactBoundary() {
        let m = memory(available: 3 * GiB + 4 * 500 * MiB)
        XCTAssertEqual(Estimator.headroom(memory: m, perAgentBytes: 500 * MiB, settings: settings), 4)
        let m2 = memory(available: 3 * GiB + 4 * 500 * MiB - 1)
        XCTAssertEqual(Estimator.headroom(memory: m2, perAgentBytes: 500 * MiB, settings: settings), 3)
    }

    func testHeadroomNeverNegative() {
        XCTAssertEqual(Estimator.headroom(memory: memory(available: 1 * GiB), perAgentBytes: 300 * MiB, settings: settings), 0)
        XCTAssertEqual(Estimator.headroom(memory: memory(available: 3 * GiB), perAgentBytes: 300 * MiB, settings: settings), 0)
        XCTAssertEqual(Estimator.headroom(memory: memory(available: 0), perAgentBytes: 300 * MiB, settings: settings), 0)
    }

    func testHeadroomZeroPerAgentDoesNotTrap() {
        let h = Estimator.headroom(memory: memory(available: 4 * GiB), perAgentBytes: 0, settings: settings)
        XCTAssertEqual(h, Int(1 * GiB))
    }

    func testHeadroomCustomReserve() {
        var s = settings
        s.reserveBytes = 0
        XCTAssertEqual(Estimator.headroom(memory: memory(available: 6 * GiB), perAgentBytes: 1 * GiB, settings: s), 6)
    }

    // MARK: level

    func testLevels() {
        let m = memory(available: 10 * GiB)
        XCTAssertEqual(Estimator.level(headroom: 0, memory: m, settings: settings), .danger)
        XCTAssertEqual(Estimator.level(headroom: 1, memory: m, settings: settings), .tight)
        XCTAssertEqual(Estimator.level(headroom: 3, memory: m, settings: settings), .tight)
        XCTAssertEqual(Estimator.level(headroom: 4, memory: m, settings: settings), .ok)
        XCTAssertEqual(Estimator.level(headroom: 40, memory: m, settings: settings), .ok)
    }

    func testPressureOverrides() {
        XCTAssertEqual(Estimator.level(headroom: 20, memory: memory(available: 10 * GiB, pressure: .critical), settings: settings), .danger)
        XCTAssertEqual(Estimator.level(headroom: 20, memory: memory(available: 10 * GiB, pressure: .warning), settings: settings), .tight)
        XCTAssertEqual(Estimator.level(headroom: 0, memory: memory(available: 10 * GiB, pressure: .warning), settings: settings), .danger)
    }

    func testSwapDanger() {
        // Author's Mac: 7.3G of 8G swap used = 0.91 -> danger even with room.
        let full = memory(available: 14 * GiB, swapUsed: 7 * GiB + 300 * MiB, swapTotal: 8 * GiB)
        XCTAssertEqual(Estimator.level(headroom: 9, memory: full, settings: settings), .danger)
        let atRatio = memory(available: 14 * GiB, swapUsed: 85, swapTotal: 100)
        XCTAssertEqual(Estimator.level(headroom: 9, memory: atRatio, settings: settings), .danger)
        let below = memory(available: 14 * GiB, swapUsed: 84, swapTotal: 100)
        XCTAssertEqual(Estimator.level(headroom: 9, memory: below, settings: settings), .ok)
    }

    func testNoSwapConfiguredIsNotDanger() {
        let m = memory(available: 14 * GiB, swapUsed: 0, swapTotal: 0)
        XCTAssertEqual(Estimator.level(headroom: 9, memory: m, settings: settings), .ok)
        let weird = memory(available: 14 * GiB, swapUsed: 5, swapTotal: 0)
        XCTAssertEqual(Estimator.level(headroom: 9, memory: weird, settings: settings), .ok)
    }

    func testCustomSwapRatio() {
        var s = settings
        s.swapDangerRatio = 0.5
        let m = memory(available: 14 * GiB, swapUsed: 4 * GiB, swapTotal: 8 * GiB)
        XCTAssertEqual(Estimator.level(headroom: 9, memory: m, settings: s), .danger)
    }

    // MARK: snapshot

    func testSnapshotWiring() {
        let procs = [
            proc(10, 1, ["claude"], tty: "ttys001", mb: 800),
            proc(11, 10, ["node", "mcp.js"], tty: "ttys001", mb: 200),
            proc(20, 1, ["codex"], tty: "ttys002", mb: 400),
            proc(30, 1, ["hermes", "chat"], tty: "ttys003", mb: 600),
        ]
        let m = memory(available: 10 * GiB)
        let t = TerminalState(sessions: 3, byApp: ["Terminal": 3])
        let s = Estimator.snapshot(procs: procs, memory: m, terminals: t, settings: settings, now: 42)
        XCTAssertEqual(s.takenAt, 42)
        XCTAssertEqual(s.memory, m)
        XCTAssertEqual(s.terminals, t)
        XCTAssertEqual(s.agents.map(\.pid), [10, 30, 20])
        XCTAssertEqual(s.perAgentBytes, 600 * MiB)
        // (10G - 3G) / 600M = 11.94 -> 11
        XCTAssertEqual(s.headroomAgents, 11)
        XCTAssertEqual(s.level, .ok)
    }

    func testSnapshotAuthorsMacIsDanger() {
        // 41% of 36G free, swap 7.3/8G: still "+N" but the level must scream.
        let m = MemoryState(totalBytes: 36 * GiB, availableBytes: 36 * GiB * 41 / 100, freePercent: 41,
                            compressedBytes: 6 * GiB, swapUsedBytes: 7 * GiB + 300 * MiB, swapTotalBytes: 8 * GiB,
                            pressure: .warning)
        let procs = (0..<11).map { proc(Int32(100 + $0), 1, ["claude"], mb: 250) }
        let s = Estimator.snapshot(procs: procs, memory: m, terminals: TerminalState(sessions: 131, byApp: [:]),
                                   settings: settings, now: 0)
        XCTAssertEqual(s.perAgentBytes, 250 * MiB)
        XCTAssertGreaterThan(s.headroomAgents, 0)
        XCTAssertEqual(s.level, .danger)
    }

    func testSnapshotNoAgentsUsesDefault() {
        let s = Estimator.snapshot(procs: [], memory: memory(available: 3 * GiB + 1200 * MiB),
                                   terminals: TerminalState(sessions: 0, byApp: [:]), settings: settings, now: 0)
        XCTAssertEqual(s.agents, [])
        XCTAssertEqual(s.perAgentBytes, 600 * MiB)
        XCTAssertEqual(s.headroomAgents, 2)
        XCTAssertEqual(s.level, .tight)
    }
}
