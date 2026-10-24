import XCTest
@testable import FanCore

final class FakeSMC: FanHardware {
    var values: [String: Double] = ["F0Ac": 1000, "F0Mn": 1000, "F0Mx": 4900, "F0Md": 0, "F0Tg": 0, "Ftst": 0]
    var writes: [(String, Double)] = []
    var failedKey: String?
    var failedRestorationKey: String?
    var requiresUnlock = false
    var staleTargetReadsAfterWrite = 0
    private var staleTargetReads = 0
    var staleModeReadsAfterRestore = 0
    private var staleModeReads = 0
    func read(_ key: String) throws -> Double {
        if key == "F0Md", staleModeReads > 0 {
            staleModeReads -= 1
            return 1
        }
        if key == "F0Tg", staleTargetReads > 0 {
            staleTargetReads -= 1
            return 1000
        }
        guard let v = values[key] else { throw MonitorError.message("missing") }; return v
    }
    func write(_ key: String, value: Double) throws {
        writes.append((key, value))
        if key == failedRestorationKey && value == 0 { throw MonitorError.message("injected restore failure") }
        if key == failedKey && value != 0 { throw MonitorError.message("injected failure") }
        if requiresUnlock && key == "F0Md" && value == 1 && values["Ftst"] != 1 { throw MonitorError.message("locked") }
        values[key] = value
        if key == "F0Tg", value != 0 { staleTargetReads = staleTargetReadsAfterWrite }
        if key == "F0Md", value == 0 { staleModeReads = staleModeReadsAfterRestore }
    }
    func modeKey(_ id: Int) -> String { "F\(id)Md" }
    func fan(_ id: Int) -> FanReading {
        FanReading(id: id, rpm: values["F\(id)Ac"], minimum: values["F\(id)Mn"], maximum: values["F\(id)Mx"], mode: values["F\(id)Md"].map(Int.init), target: values["F\(id)Tg"])
    }
}

final class FanCoreTests: XCTestCase {
    func testRestoreWaitsForAutomaticModeReadback() throws {
        let hardware = FakeSMC(); hardware.staleModeReadsAfterRestore = 3
        var waits = 0
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in waits += 1 })
        try controller.manual(fan: 0, rpm: 1500)
        try controller.restore()
        XCTAssertEqual(waits, 3)
        XCTAssertFalse(controller.needsRecovery)
        XCTAssertEqual(hardware.values["F0Md"], 0)
    }
    func testUnconfirmedManualReadbackTimesOutAndRestoresAutomatic() throws {
        let hardware = FakeSMC(); hardware.staleTargetReadsAfterWrite = 30
        var waits = 0
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in waits += 1 })
        XCTAssertThrowsError(try controller.manual(fan: 0, rpm: 1500))
        XCTAssertEqual(waits, 20)
        XCTAssertFalse(controller.needsRecovery)
        XCTAssertEqual(hardware.values["F0Md"], 0)
    }
    func testManualWaitsForFirmwareReadbackWithoutRepeatingWrites() throws {
        let hardware = FakeSMC(); hardware.staleTargetReadsAfterWrite = 3
        var waits = 0
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in waits += 1 })
        try controller.manual(fan: 0, rpm: 1500)
        XCTAssertEqual(waits, 3)
        XCTAssertEqual(hardware.writes.filter { $0.0 == "F0Tg" }.count, 1)
        XCTAssertTrue(controller.needsRecovery)
        try controller.restore()
        XCTAssertFalse(controller.needsRecovery)
    }
    func testDecodersPreserveZeroAndSignedTemperatures() throws {
        XCTAssertEqual(try SMC.decode(type: "flt ", bytes: [0, 0, 122, 68]), 1000)
        XCTAssertEqual(try SMC.decode(type: "fpe2", bytes: [0x0f, 0xa0]), 1000)
        XCTAssertEqual(try SMC.decode(type: "sp78", bytes: [0xff, 0x80]), -0.5)
        XCTAssertEqual(try SMC.decode(type: "ui8 ", bytes: [0]), 0)
        XCTAssertThrowsError(try SMC.decode(type: "flt ", bytes: [0, 0, 128, 127]))
        XCTAssertThrowsError(try SMC.decode(type: "flt ", bytes: [0]))
    }
    func testInvalidTargetsNeverWriteHardware() {
        for rpm in [0.0, 999, 4901, .nan, .infinity] {
            let hardware = FakeSMC()
            let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in })
            XCTAssertThrowsError(try controller.manual(fan: 0, rpm: rpm))
            XCTAssertTrue(hardware.writes.isEmpty)
        }
    }
    func testJournalPrecedesWritesAndRestoreReturnsAutomatic() throws {
        let hardware = FakeSMC()
        var journalWrites = 0
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { j in
            if journalWrites == 0 { XCTAssertTrue(hardware.writes.isEmpty); XCTAssertEqual(j.fans, [0]) }
            journalWrites += 1
        }, delay: { _ in })
        try controller.manual(fan: 0, rpm: 2000)
        XCTAssertEqual(hardware.values["F0Md"], 1)
        XCTAssertEqual(hardware.values["F0Tg"], 2000)
        try controller.restore()
        XCTAssertEqual(hardware.values["F0Md"], 0)
        XCTAssertEqual(hardware.values["F0Tg"], 0)
        XCTAssertFalse(controller.needsRecovery)
    }
    func testFailedTargetWriteRestoresModeAndUnlock() {
        let hardware = FakeSMC(); hardware.requiresUnlock = true; hardware.failedKey = "F0Tg"
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in })
        XCTAssertThrowsError(try controller.manual(fan: 0, rpm: 2000))
        XCTAssertEqual(hardware.values["F0Md"], 0)
        XCTAssertEqual(hardware.values["Ftst"], 0)
        XCTAssertFalse(controller.needsRecovery)
    }
    func testExternalManualSessionIsNotTakenOver() {
        let hardware = FakeSMC(); hardware.values["F0Md"] = 1
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in })
        XCTAssertThrowsError(try controller.manual(fan: 0, rpm: 2000))
        XCTAssertTrue(hardware.writes.isEmpty)
    }
    func testFailedJournalPreventsManualHardwareWrite() {
        let hardware = FakeSMC()
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in throw MonitorError.message("disk unavailable") }, delay: { _ in })
        XCTAssertThrowsError(try controller.manual(fan: 0, rpm: 2000))
        XCTAssertTrue(hardware.writes.isEmpty)
    }
    func testCrashRecoveryUsesPersistedOwnership() throws {
        let hardware = FakeSMC(); hardware.values["F0Md"] = 1; hardware.values["F0Tg"] = 2000; hardware.values["Ftst"] = 1
        var journal = ControlJournal(); journal.fans = [0]; journal.changedTestMode = true
        let data = try JSONEncoder().encode(journal)
        let recovered = try JSONDecoder().decode(ControlJournal.self, from: data)
        let controller = FanController(hardware: hardware, appleSilicon: true, journal: recovered, persist: { _ in }, delay: { _ in })
        try controller.restore()
        XCTAssertEqual(hardware.values["F0Md"], 0); XCTAssertEqual(hardware.values["Ftst"], 0)
    }
    func testTemperatureUnavailableIsNotZero() {
        let reading = TemperatureReading(values: [.nan, .infinity, -1, 0, 200])
        XCTAssertNil(reading.average); XCTAssertEqual(reading.sensorCount, 0)
        XCTAssertEqual(TemperatureReading(values: [40, 50]).average, 45)
    }
    func testFailedRestoreRetainsOwnershipForRetry() throws {
        let hardware = FakeSMC()
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in })
        try controller.manual(fan: 0, rpm: 2000)
        hardware.failedRestorationKey = "F0Md"
        XCTAssertThrowsError(try controller.restore())
        XCTAssertTrue(controller.needsRecovery)
        hardware.failedRestorationKey = nil
        try controller.restore()
        XCTAssertFalse(controller.needsRecovery)
        XCTAssertEqual(hardware.values["F0Md"], 0)
    }
    func testExistingGlobalTestModeIsNotCleared() throws {
        let hardware = FakeSMC(); hardware.values["Ftst"] = 1
        let controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in })
        try controller.manual(fan: 0, rpm: 2000)
        try controller.restore()
        XCTAssertEqual(hardware.values["Ftst"], 1)
        XCTAssertFalse(hardware.writes.contains { $0.0 == "Ftst" })
    }
    func testSensorMappingsAndLease() {
        XCTAssertTrue(SensorMap.keys(chip: "Apple M4").cpu.contains("Tp09"))
        XCTAssertTrue(SensorMap.keys(chip: "Apple M4 Pro").gpu.contains("Tg1U"))
        XCTAssertFalse(SensorMap.keys(chip: "Apple M4 Pro").gpu.contains("Tg0G"))
        XCTAssertTrue(SensorMap.keys(chip: "Apple unknown").cpu.isEmpty)
        XCTAssertFalse(ControlPolicy.expired(lastHeartbeat: 10, now: 21.9))
        XCTAssertTrue(ControlPolicy.expired(lastHeartbeat: 10, now: 22))
    }
}
