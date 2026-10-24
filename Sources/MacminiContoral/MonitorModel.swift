import AppKit
import Combine
import FanCore

@MainActor final class MonitorModel: ObservableObject {
    static let shared = MonitorModel()
    @Published var snapshot: Snapshot?
    @Published var history: [HistoryPoint] = []
    @Published private(set) var menuHistory: [HistoryPoint] = []
    @Published var selectedFan = 0
    @Published var minutes = 5
    @Published var historyPaused = false
    @Published var manualSelection = false
    @Published var targetRPM = 2000.0
    @Published var now = Date()
    let control = ControlClient()
    private let reader = SensorReader()
    private let queue = DispatchQueue(label: "local.macmini.contoral.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var freshnessClock: AnyCancellable?
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []
    var fan: FanReading? { snapshot?.fans.first { $0.id == selectedFan } }
    var isStale: Bool { snapshot.map { now.timeIntervalSince($0.timestamp) > 3 } ?? true }
    var usableFan: FanReading? { !isStale ? fan : nil }
    var menuTrend: FanTrend { FanTrend(history: menuHistory, fanID: selectedFan, end: now) }
    var visibleHistory: [HistoryPoint] {
        let end = historyPaused ? (history.last?.time ?? now) : now
        return history.filter { $0.fanID == selectedFan && $0.time >= end.addingTimeInterval(-Double(minutes * 60)) }
    }
    var deviceName: String { snapshot?.model.hasPrefix("Mac") == true ? "\(snapshot?.model ?? "Mac") · \(snapshot?.chip ?? "")" : "Mac" }
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(80))
        timer.setEventHandler { [weak self, reader] in
            let sample = reader.sample()
            DispatchQueue.main.async { self?.receive(sample) }
        }
        self.timer = timer; timer.resume()
        freshnessClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            self?.now = date
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.control.restore() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.history.removeAll(); self?.menuHistory.removeAll(); self?.snapshot = nil; self?.manualSelection = false }
        })
    }
    private func receive(_ sample: Snapshot) {
        now = Date(); snapshot = sample; ticks += 1
        if !sample.fans.contains(where: { $0.id == selectedFan }) { selectedFan = sample.fans.first?.id ?? 0 }
        if let fan, fan.controllable, let min = fan.minimum, let max = fan.maximum {
            targetRPM = Swift.min(Swift.max(targetRPM, min), max)
        }
        // Menu bar trends stay live even while the main history chart is paused.
        for fan in sample.fans { menuHistory.append(HistoryPoint(time: sample.timestamp, fanID: fan.id, rpm: fan.rpm)) }
        if sample.fans.isEmpty { menuHistory.append(HistoryPoint(time: sample.timestamp, fanID: selectedFan, rpm: nil)) }
        menuHistory.removeAll { $0.time < now.addingTimeInterval(-60) }
        if menuHistory.count > 610 { menuHistory.removeFirst(menuHistory.count - 610) }
        if !historyPaused {
            for fan in sample.fans { history.append(HistoryPoint(time: sample.timestamp, fanID: fan.id, rpm: fan.rpm)) }
            if sample.fans.isEmpty { history.append(HistoryPoint(time: sample.timestamp, fanID: selectedFan, rpm: nil)) }
            history.removeAll { $0.time < now.addingTimeInterval(-900) }
        }
        if ticks % 3 == 0 { control.heartbeat() }
        if ticks % 5 == 0 { control.refreshStatus() }
    }
    func apply() async {
        guard let fan = usableFan else { return }
        do { try ControlPolicy.validate(rpm: targetRPM, fan: fan) }
        catch { control.message = error.localizedDescription; return }
        await control.apply(fan: fan.id, rpm: targetRPM.rounded())
    }
    func automatic() async {
        manualSelection = false
        if let fan, !fan.isAutomatic, !control.ownsManual {
            control.message = "目前的手動設定不屬於此 App，請在原控制程式恢復自動調節。"
            return
        }
        await control.restore()
    }
    func quit() async {
        await control.restore()
        control.disconnect()
    }
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "monitor" || $0.title == "主機管理-Macmini contoral" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

enum Format {
    static func rpm(_ n: Double?) -> String { n.map { Int($0.rounded()).formatted(.number) } ?? "—" }
    static func temperature(_ n: Double?) -> String { n.map { String(format: "%.0f°C", $0) } ?? "—" }
}
