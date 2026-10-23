import Foundation
import IOKit

// SMC wire format and key conventions adapted from exelban/Stats (MIT).
// This transport is intentionally serial; the caller owns its execution queue.
public final class SMC {
    private var connection: io_connect_t = 0
    private var cache: [String: (size: UInt32, type: String)] = [:]
    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw MonitorError.message("這台 Mac 沒有可用的 SMC 感測器介面。") }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { throw MonitorError.message("無法開啟 SMC（\(result)）。") }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }

    public static func fourCC(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    private func call(key: String, command: UInt8, size: UInt32 = 0, payload: [UInt8] = []) throws -> [UInt8] {
        guard key.utf8.count == 4, payload.count <= 32, size <= 32,
              [UInt8(5), 6, 9].contains(command) else { throw MonitorError.message("無效的 SMC 請求。") }
        var input = [UInt8](repeating: 0, count: 80)
        func store(_ n: UInt32, _ offset: Int) {
            for i in 0..<4 { input[offset+i] = UInt8(truncatingIfNeeded: n >> (i*8)) }
        }
        store(Self.fourCC(key), 0); store(size, 28)
        input[42] = command
        for (i, byte) in payload.enumerated() { input[48+i] = byte }
        var output = [UInt8](repeating: 0, count: 80)
        var outputSize = 80
        let result = input.withUnsafeBytes { src in
            output.withUnsafeMutableBytes { dst in
                IOConnectCallStructMethod(connection, 2, src.baseAddress, 80, dst.baseAddress, &outputSize)
            }
        }
        guard result == KERN_SUCCESS, outputSize == 80, output[40] == 0 else {
            throw MonitorError.message("感測器 \(key) 無法\(command == 6 ? "寫入" : "讀取")（IO \(result)，SMC \(output[40])）。")
        }
        return output
    }
    private func info(_ key: String) throws -> (size: UInt32, type: String) {
        if let value = cache[key] { return value }
        let bytes = try call(key: key, command: 9)
        let size = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[28+$1]) << ($1*8)) }
        let type = String(bytes: bytes[32..<36].reversed(), encoding: .ascii) ?? ""
        guard size > 0, size <= 32, !type.isEmpty else { throw MonitorError.message("不支援的感測器格式。") }
        cache[key] = (size, type)
        return (size, type)
    }
    public func read(_ key: String) throws -> Double {
        let info = try info(key)
        let result = try call(key: key, command: 5, size: info.size)
        return try Self.decode(type: info.type, bytes: Array(result[48..<(48+Int(info.size))]))
    }
    public static func decode(type: String, bytes: [UInt8]) throws -> Double {
        let integer = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let value: Double
        switch (type, bytes.count) {
        case ("ui8 ", 1), ("ui16", 2), ("ui32", 4): value = Double(integer)
        case ("flt ", 4):
            let bits = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[$1]) << ($1*8)) }
            value = Double(Float(bitPattern: bits))
        case ("fpe2", 2): value = Double(integer) / 4
        case ("sp78", 2): value = Double(Int16(bitPattern: UInt16(integer))) / 256
        default: throw MonitorError.message("不支援的感測器格式：\(type)。")
        }
        guard value.isFinite else { throw MonitorError.message("感測器回傳無效數值。") }
        return value
    }
    public func write(_ key: String, value: Double) throws {
        // Only the privileged helper may write. No generic key-writing IPC is exposed.
        guard geteuid() == 0 else { throw MonitorError.message("調速需要啟用風扇控制服務。") }
        let info = try info(key)
        let bytes: [UInt8]
        guard value.isFinite, value >= 0 else { throw MonitorError.message("無效的控制數值。") }
        switch (info.type, info.size) {
        case ("ui8 ", 1):
            guard value <= 255 else { throw MonitorError.message("控制數值超出範圍。") }
            bytes = [UInt8(value)]
        case ("ui16", 2):
            guard value <= 65535 else { throw MonitorError.message("控制數值超出範圍。") }
            bytes = [UInt8(Int(value) >> 8), UInt8(truncatingIfNeeded: Int(value))]
        case ("flt ", 4):
            let bits = Float(value).bitPattern
            bytes = (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0*8)) }
        case ("fpe2", 2):
            guard value < 16384 else { throw MonitorError.message("控制數值超出範圍。") }
            let n = UInt16(value * 4)
            bytes = [UInt8(n >> 8), UInt8(truncatingIfNeeded: n)]
        default: throw MonitorError.message("不支援這台 Mac 的調速格式。")
        }
        _ = try call(key: key, command: 6, size: info.size, payload: bytes)
    }
    public func modeKey(_ id: Int) -> String {
        (try? read("F\(id)md")) != nil ? "F\(id)md" : "F\(id)Md"
    }
    public func fan(_ id: Int) -> FanReading {
        FanReading(id: id, rpm: try? read("F\(id)Ac"), minimum: try? read("F\(id)Mn"),
                   maximum: try? read("F\(id)Mx"), mode: (try? read(modeKey(id))).map(Int.init), target: try? read("F\(id)Tg"))
    }
    public func fanCount() throws -> Int {
        let n = try read("FNum")
        guard n >= 0, n <= 10 else { throw MonitorError.message("風扇數量無效。") }
        return Int(n)
    }
}

public final class SensorReader {
    private var smc: SMC?
    private let chip = HardwareInfo.string("machdep.cpu.brand_string")
    private let model = HardwareInfo.string("hw.model")
    public init() {}
    public func sample() -> Snapshot {
        do {
            if smc == nil { smc = try SMC() }
            guard let smc else { throw MonitorError.message("無法連接感測器。") }
            let count = try smc.fanCount()
            let fans = (0..<count).map(smc.fan)
            let keys = SensorMap.keys(chip: chip)
            let cpu = TemperatureReading(values: keys.cpu.compactMap { try? smc.read($0) })
            let gpu = TemperatureReading(values: keys.gpu.compactMap { try? smc.read($0) })
            return Snapshot(timestamp: Date(), chip: chip, model: model, fans: fans, cpu: cpu, gpu: gpu,
                            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                            error: fans.contains(where: { $0.rpm == nil }) ? "部分風扇資料無法讀取。" : nil)
        } catch {
            smc = nil
            return Snapshot(timestamp: Date(), chip: chip, model: model, fans: [],
                            cpu: TemperatureReading(values: []), gpu: TemperatureReading(values: []),
                            thermalState: ProcessInfo.processInfo.thermalState.rawValue, error: error.localizedDescription)
        }
    }
}
