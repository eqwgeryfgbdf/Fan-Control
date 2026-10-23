import Foundation
import ServiceManagement
import FanCore

private final class ReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Error>
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ message: String?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; lock.unlock()
        if let message { continuation.resume(throwing: MonitorError.message(message)) }
        else { continuation.resume() }
    }
}

@MainActor final class ControlClient: ObservableObject {
    @Published var enabled = false
    @Published var requiresApproval = false
    @Published var busy = false
    @Published var message: String?
    @Published var ownsManual = false
    private var connection: NSXPCConnection?
    private let service = SMAppService.daemon(plistName: ServiceIdentity.plist)
    init() { refreshStatus() }
    func refreshStatus() {
        enabled = service.status == .enabled
        requiresApproval = service.status == .requiresApproval
        if !enabled { connection?.invalidate(); connection = nil; ownsManual = false }
    }
    func register() async {
        busy = true; message = nil
        defer { busy = false; refreshStatus() }
        do {
            try await Task.detached { try SMAppService.daemon(plistName: ServiceIdentity.plist).register() }.value
            refreshStatus()
            if requiresApproval {
                message = "請在系統設定的登入項目中允許 Macmini contoral。"
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            refreshStatus()
            if requiresApproval {
                message = "請在系統設定的登入項目中允許 Macmini contoral。"
                SMAppService.openSystemSettingsLoginItems()
            } else { message = "無法啟用控制服務：\(error.localizedDescription)" }
        }
    }
    func openApproval() { SMAppService.openSystemSettingsLoginItems() }
    private func connect() throws -> NSXPCConnection {
        refreshStatus()
        guard enabled else { throw MonitorError.message("請先啟用風扇控制服務。") }
        if let connection { return connection }
        guard let team = Bundle.main.object(forInfoDictionaryKey: "MacminiSigningTeam") as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw MonitorError.message("此版本未正確簽署，僅能讀取感測器。")
        }
        let conn = NSXPCConnection(machServiceName: ServiceIdentity.helper, options: .privileged)
        conn.setCodeSigningRequirement(ServiceIdentity.requirement(identifier: ServiceIdentity.helper, team: team))
        conn.remoteObjectInterface = NSXPCInterface(with: FanControlProtocol.self)
        conn.interruptionHandler = { [weak self] in Task { @MainActor in
            self?.connection?.invalidate(); self?.connection = nil; self?.ownsManual = false
            self?.message = "控制服務連線中斷，正在恢復自動調節。"
        } }
        conn.resume(); connection = conn
        return conn
    }
    private func perform(_ action: @escaping (FanControlProtocol, @escaping (String?) -> Void) -> Void) async throws {
        let conn = try connect()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ReplyGate(continuation)
                guard let proxy = conn.remoteObjectProxyWithErrorHandler({ gate.finish($0.localizedDescription) }) as? FanControlProtocol else {
                    gate.finish("無法連線至風扇控制服務。"); return
                }
                action(proxy) { gate.finish($0) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 35) {
                    gate.finish("控制服務逾時；連線將關閉並恢復自動調節。")
                }
            }
        } catch {
            conn.invalidate(); connection = nil; ownsManual = false
            throw error
        }
    }
    func apply(fan: Int, rpm: Double) async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await perform { $0.setManual(fan: fan, rpm: rpm, reply: $1) }
            ownsManual = true
            message = "目標已確認：\(Int(rpm)) RPM。實際轉速會逐步調整。"
        } catch { message = error.localizedDescription }
    }
    func restore() async {
        guard connection != nil || ownsManual else { return }
        busy = true
        defer { busy = false }
        do {
            try await perform { $0.restoreAutomatic(reply: $1) }
            ownsManual = false; message = "已恢復自動調節。"
        } catch { message = "自動恢復尚未確認：\(error.localizedDescription)" }
    }
    func heartbeat() {
        guard let connection, ownsManual else { return }
        let remote = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in
                self?.connection?.invalidate(); self?.connection = nil; self?.ownsManual = false
                self?.message = "控制服務連線中斷，正在恢復自動調節。"
            }
        } as? FanControlProtocol
        remote?.heartbeat { [weak self] owns in Task { @MainActor in
            if !owns, self?.busy == false { self?.ownsManual = false }
        } }
    }
    func disconnect() { connection?.invalidate(); connection = nil; ownsManual = false }
}
