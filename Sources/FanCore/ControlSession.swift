import Foundation

public enum RecoveryReason: String, Codable {
    case requested, connectionLost, leaseExpired, thermal, sensors, serviceRestart, serviceStopping
    public var message: String {
        switch self {
        case .requested: return "已恢復自動調節。"
        case .connectionLost: return "控制連線中斷，已恢復自動調節。"
        case .leaseExpired: return "控制連線逾時，已恢復自動調節。"
        case .thermal: return "系統需要降溫，已恢復自動調節。"
        case .sensors: return "感測器讀值持續失效，已恢復自動調節。"
        case .serviceRestart: return "控制服務重新啟動，已恢復自動調節。"
        case .serviceStopping: return "控制服務已停止，已恢復自動調節。"
        }
    }
}

/// Used only on the helper's serial queue. The helper independently checks sensors;
/// a responsive UI and valid heartbeats cannot conceal a persistent sensor failure.
public final class ControlSessionState {
    public let controller: FanController
    public private(set) var owner: UUID?
    public private(set) var recoveryReason: RecoveryReason?
    private var lastHeartbeat: TimeInterval = 0
    private var invalidSince: TimeInterval?
    private var requiresCPU = false
    private var requiresGPU = false
    private let sample: () -> Snapshot
    private let thermalState: () -> Int
    private let clock: () -> TimeInterval
    public static let sensorFailureSeconds: TimeInterval = 3

    public init(controller: FanController, sample: @escaping () -> Snapshot,
                thermalState: @escaping () -> Int, clock: @escaping () -> TimeInterval = { ControlClock.now }) {
        self.controller = controller; self.sample = sample; self.thermalState = thermalState; self.clock = clock
    }

    private func readable(_ snapshot: Snapshot, fans: Set<Int>) -> Bool {
        guard !fans.isEmpty, !requiresCPU || snapshot.cpu.average != nil,
              !requiresGPU || snapshot.gpu.average != nil else { return false }
        return fans.allSatisfy { id in
            guard let fan = snapshot.fans.first(where: { $0.id == id }), fan.controllable,
                  let rpm = fan.rpm, rpm.isFinite, rpm >= 0, rpm < 20_000,
                  let mode = fan.mode, [0, 1, 3].contains(mode),
                  let target = fan.target, target.isFinite, target >= 0, target < 20_000 else { return false }
            return true
        }
    }

    public func manual(session: UUID, fan: Int, rpm: Double) throws {
        guard owner == nil || owner == session else { throw MonitorError.message("另一個 App 連線正在控制風扇。") }
        guard !(owner == nil && controller.needsRecovery) else {
            throw MonitorError.message("自動恢復尚未完成，請稍候再調速。")
        }
        guard thermalState() < ProcessInfo.ThermalState.serious.rawValue else {
            try recover(reason: .thermal)
            throw MonitorError.message("系統正在降溫，請使用自動調節。")
        }
        let current = sample()
        guard readable(current, fans: controller.journal.fans.union([fan])) else {
            throw MonitorError.message("無法確認風扇或溫度讀值，暫時無法調速。")
        }
        do {
            try controller.manual(fan: fan, rpm: rpm)
            // Remember available temperature families for the whole manual session.
            // Unsupported temperature families do not prevent fan-only monitoring.
            requiresCPU = requiresCPU || current.cpu.average != nil
            requiresGPU = requiresGPU || current.gpu.average != nil
            owner = session; lastHeartbeat = clock(); invalidSince = nil; recoveryReason = nil
        } catch {
            if !controller.needsRecovery { clearSession() }
            else { owner = nil }
            throw error
        }
    }

    public func restore(session: UUID) throws {
        guard owner == nil || owner == session else { throw MonitorError.message("另一個 App 連線正在控制風扇。") }
        try recover(reason: .requested)
    }

    public func heartbeat(session: UUID) -> Bool {
        if owner == session { lastHeartbeat = clock(); return true }
        return false
    }

    public func disconnected(session: UUID) throws {
        if owner == session { try recover(reason: .connectionLost) }
    }

    public func recover(reason: RecoveryReason) throws {
        // Revoke the lease before attempting recovery. A failed restore must remain
        // retryable even if the former client continues sending heartbeats.
        owner = nil; recoveryReason = reason
        try controller.restore()
        clearSession()
    }

    private func clearSession() {
        owner = nil; invalidSince = nil; requiresCPU = false; requiresGPU = false
    }

    public func tick() throws {
        guard controller.needsRecovery else { return }
        if owner == nil { try recover(reason: recoveryReason ?? .serviceRestart); return }
        if thermalState() >= ProcessInfo.ThermalState.serious.rawValue { try recover(reason: .thermal); return }
        let now = clock()
        if ControlPolicy.expired(lastHeartbeat: lastHeartbeat, now: now) { try recover(reason: .leaseExpired); return }
        let current = sample()
        if readable(current, fans: controller.journal.fans) {
            requiresCPU = requiresCPU || current.cpu.average != nil
            requiresGPU = requiresGPU || current.gpu.average != nil
            invalidSince = nil
        } else {
            if invalidSince == nil { invalidSince = now }
            if now - (invalidSince ?? now) >= Self.sensorFailureSeconds { try recover(reason: .sensors) }
        }
    }
}
