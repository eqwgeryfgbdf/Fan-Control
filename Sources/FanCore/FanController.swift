import Foundation

public protocol FanHardware: AnyObject {
    func read(_ key: String) throws -> Double
    func write(_ key: String, value: Double) throws
    func modeKey(_ id: Int) -> String
    func fan(_ id: Int) -> FanReading
}
extension SMC: FanHardware {}

public struct ControlJournal: Codable {
    public var fans: Set<Int> = []
    public var changedTestMode = false
    public init() {}
}

/// All methods run on one serial queue. An on-disk journal precedes every mutation.
public final class FanController {
    private let hardware: FanHardware
    private let appleSilicon: Bool
    private let persist: (ControlJournal) throws -> Void
    private let delay: (TimeInterval) -> Void
    public private(set) var journal: ControlJournal
    public var needsRecovery: Bool { !journal.fans.isEmpty || journal.changedTestMode }
    public init(hardware: FanHardware, appleSilicon: Bool, journal: ControlJournal = ControlJournal(),
                persist: @escaping (ControlJournal) throws -> Void,
                delay: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)) {
        self.hardware = hardware; self.appleSilicon = appleSilicon
        self.journal = journal; self.persist = persist; self.delay = delay
    }
    private func retryWrite(_ key: String, value: Double, attempts: Int = 10) throws {
        var failure: Error = MonitorError.message("寫入失敗。")
        for i in 0..<attempts {
            do { try hardware.write(key, value: value); return }
            catch { failure = error; if i+1 < attempts { delay(0.05) } }
        }
        throw failure
    }
    public func manual(fan id: Int, rpm: Double) throws {
        let fan = hardware.fan(id)
        try ControlPolicy.validate(rpm: rpm, fan: fan)
        guard fan.isAutomatic || journal.fans.contains(id) else {
            throw MonitorError.message("此風扇已由其他程式手動控制，請先恢復自動調節。")
        }
        journal.fans.insert(id)
        try persist(journal)
        do {
            let mode = hardware.modeKey(id)
            if appleSilicon {
                do { try hardware.write(mode, value: 1) }
                catch {
                    let testMode = try hardware.read("Ftst")
                    if testMode != 1 {
                        journal.changedTestMode = true
                        try persist(journal)
                        try retryWrite("Ftst", value: 1, attempts: 100)
                        delay(3)
                    }
                    try retryWrite(mode, value: 1, attempts: 160)
                }
            } else {
                if (try? hardware.read(mode)) != nil { try hardware.write(mode, value: 1) }
                let mask = Int(try hardware.read("FS! ")) | (1 << id)
                try hardware.write("FS! ", value: Double(mask))
            }
            try retryWrite("F\(id)Tg", value: rpm)
            let target = try hardware.read("F\(id)Tg")
            let actualMode = try hardware.read(mode)
            guard abs(target - rpm) <= 5, actualMode == 1 else {
                throw MonitorError.message("風扇未確認目標設定，已要求恢復自動調節。")
            }
        } catch {
            let original = error
            do { try restore() }
            catch { throw MonitorError.message("\(original.localizedDescription) 自動恢復尚未完成，服務會持續重試：\(error.localizedDescription)") }
            throw original
        }
    }
    public func restore() throws {
        var errors: [String] = []
        for id in journal.fans.sorted() {
            do {
                let mode = hardware.modeKey(id)
                if appleSilicon {
                    try retryWrite(mode, value: 0)
                    try retryWrite("F\(id)Tg", value: 0)
                } else {
                    if (try? hardware.read(mode)) != nil { try hardware.write(mode, value: 0) }
                    let mask = Int(try hardware.read("FS! ")) & ~(1 << id)
                    try hardware.write("FS! ", value: Double(mask))
                }
                let value = try hardware.read(mode)
                guard value == 0 || value == 3 else { throw MonitorError.message("風扇仍處於手動模式。") }
                journal.fans.remove(id)
                try persist(journal)
            } catch { errors.append(error.localizedDescription) }
        }
        if journal.fans.isEmpty && journal.changedTestMode {
            do {
                try retryWrite("Ftst", value: 0)
                journal.changedTestMode = false
                try persist(journal)
            } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw MonitorError.message(errors.joined(separator: " ")) }
    }
}
