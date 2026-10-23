import Foundation
import FanCore
import os

private let log = Logger(subsystem: ServiceIdentity.helper, category: "control")
private let queue = DispatchQueue(label: "local.macmini.contoral.hardware")
private let journalURL = URL(fileURLWithPath: "/var/run/local.macmini.contoral.control.json")

final class ServiceState {
    let controller: FanController
    var owner: UUID?
    var lastHeartbeat = ControlClock.now
    init() throws {
        let hardware = try SMC()
        let journal: ControlJournal
        if FileManager.default.fileExists(atPath: journalURL.path) {
            // A corrupt recovery journal must not silently permit new manual control.
            journal = try JSONDecoder().decode(ControlJournal.self, from: Data(contentsOf: journalURL))
        } else { journal = ControlJournal() }
        controller = FanController(hardware: hardware, appleSilicon: HardwareInfo.string("machdep.cpu.brand_string").contains("Apple"), journal: journal) {
            try JSONEncoder().encode($0).write(to: journalURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        }
        if controller.needsRecovery { recover() }
    }
    func recover() {
        do { try controller.restore(); owner = nil }
        catch { log.error("Automatic recovery pending: \(error.localizedDescription, privacy: .public)") }
    }
    func tick() {
        guard controller.needsRecovery else { return }
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        if owner == nil || hot || ControlPolicy.expired(lastHeartbeat: lastHeartbeat, now: ControlClock.now) {
            recover()
        }
    }
}

final class Session: NSObject, FanControlProtocol {
    let id = UUID()
    let state: ServiceState
    init(state: ServiceState) { self.state = state }
    func ping(reply: @escaping (String) -> Void) { reply("MacminiContoral helper 1.0") }
    func setManual(fan: Int, rpm: Double, reply: @escaping (String?) -> Void) {
        queue.async {
            guard self.state.owner == nil || self.state.owner == self.id else {
                reply("另一個 App 連線正在控制風扇。"); return
            }
            guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
                self.state.recover(); reply("系統正在降溫，請使用自動調節。"); return
            }
            do {
                try self.state.controller.manual(fan: fan, rpm: rpm)
                self.state.owner = self.id
                self.state.lastHeartbeat = ControlClock.now
                reply(nil)
            } catch {
                if self.state.controller.needsRecovery { self.state.owner = nil }
                reply(error.localizedDescription)
            }
        }
    }
    func restoreAutomatic(reply: @escaping (String?) -> Void) {
        queue.async {
            guard self.state.owner == nil || self.state.owner == self.id else {
                reply("另一個 App 連線正在控制風扇。"); return
            }
            do { try self.state.controller.restore(); self.state.owner = nil; reply(nil) }
            catch { self.state.owner = nil; reply(error.localizedDescription) }
        }
    }
    func heartbeat(reply: @escaping (Bool) -> Void) {
        queue.async {
            if self.state.owner == self.id { self.state.lastHeartbeat = ControlClock.now }
            reply(self.state.owner == self.id)
        }
    }
    func disconnected() {
        queue.async {
            if self.state.owner == self.id { self.state.owner = nil; self.state.recover() }
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let state: ServiceState
    init(state: ServiceState) { self.state = state }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let session = Session(state: state)
        connection.exportedInterface = NSXPCInterface(with: FanControlProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { session.disconnected() }
        connection.interruptionHandler = { session.disconnected() }
        connection.resume()
        return true
    }
}

guard geteuid() == 0 else { fputs("This service must be launched by macOS ServiceManagement.\n", stderr); exit(1) }
let bundleURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
guard let bundle = Bundle(url: bundleURL),
      let team = bundle.object(forInfoDictionaryKey: "MacminiSigningTeam") as? String,
      team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
    fputs("Missing signing identity.\n", stderr); exit(1)
}
do {
    let state = try ServiceState()
    let delegate = ListenerDelegate(state: state)
    let listener = NSXPCListener(machServiceName: ServiceIdentity.helper)
    listener.setConnectionCodeSigningRequirement(ServiceIdentity.requirement(identifier: ServiceIdentity.app, team: team))
    listener.delegate = delegate
    listener.resume()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { state.tick() }
    timer.resume()
    signal(SIGTERM, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
    termination.setEventHandler { state.recover(); exit(0) }
    termination.resume()
    // The daemon stays alive so launchd can restart it and recover the journal after a crash.
    withExtendedLifetime((listener, delegate, timer, termination)) { RunLoop.current.run() }
} catch {
    log.error("Unable to start: \(error.localizedDescription, privacy: .public)")
    exit(1)
}
