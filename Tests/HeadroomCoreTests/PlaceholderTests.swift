import XCTest
@testable import HeadroomCore
final class PlaceholderTests: XCTestCase { func testModel() { XCTAssertEqual(HeadroomSettings().reserveBytes, 3 << 30) } }
