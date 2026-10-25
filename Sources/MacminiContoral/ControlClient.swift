import Foundation
import ServiceManagement
import FanCore

private final class ReplyGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Value, Error>
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; lock.unlock()
        continuation.resume(with: result)
    }
}

enum ServiceHealth: String {
    case unavailable = "尚未啟用", approval = "等待系統授權", checking = "正在檢查連線"
    case ready = "可調速", disconnected = "控制服務無法連線", outdated = "控制服務需要更新"
    case recovering = "正在恢復自動", inUse = "另一個 App 正在控制"
}

@MainActor final class ControlClient: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var health: ServiceHealth = .unavailable
    @Published private(set) var helperVersion: String?
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var ownsManual = false
    @Published private(set) var recoveryPending = false
    @Published private(set) var ownedFans: Set<Int> = []
    var canApply: Bool { health == .ready && verifiedConnectionID == connectionID && !busy && !recoveryPending }
    var canRestore: Bool { ownsManual || recoveryPending }
    var canRestart: Bool { enabled && !busy && !ownsManual && health != .inUse }
    private var connection: NSXPCConnection?
    private var connectionID = UUID()
    private var verifiedConnectionID: UUID?
    private var revision = 0
    private var checking = false
    private let service = SMAppService.daemon(plistName: ServiceIdentity.plist)
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

    init() { refreshStatus() }
    func refreshStatus() {
        enabled = service.status == .enabled
        requiresApproval = service.status == .requiresApproval
        if !enabled {
            if connection != nil { disconnect() }
            health = recoveryPending ? .recovering : requiresApproval ? .approval : .unavailable
        } else if !busy {
            Task { await checkHealth() }
        }
    }
    func register() async {
        guard !busy else { return }
        busy = true; message = nil; revision += 1
        do {
            try await Task.detached { try SMAppService.daemon(plistName: ServiceIdentity.plist).register() }.value
        } catch { message = "無法啟用控制服務：\(error.localizedDescription)" }
        busy = false; refreshStatus()
        if requiresApproval {
            message = "請在系統設定的登入項目中允許 風扇管理 Fan Control。"
            SMAppService.openSystemSettingsLoginItems()
        }
    }
    func openApproval() { SMAppService.openSystemSettingsLoginItems() }
    func restartService() async {
        guard canRestart else { return }
        busy = true; message = nil; revision += 1
        disconnect()
        do {
            try await service.unregister()
            try await Task.sleep(for: .seconds(1))
            try await Task.detached { try SMAppService.daemon(plistName: ServiceIdentity.plist).register() }.value
            message = "控制服務已重新註冊，正在確認連線。"
        } catch { message = "無法重新啟動控制服務：\(error.localizedDescription)" }
        busy = false; refreshStatus()
    }
    private func connect() throws -> NSXPCConnection {
        guard service.status == .enabled else { throw MonitorError.message("請先啟用風扇控制服務。") }
        if let connection { return connection }
        guard let team = Bundle.main.object(forInfoDictionaryKey: "MacminiSigningTeam") as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw MonitorError.message("此版本未正確簽署，僅能讀取感測器。")
        }
        let conn = NSXPCConnection(machServiceName: ServiceIdentity.helper, options: .privileged)
        let id = UUID(); connectionID = id; verifiedConnectionID = nil
        conn.setCodeSigningRequirement(ServiceIdentity.requirement(identifier: ServiceIdentity.helper, team: team))
        conn.remoteObjectInterface = NSXPCInterface(with: FanControlProtocol.self)
        conn.interruptionHandler = { [weak self] in Task { @MainActor in self?.lostConnection(id: id) } }
        conn.invalidationHandler = { [weak self] in Task { @MainActor in self?.lostConnection(id: id) } }
        conn.resume(); connection = conn
        return conn
    }
    private func lostConnection(id: UUID) {
        guard connectionID == id else { return }
        let wasManual = ownsManual || recoveryPending
        disconnect()
        health = wasManual ? .recovering : .disconnected
        message = wasManual ? "控制連線中斷，正在確認自動恢復。" : "無法連線至控制服務，監測仍可使用。"
    }
    private func request<Value>(on conn: NSXPCConnection, timeout: Double,
                                action: @escaping (FanControlProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate<Value>(continuation)
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ gate.finish(.failure($0)) }) as? FanControlProtocol else {
                gate.finish(.failure(MonitorError.message("無法連線至風扇控制服務。"))); return
            }
            action(proxy) { gate.finish($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.finish(.failure(MonitorError.message("控制服務回應逾時。")))
            }
        }
    }
    func checkHealth() async {
        guard enabled, !busy, !checking else { return }
        checking = true
        defer { checking = false }
        if health == .unavailable || health == .disconnected { health = .checking }
        let startRevision = revision
        do {
            let conn = try connect()
            let id = connectionID
            let reply: String = try await request(on: conn, timeout: 4) { proxy, finish in
                proxy.ping { finish(.success($0)) }
            }
            guard revision == startRevision, connectionID == id, !busy else { return }
            guard let data = reply.data(using: .utf8), let status = try? JSONDecoder().decode(HelperStatus.self, from: data),
                  status.matches(version: version, build: build) else {
                health = .outdated; helperVersion = nil; verifiedConnectionID = nil
                message = "請從安裝位置開啟新版，並在設定重新啟動控制服務。"
                return
            }
            helperVersion = "\(status.version)（\(status.build)）"
            verifiedConnectionID = id
            let hadControl = ownsManual || recoveryPending
            ownsManual = status.ownedByClient
            recoveryPending = status.recoveryPending
            ownedFans = status.ownedByClient || status.recoveryPending ? Set(status.controlledFans) : []
            health = status.recoveryPending ? .recovering : (!status.ownedByClient && !status.controlledFans.isEmpty ? .inUse : .ready)
            if hadControl && !status.ownedByClient {
                message = status.recoveryPending ? "自動恢復尚未完成，控制服務會持續重試。" : status.recoveryReason?.message ?? "已恢復自動調節。"
            } else if health == .ready, message == "控制服務已重新註冊，正在確認連線。" {
                message = "控制服務連線與版本已確認。"
            }
        } catch {
            guard revision == startRevision else { return }
            lostConnection(id: connectionID)
        }
    }
    private func perform(_ action: @escaping (FanControlProtocol, @escaping (String?) -> Void) -> Void) async throws {
        let conn = try connect()
        let id = connectionID
        do {
            let _: Void = try await request(on: conn, timeout: 35) { proxy, finish in
                action(proxy) { error in
                    if let error { finish(.failure(MonitorError.message(error))) } else { finish(.success(())) }
                }
            }
        } catch {
            lostConnection(id: id)
            throw error
        }
    }
    func apply(fan: Int, rpm: Double) async {
        guard canApply else { message = "控制服務尚未就緒，請先確認服務狀態。"; return }
        busy = true; message = nil; revision += 1
        // Keep a candidate fan until recovery is verified even if the reply is lost.
        ownedFans.insert(fan)
        defer { busy = false; refreshStatus() }
        do {
            try await perform { $0.setManual(fan: fan, rpm: rpm, reply: $1) }
            ownsManual = true; recoveryPending = false
            message = "目標已確認：\(Int(rpm)) RPM。實際轉速會逐步調整。"
        } catch {
            recoveryPending = true; health = .recovering
            message = "\(error.localizedDescription) 正在確認自動恢復。"
        }
    }
    @discardableResult func restore() async -> Bool {
        guard !busy else { return false }
        guard connection != nil || canRestore else { return true }
        busy = true; recoveryPending = true; health = .recovering; revision += 1
        message = "正在恢復自動調節…"
        defer { busy = false; refreshStatus() }
        do {
            try await perform { $0.restoreAutomatic(reply: $1) }
            ownsManual = false; recoveryPending = false; ownedFans.removeAll()
            health = verifiedConnectionID == connectionID ? .ready : .checking
            message = "已恢復自動調節。"
            return true
        } catch { message = "自動恢復尚未確認：\(error.localizedDescription)"; return false }
    }
    func heartbeat() {
        guard let connection, ownsManual, !recoveryPending else { return }
        let id = connectionID
        let remote = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in self?.lostConnection(id: id) }
        } as? FanControlProtocol
        remote?.heartbeat { [weak self] owns in Task { @MainActor in
            guard let self, self.connectionID == id, !self.busy else { return }
            if !owns {
                self.ownsManual = false; self.recoveryPending = true; self.health = .recovering
                await self.checkHealth()
            }
        } }
    }
    func disconnect() {
        revision += 1
        connectionID = UUID()
        let old = connection; connection = nil
        recoveryPending = recoveryPending || ownsManual
        ownsManual = false; helperVersion = nil; verifiedConnectionID = nil
        old?.invalidate()
    }
}
