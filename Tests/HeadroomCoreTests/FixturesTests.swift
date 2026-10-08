import XCTest
@testable import HeadroomCore

final class FixturesTests: XCTestCase {
    func testDemoShape() {
        let d = Fixtures.demo
        XCTAssertEqual(d.agents.count, 12)
        XCTAssertGreaterThanOrEqual(Set(d.agents.map(\.kind)).count, 4, "mixed kinds")
        XCTAssertEqual(d.terminals.sessions, 31)
        XCTAssertEqual(d.terminals.byApp.values.reduce(0, +), 31)
        XCTAssertEqual(Set(d.terminals.byApp.keys), ["Terminal", "iTerm2", "tmux"])
        XCTAssertEqual(d.memory.totalBytes, 36 * GiB)
        XCTAssertEqual(Format.bytes(d.memory.availableBytes), "14.2G")
        XCTAssertEqual(d.headroomAgents, 9)
        XCTAssertEqual(d.level, .ok)
    }

    func testDemoIsSortedAndUnique() {
        let d = Fixtures.demo
        XCTAssertEqual(d.agents.map(\.treeBytes), d.agents.map(\.treeBytes).sorted(by: >))
        XCTAssertEqual(Set(d.agents.map(\.pid)).count, d.agents.count)
    }

    func testDemoAgreesWithEstimator() {
        let d = Fixtures.demo
        let s = HeadroomSettings()
        XCTAssertEqual(d.perAgentBytes, Estimator.perAgentBytes(d.agents, settings: s))
        XCTAssertEqual(d.headroomAgents, Estimator.headroom(memory: d.memory, perAgentBytes: d.perAgentBytes, settings: s))
        XCTAssertEqual(d.level, Estimator.level(headroom: d.headroomAgents, memory: d.memory, settings: s))
    }
}
