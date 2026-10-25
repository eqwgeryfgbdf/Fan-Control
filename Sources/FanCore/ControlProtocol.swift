import Foundation

public enum ServiceIdentity {
    public static let protocolVersion = 2
    public static let app = "local.macmini.contoral"
    public static let helper = "local.macmini.contoral.helper"
    public static let plist = "local.macmini.contoral.helper.plist"
    public static func requirement(identifier: String, team: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
}

public struct HelperStatus: Codable, Equatable {
    public let protocolVersion: Int
    public let version: String
    public let build: String
    public let ownedByClient: Bool
    public let controlledFans: [Int]
    public let recoveryPending: Bool
    public let recoveryReason: RecoveryReason?

    public init(version: String, build: String, ownedByClient: Bool, controlledFans: [Int],
                recoveryPending: Bool, recoveryReason: RecoveryReason?, protocolVersion: Int = ServiceIdentity.protocolVersion) {
        self.protocolVersion = protocolVersion; self.version = version; self.build = build
        self.ownedByClient = ownedByClient; self.controlledFans = controlledFans
        self.recoveryPending = recoveryPending; self.recoveryReason = recoveryReason
    }
    public func matches(version: String, build: String) -> Bool {
        protocolVersion == ServiceIdentity.protocolVersion && self.version == version && self.build == build
    }
}

@objc public protocol FanControlProtocol {
    func ping(reply: @escaping (String) -> Void)
    func setManual(fan: Int, rpm: Double, reply: @escaping (String?) -> Void)
    func restoreAutomatic(reply: @escaping (String?) -> Void)
    func heartbeat(reply: @escaping (Bool) -> Void)
}
