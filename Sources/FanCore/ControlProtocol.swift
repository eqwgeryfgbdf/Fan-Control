import Foundation

public enum ServiceIdentity {
    public static let app = "local.macmini.contoral"
    public static let helper = "local.macmini.contoral.helper"
    public static let plist = "local.macmini.contoral.helper.plist"
    public static func requirement(identifier: String, team: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
}

@objc public protocol FanControlProtocol {
    func ping(reply: @escaping (String) -> Void)
    func setManual(fan: Int, rpm: Double, reply: @escaping (String?) -> Void)
    func restoreAutomatic(reply: @escaping (String?) -> Void)
    func heartbeat(reply: @escaping (Bool) -> Void)
}
