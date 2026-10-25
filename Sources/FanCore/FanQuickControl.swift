import Foundation

public enum FanQuickControl {
    /// Keep labels truthful: omit unsupported presets rather than silently clamping.
    public static func presets(for fan: FanReading) -> [Double] {
        [1500.0, 2000, 2500].filter { (try? ControlPolicy.validate(rpm: $0, fan: fan)) != nil }
    }
    public static func parse(_ text: String, for fan: FanReading) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let integer = Int(value) else { return nil }
        let rpm = Double(integer)
        guard (try? ControlPolicy.validate(rpm: rpm, fan: fan)) != nil else { return nil }
        return rpm
    }
}
