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

@main struct MacminiContoralApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MonitorModel.shared
    var body: some Scene {
        Window("主機管理-Macmini contoral", id: "monitor") {
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
                Text("\(Format.rpm(model.usableFan?.rpm)) RPM · \(Format.temperature(model.isStale ? nil : model.snapshot?.cpu.average))")
                    .monospacedDigit()
            } icon: { Image(systemName: "fanblades") }
                .accessibilityLabel("Macmini contoral，風扇轉速與 CPU 溫度")
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView(model: model, control: model.control) }
    }
}
