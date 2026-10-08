import Foundation
import XCTest
@testable import HeadroomCore

final class FormatTests: XCTestCase {
    func testBytesSmall() {
        XCTAssertEqual(Format.bytes(0), "0B")
        XCTAssertEqual(Format.bytes(1), "1B")
        XCTAssertEqual(Format.bytes(1023), "1023B")
    }

    func testBytesUnits() {
        XCTAssertEqual(Format.bytes(1024), "1.0K")
        XCTAssertEqual(Format.bytes(1536), "1.5K")
        XCTAssertEqual(Format.bytes(1 * MiB), "1.0M")
        XCTAssertEqual(Format.bytes(812 * MiB), "812M")
        XCTAssertEqual(Format.bytes(1 * GiB), "1.0G")
        XCTAssertEqual(Format.bytes(14541 * MiB), "14.2G")
        XCTAssertEqual(Format.bytes(36 * GiB), "36.0G")
        XCTAssertEqual(Format.bytes(1 << 40), "1.0T")
    }

    func testBytesDecimalBoundary() {
        XCTAssertEqual(Format.bytes(99 * MiB), "99.0M")
        XCTAssertEqual(Format.bytes(100 * MiB), "100M")
        XCTAssertEqual(Format.bytes(99 * MiB + 1000 * 1024), "100M", "99.98M rounds up to the integer form")
        XCTAssertEqual(Format.bytes(99 * MiB + 900 * 1024), "99.9M")
        XCTAssertEqual(Format.bytes(1023 * MiB + 1000 * 1024), "1.0G", "1023.98M promotes to the next unit")
        XCTAssertEqual(Format.bytes(512 * MiB + 600 * 1024), "513M")
    }

    func testBytesMax() {
        XCTAssertEqual(Format.bytes(UInt64.max), "16.0E")
    }

    func testLine() {
        XCTAssertEqual(Format.line(Fixtures.demo), "AG 12 | TTY 31 | 14.2G free | +9")
        var s = Fixtures.demo
        s.agents = []
        s.terminals.sessions = 0
        s.memory.availableBytes = 0
        s.headroomAgents = 0
        XCTAssertEqual(Format.line(s), "AG 0 | TTY 0 | 0B free | +0")
    }

    func testJSONIsPrettySortedAndRoundTrips() throws {
        let text = Format.json(Fixtures.demo)
        XCTAssertTrue(text.contains("\n  "), "pretty printed")
        let agents = try XCTUnwrap(text.range(of: "\"agents\""))
        let headroom = try XCTUnwrap(text.range(of: "\"headroomAgents\""))
        let level = try XCTUnwrap(text.range(of: "\"level\""))
        let takenAt = try XCTUnwrap(text.range(of: "\"takenAt\""))
        XCTAssertLessThan(agents.lowerBound, headroom.lowerBound)
        XCTAssertLessThan(headroom.lowerBound, level.lowerBound)
        XCTAssertLessThan(level.lowerBound, takenAt.lowerBound)
        XCTAssertTrue(text.contains("\"level\" : \"ok\""))
        XCTAssertTrue(text.contains("\"kind\" : \"claude\""))
        let decoded = try JSONDecoder().decode(Snapshot.self, from: Data(text.utf8))
        XCTAssertEqual(decoded, Fixtures.demo)
        XCTAssertEqual(Format.json(Fixtures.demo), text, "stable output")
    }
}
