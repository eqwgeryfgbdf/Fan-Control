import Foundation

public struct FanReading: Codable, Identifiable, Sendable {
    public let id: Int
    public let rpm: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let mode: Int?
    public let target: Double?
    public var isAutomatic: Bool { mode == 0 || mode == 3 }
    public var name: String { id == 0 ? "主風扇" : "風扇 \(id + 1)" }
    public var controllable: Bool {
        guard let minimum, let maximum else { return false }
        return minimum.isFinite && maximum.isFinite && minimum > 0 && maximum > minimum && maximum < 20_000
    }
    public init(id: Int, rpm: Double?, minimum: Double?, maximum: Double?, mode: Int?, target: Double?) {
        self.id = id; self.rpm = rpm; self.minimum = minimum; self.maximum = maximum
        self.mode = mode; self.target = target
    }
}

public struct TemperatureReading: Codable, Sendable {
    public let average: Double?
    public let maximum: Double?
    public let sensorCount: Int
    public init(values: [Double]) {
        let valid = values.filter { $0.isFinite && $0 > 0 && $0 < 130 }
        sensorCount = valid.count
        average = valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
        maximum = valid.max()
    }
}

public struct Snapshot: Codable, Sendable {
    public let timestamp: Date
    public let chip: String
    public let model: String
    public let fans: [FanReading]
    public let cpu: TemperatureReading
    public let gpu: TemperatureReading
    public let thermalState: Int
    public let error: String?
}

public struct HistoryPoint: Identifiable {
    public let id = UUID()
    public let time: Date
    public let fanID: Int
    public let rpm: Double?
    public init(time: Date, fanID: Int, rpm: Double?) { self.time = time; self.fanID = fanID; self.rpm = rpm }
}

public enum MonitorError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

public enum HardwareInfo {
    public static func string(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "未知" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "未知" }
        return String(cString: bytes)
    }
}

public enum ControlPolicy {
    public static let leaseSeconds: TimeInterval = 12
    public static func validate(rpm: Double, fan: FanReading) throws {
        guard fan.id >= 0, fan.id <= 9, fan.controllable,
              let minimum = fan.minimum, let maximum = fan.maximum,
              rpm.isFinite, rpm >= minimum, rpm <= maximum else {
            throw MonitorError.message("目標轉速超出這顆風扇的硬體範圍。")
        }
    }
    public static func expired(lastHeartbeat: TimeInterval, now: TimeInterval) -> Bool {
        now - lastHeartbeat >= leaseSeconds
    }
}

public enum ControlClock {
    /// Unlike wall time, this cannot jump; unlike uptime, it includes time asleep.
    public static var now: TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
    }
}
