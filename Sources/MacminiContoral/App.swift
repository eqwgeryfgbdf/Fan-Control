import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await MonitorModel.shared.quit(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MonitorModel.shared.showMainWindow(); return true
    }
}

@main struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MonitorModel.shared
    @AppStorage("showMenuBarTrend") private var showMenuBarTrend = true
    @AppStorage("menuBarShowsRPM") private var menuBarShowsRPM = true
    @AppStorage("menuBarShowsCPU") private var menuBarShowsCPU = true
    @AppStorage("menuBarShowsGPU") private var menuBarShowsGPU = true
    private var menuBarText: String {
        var parts: [String] = []
        if menuBarShowsRPM { parts.append("\(Format.rpm(model.usableFan?.rpm)) RPM") }
        if menuBarShowsCPU { parts.append("CPU \(Format.temperature(model.isStale ? nil : model.snapshot?.cpu.average))") }
        if menuBarShowsGPU { parts.append("GPU \(Format.temperature(model.isStale ? nil : model.snapshot?.gpu.average))") }
        return parts.joined(separator: " · ")
    }
    var body: some Scene {
        Window("風扇管理 Fan Control", id: "monitor") {
            MonitorView(model: model, control: model.control)
                .task { model.start() }
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("顯示監測視窗") { model.showMainWindow() }.keyboardShortcut("1")
            }
        }
        MenuBarExtra {
            MenuPanel(model: model, control: model.control).task { model.start() }
        } label: {
            Label {
                Text(menuBarText)
                    .monospacedDigit()
            } icon: {
                if showMenuBarTrend, !model.isStale, !model.menuTrend.points.isEmpty {
                    Image(nsImage: MenuBarTrendIcon.image(for: model.menuTrend))
                } else { Image(systemName: "fanblades") }
            }
                .accessibilityLabel("風扇管理 Fan Control，即時風扇與溫度監測")
                .accessibilityValue("\(Format.rpm(model.usableFan?.rpm)) RPM，CPU \(Format.temperature(model.isStale ? nil : model.snapshot?.cpu.average))，GPU \(Format.temperature(model.isStale ? nil : model.snapshot?.gpu.average))")
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView(model: model, control: model.control) }
    }
}
