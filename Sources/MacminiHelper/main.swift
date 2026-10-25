import Foundation
import FanCore
import os
import MachO

private let log = Logger(subsystem: ServiceIdentity.helper, category: "control")
private let queue = DispatchQueue(label: "local.macmini.contoral.hardware")
private let journalURL = URL(fileURLWithPath: "/var/run/local.macmini.contoral.control.json")

final class ServiceState {
    let control: ControlSessionState
    init() throws {
        let hardware = try SMC()
        let journal: ControlJournal
        if FileManager.default.fileExists(atPath: journalURL.path) {
            // A corrupt recovery journal must not silently permit new manual control.
            journal = try JSONDecoder().decode(ControlJournal.self, from: Data(contentsOf: journalURL))
        } else { journal = ControlJournal() }
        let controller = FanController(hardware: hardware, appleSilicon: HardwareInfo.string("machdep.cpu.brand_string").contains("Apple"), journal: journal) {
            try JSONEncoder().encode($0).write(to: journalURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        }
        let reader = SensorReader()
        control = ControlSessionState(controller: controller, sample: { reader.sample() },
                                      thermalState: { ProcessInfo.processInfo.thermalState.rawValue })
        if controller.needsRecovery { recover(reason: .serviceRestart) }
    }
    func recover(reason: RecoveryReason) {
        do { try control.recover(reason: reason) }
        catch { log.error("Automatic recovery pending: \(error.localizedDescription, privacy: .public)") }
    }
    func tick() {
        do { try control.tick() }
        catch { log.error("Automatic recovery pending: \(error.localizedDescription, privacy: .public)") }
    }
}

final class Session: NSObject, FanControlProtocol {
    let id = UUID()
    let state: ServiceState
    init(state: ServiceState) { self.state = state }
    func ping(reply: @escaping (String) -> Void) {
        queue.async {
            let control = self.state.control
            let status = HelperStatus(version: helperVersion, build: helperBuild, ownedByClient: control.owner == self.id,
                                      controlledFans: control.controller.journal.fans.sorted(),
                                      recoveryPending: control.owner == nil && control.controller.needsRecovery,
                                      recoveryReason: control.recoveryReason)
            let data = try? JSONEncoder().encode(status)
            reply(data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        }
    }
    func setManual(fan: Int, rpm: Double, reply: @escaping (String?) -> Void) {
        queue.async {
            do { try self.state.control.manual(session: self.id, fan: fan, rpm: rpm); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func restoreAutomatic(reply: @escaping (String?) -> Void) {
        queue.async {
            do { try self.state.control.restore(session: self.id); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func heartbeat(reply: @escaping (Bool) -> Void) {
        queue.async { reply(self.state.control.heartbeat(session: self.id)) }
    }
    func disconnected() {
        queue.async {
            do { try self.state.control.disconnected(session: self.id) }
            catch { log.error("Automatic recovery pending: \(error.localizedDescription, privacy: .public)") }
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

// launchd may supply a relative BundleProgram as argv[0]. Resolve the loaded
// executable through dyld instead of interpreting argv[0] against its cwd.
var executablePathSize: UInt32 = 0
_ = _NSGetExecutablePath(nil, &executablePathSize)
var executablePath = [CChar](repeating: 0, count: Int(executablePathSize))
guard _NSGetExecutablePath(&executablePath, &executablePathSize) == 0 else {
    fputs("Unable to resolve the helper executable.\n", stderr); exit(1)
}
let bundleURL = URL(fileURLWithPath: String(cString: executablePath)).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
guard let bundle = Bundle(url: bundleURL),
      bundle.bundleIdentifier == ServiceIdentity.app,
      let team = bundle.object(forInfoDictionaryKey: "MacminiSigningTeam") as? String,
      team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
    fputs("Missing signing identity.\n", stderr); exit(1)
}
// Capture the running helper's version once. Replacing an app on disk cannot make
// an old in-memory helper advertise the new executable's version.
let helperVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
let helperBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
// A read-only packaging check; it never opens SMC or starts the control service.
if CommandLine.arguments.dropFirst().contains("--validate-installation") {
    print("Validated helper bundle: \(bundleURL.path)")
    exit(0)
}
guard geteuid() == 0 else { fputs("This service must be launched by macOS ServiceManagement.\n", stderr); exit(1) }
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
    termination.setEventHandler { state.recover(reason: .serviceStopping); exit(0) }
    termination.resume()
    // The daemon stays alive so launchd can restart it and recover the journal after a crash.
    withExtendedLifetime((listener, delegate, timer, termination)) { RunLoop.current.run() }
} catch {
    log.error("Unable to start: \(error.localizedDescription, privacy: .public)")
    exit(1)
}
