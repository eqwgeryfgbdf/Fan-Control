import XCTest
@testable import FanCore

final class FanTrendTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1_000)
    private func point(_ secondsAgo: Double, _ rpm: Double?, fan: Int = 0) -> HistoryPoint {
        HistoryPoint(time: end.addingTimeInterval(-secondsAgo), fanID: fan, rpm: rpm)
    }

    func testWindowExcludesOtherFansOldAndFutureSamples() {
        let trend = FanTrend(history: [point(61, 4900), point(2, 3000, fan: 1),
                                      point(-1, 4000), point(0, 1500), point(1, 1000)], fanID: 0, end: end)
        XCTAssertEqual(trend.points.compactMap(\.rpm), [1000, 1500])
        XCTAssertEqual(trend.minimum, 1000)
        XCTAssertEqual(trend.maximum, 1500)
    }

    func testMissingInvalidAndDelayedSamplesDoNotDrawConnectingLines() {
        let history = [point(15, 1000), point(14, 1001), point(13, nil), point(12, 1100),
                       point(11, .nan), point(10, 1200), point(9, .infinity), point(8, -1),
                       point(7, 1300), point(0, 1400)]
        let trend = FanTrend(history: history, fanID: 0, end: end)
        XCTAssertEqual(trend.segments.map { $0.points.compactMap(\.rpm) },
                       [[1000, 1001], [1100], [1200], [1300], [1400]])
    }

    func testScaleDoesNotExaggerateNoiseAndEmptyDataStaysUnavailable() {
        let flat = FanTrend(history: [point(1, 1000), point(0, 1001)], fanID: 0, end: end)
        XCTAssertGreaterThanOrEqual(flat.upperBound - flat.lowerBound, 200)
        XCTAssertLessThan(flat.lowerBound, 1000)
        XCTAssertGreaterThan(flat.upperBound, 1001)
        let empty = FanTrend(history: [point(0, nil)], fanID: 0, end: end)
        XCTAssertNil(empty.minimum)
        XCTAssertNil(empty.maximum)
        XCTAssertTrue(empty.segments.isEmpty)
        let stopped = FanTrend(history: [point(0, 0)], fanID: 0, end: end)
        XCTAssertEqual(stopped.minimum, 0)
        XCTAssertEqual(stopped.lowerBound, 0)
    }
}
