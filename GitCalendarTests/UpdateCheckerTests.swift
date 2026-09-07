import XCTest

final class UpdateCheckerTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertLessThan(SemanticVersion("1.9.9"), SemanticVersion("v1.10.0"))
        XCTAssertLessThan(SemanticVersion("1.0"), SemanticVersion("1.0.1"))
        XCTAssertEqual(SemanticVersion("v2.0.0"), SemanticVersion("2.0"))
        XCTAssertFalse(SemanticVersion("2.1.0") < SemanticVersion("2.0.9"))
    }
}
