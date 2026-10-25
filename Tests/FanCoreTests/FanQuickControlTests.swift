import XCTest
@testable import FanCore

final class FanQuickControlTests: XCTestCase {
    private func fan(min: Double? = 1000, max: Double? = 4900) -> FanReading {
        FanReading(id: 0, rpm: 1000, minimum: min, maximum: max, mode: 0, target: 1000)
    }
    func testPresetsAreOmittedOutsideHardwareRange() {
        XCTAssertEqual(FanQuickControl.presets(for: fan()), [1500, 2000, 2500])
        XCTAssertEqual(FanQuickControl.presets(for: fan(min: 1800, max: 2200)), [2000])
        XCTAssertTrue(FanQuickControl.presets(for: fan(min: 3000)).isEmpty)
        XCTAssertTrue(FanQuickControl.presets(for: fan(min: nil)).isEmpty)
    }
    func testInvalidInputCannotBecomeAControlTarget() {
        for input in ["", "nan", "inf", "1e3", "-1500", "1500.5", "2000rpm", "999", "4901", "9999999999999999999999999"] {
            XCTAssertNil(FanQuickControl.parse(input, for: fan()), input)
        }
        XCTAssertEqual(FanQuickControl.parse(" 1500 ", for: fan()), 1500)
        XCTAssertEqual(FanQuickControl.parse("1000", for: fan()), 1000)
        XCTAssertEqual(FanQuickControl.parse("4900", for: fan()), 4900)
        XCTAssertNil(FanQuickControl.parse("1500", for: fan(max: nil)))
    }
}
