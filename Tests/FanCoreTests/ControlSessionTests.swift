import XCTest
@testable import FanCore

private final class SessionFixture {
    let hardware = FakeSMC()
    let id = UUID()
    var time: TimeInterval = 100
    var thermal = 0
    var cpu = [50.0]
    var gpu = [45.0]
    var missingFans = false
    var fanIDs = [0]
    lazy var controller = FanController(hardware: hardware, appleSilicon: true, persist: { _ in }, delay: { _ in })
    lazy var session = ControlSessionState(controller: controller, sample: { [unowned self] in
        Snapshot(timestamp: Date(), chip: "Apple M4", model: "Test", fans: missingFans ? [] : fanIDs.map(hardware.fan),
                 cpu: TemperatureReading(values: cpu), gpu: TemperatureReading(values: gpu), thermalState: thermal, error: nil)
    }, thermalState: { [unowned self] in thermal }, clock: { [unowned self] in time })
    func start() throws { try session.manual(session: id, fan: 0, rpm: 1500) }
    func tick(at time: TimeInterval) throws {
        self.time = time
        _ = session.heartbeat(session: id)
        try session.tick()
    }
}

final class ControlSessionTests: XCTestCase {
    func testSensorLossRestoresDespiteFreshHeartbeats() throws {
        let f = SessionFixture(); try f.start()
        f.hardware.values.removeValue(forKey: "F0Ac")
        try f.tick(at: 101); try f.tick(at: 103.9)
        XCTAssertEqual(f.hardware.values["F0Md"], 1)
        try f.tick(at: 104)
        XCTAssertEqual(f.hardware.values["F0Md"], 0)
        XCTAssertNil(f.session.owner)
        XCTAssertEqual(f.session.recoveryReason, .sensors)
    }

    func testTemperatureLossRequiresContinuousFailure() throws {
        for gpuMissing in [false, true] {
            let f = SessionFixture(); try f.start()
            if gpuMissing { f.gpu = [] } else { f.cpu = [] }
            try f.tick(at: 101); try f.tick(at: 102)
            f.cpu = [50]; f.gpu = [45]; try f.tick(at: 103)
            if gpuMissing { f.gpu = [] } else { f.cpu = [] }
            try f.tick(at: 104); try f.tick(at: 106.9)
            XCTAssertEqual(f.hardware.values["F0Md"], 1)
            try f.tick(at: 107)
            XCTAssertEqual(f.hardware.values["F0Md"], 0)
        }
    }

    func testUnsupportedTemperaturesDoNotPreventManualControl() throws {
        let f = SessionFixture(); f.cpu = []; f.gpu = []; try f.start()
        try f.tick(at: 110); try f.tick(at: 120)
        XCTAssertEqual(f.hardware.values["F0Md"], 1)
        // A newly available family becomes required for this session.
        f.cpu = [50]; try f.tick(at: 121); f.cpu = []
        try f.tick(at: 122); try f.tick(at: 125)
        XCTAssertEqual(f.hardware.values["F0Md"], 0)
    }

    func testMissingFanRejectsManualBeforeHardwareWrite() {
        let f = SessionFixture(); f.missingFans = true
        XCTAssertThrowsError(try f.start())
        XCTAssertTrue(f.hardware.writes.isEmpty)
    }

    func testFailedRecoveryRevokesLeaseAndRetriesBeforeNewControl() throws {
        let f = SessionFixture(); try f.start()
        f.hardware.failedRestorationKey = "F0Md"
        f.thermal = 2
        XCTAssertThrowsError(try f.session.tick())
        XCTAssertNil(f.session.owner)
        XCTAssertFalse(f.session.heartbeat(session: f.id))
        f.thermal = 0
        XCTAssertThrowsError(try f.start())
        f.hardware.failedRestorationKey = nil
        try f.session.tick()
        XCTAssertEqual(f.hardware.values["F0Md"], 0)
        XCTAssertFalse(f.controller.needsRecovery)
    }

    func testLeaseAndThermalRecoveryUseTheRealSessionState() throws {
        let f = SessionFixture(); try f.start()
        f.time = 111.9; try f.session.tick()
        XCTAssertEqual(f.hardware.values["F0Md"], 1)
        f.time = 112; try f.session.tick()
        XCTAssertEqual(f.session.recoveryReason, .leaseExpired)
        XCTAssertEqual(f.hardware.values["F0Md"], 0)
        try f.start(); f.thermal = 2; try f.session.tick()
        XCTAssertEqual(f.session.recoveryReason, .thermal)
        XCTAssertEqual(f.hardware.values["F0Md"], 0)
    }

    func testOnlyOwningConnectionCanControlOrDisconnect() throws {
        let f = SessionFixture(); try f.start(); let other = UUID()
        XCTAssertThrowsError(try f.session.manual(session: other, fan: 0, rpm: 2000))
        XCTAssertThrowsError(try f.session.restore(session: other))
        try f.session.disconnected(session: other)
        XCTAssertEqual(f.hardware.values["F0Md"], 1)
        try f.session.disconnected(session: f.id)
        XCTAssertEqual(f.hardware.values["F0Md"], 0)
        XCTAssertEqual(f.session.recoveryReason, .connectionLost)
    }

    func testAllOwnedFansAreMonitored() throws {
        let f = SessionFixture()
        for (key, value) in f.hardware.values where key.hasPrefix("F0") {
            f.hardware.values[key.replacingOccurrences(of: "F0", with: "F1")] = value
        }
        f.fanIDs = [0, 1]; try f.start()
        try f.session.manual(session: f.id, fan: 1, rpm: 2000)
        f.fanIDs = [1]
        try f.tick(at: 101); try f.tick(at: 104)
        XCTAssertEqual(f.hardware.values["F0Md"], 0)
        XCTAssertEqual(f.hardware.values["F1Md"], 0)
    }
}
