import Foundation

/// A one-minute view of real samples. Missing readings and sampling gaps stay gaps.
public struct FanTrend {
    public struct Segment: Identifiable {
        public let id: Int
        public let points: [HistoryPoint]
    }
    public let start: Date
    public let end: Date
    public let segments: [Segment]
    public let minimum: Double?
    public let maximum: Double?
    public let lowerBound: Double
    public let upperBound: Double
    public var points: [HistoryPoint] { segments.flatMap(\.points) }

    public init(history: [HistoryPoint], fanID: Int, end: Date) {
        self.end = end
        let start = end.addingTimeInterval(-60)
        self.start = start
        let samples = history.filter { $0.fanID == fanID && $0.time >= start && $0.time <= end }
            .sorted { $0.time < $1.time }
        var groups: [[HistoryPoint]] = []
        var current: [HistoryPoint] = []
        for sample in samples {
            let valid = sample.rpm.map { $0.isFinite && $0 >= 0 } ?? false
            if !valid || current.last.map({ sample.time.timeIntervalSince($0.time) > 3 }) == true {
                if !current.isEmpty { groups.append(current); current = [] }
            }
            if valid { current.append(sample) }
        }
        if !current.isEmpty { groups.append(current) }
        segments = groups.enumerated().map { Segment(id: $0.offset, points: $0.element) }
        let values = groups.flatMap { $0 }.compactMap(\.rpm)
        minimum = values.min(); maximum = values.max()
        // A minimum 200 RPM span avoids exaggerating one-RPM sensor noise.
        lowerBound = max(0, floor(((minimum ?? 1000) - 100) / 100) * 100)
        upperBound = max(lowerBound + 200, ceil(((maximum ?? 1000) + 100) / 100) * 100)
    }
}
