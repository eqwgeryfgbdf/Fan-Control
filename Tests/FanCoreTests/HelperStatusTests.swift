import XCTest
@testable import FanCore

final class HelperStatusTests: XCTestCase {
    func testMatchingVersionAndBuildAreBothRequired() throws {
        let status = HelperStatus(version: "1.0.3", build: "5", ownedByClient: false,
                                  controlledFans: [], recoveryPending: false, recoveryReason: nil)
        XCTAssertTrue(status.matches(version: "1.0.3", build: "5"))
        XCTAssertFalse(status.matches(version: "1.0.2", build: "5"))
        XCTAssertFalse(status.matches(version: "1.0.3", build: "4"))
        let incompatible = HelperStatus(version: "1.0.3", build: "5", ownedByClient: false,
                                        controlledFans: [], recoveryPending: false, recoveryReason: nil, protocolVersion: 1)
        XCTAssertFalse(incompatible.matches(version: "1.0.3", build: "5"))
        XCTAssertThrowsError(try JSONDecoder().decode(HelperStatus.self, from: Data("MacminiContoral helper 1.0".utf8)))
    }
    func testRecoveryAndOwnershipSurviveHandshakeEncoding() throws {
        let pending = HelperStatus(version: "1.0.3", build: "5", ownedByClient: false,
                                   controlledFans: [0, 1], recoveryPending: true, recoveryReason: .sensors)
        let decoded = try JSONDecoder().decode(HelperStatus.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(decoded, pending)
        XCTAssertTrue(decoded.recoveryPending)
        XCTAssertFalse(decoded.ownedByClient)
    }
}
