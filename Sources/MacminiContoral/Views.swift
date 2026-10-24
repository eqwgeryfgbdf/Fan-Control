import SwiftUI
import Charts
import FanCore
import ServiceManagement

private struct AdaptiveControls: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct MonitorView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var control: ControlClient
    @State private var showControl = false
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("風扇轉速").font(.system(size: 30, weight: .semibold))
                    Text(deviceTitle).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.rpm(model.usableFan?.rpm)).font(.system(size: 36, weight: .semibold, design: .rounded))
                        Text("RPM").font(.title3).foregroundStyle(.secondary)
                    }.monospacedDigit()
                    Label(model.isStale ? "等待感測器" : "每秒更新", systemImage: model.isStale ? "clock" : "circle.fill")
                        .font(.caption).foregroundStyle(model.isStale ? Color.secondary : Color.accentColor)
                }
            }
            HStack(spacing: 20) {
                Picker("顯示範圍", selection: $model.minutes) {
                    Text("1 分鐘").tag(1); Text("5 分鐘").tag(5); Text("15 分鐘").tag(15)
                }.pickerStyle(.segmented).frame(width: 300)
                if (model.snapshot?.fans.count ?? 0) > 1 {
                    Picker("風扇", selection: $model.selectedFan) {
                        ForEach(model.snapshot?.fans ?? []) { Text($0.name).tag($0.id) }
                    }.frame(width: 160)
                }
                Spacer()
                Label("CPU \(Format.temperature(model.isStale ? nil : model.snapshot?.cpu.average))", systemImage: "thermometer.medium")
                Label("GPU \(Format.temperature(model.isStale ? nil : model.snapshot?.gpu.average))", systemImage: "cpu")
            }.font(.callout).monospacedDigit()
            if let error = model.snapshot?.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            chart.frame(minHeight: 220, maxHeight: .infinity)
            Divider()
            fanTable
            Divider()
            HStack {
                Text("\(model.snapshot?.fans.count ?? 0) 顆風扇")
                if model.historyPaused { Label("圖表已暫停，感測器仍持續更新", systemImage: "pause.circle") }
                Spacer()
                Text(model.snapshot?.timestamp ?? Date(), style: .time)
                Text("· macOS 15+")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(30)
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 820, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.historyPaused.toggle() } label: {
                    Label(model.historyPaused ? "繼續圖表" : "暫停圖表", systemImage: model.historyPaused ? "play" : "pause")
                }.help("暫停圖表記錄；即時監測與風扇控制仍持續運作")
                Button { showControl.toggle() } label: { Label("風扇控制", systemImage: "fanblades") }
                    .popover(isPresented: $showControl, arrowEdge: .bottom) { MenuPanel(model: model, control: control) }
                SettingsLink { Label("設定", systemImage: "gearshape") }
            }
        }
    }
    private var deviceTitle: String {
        guard let s = model.snapshot else { return "正在連接這台 Mac…" }
        let name = s.model == "Mac16,10" || s.model == "Mac16,11" ? "Mac mini" : s.model
        return "\(name) · \(s.chip)"
    }
    private var chart: some View {
        let points = model.visibleHistory
        let values = points.compactMap(\.rpm)
        let low = values.min() ?? 1000
        let high = values.max() ?? 1000
        let padding = max(20, (high-low) * 0.15)
        let end = model.historyPaused ? (points.last?.time ?? model.now) : model.now
        return VStack(alignment: .leading, spacing: 12) {
            Text("RPM").font(.caption).foregroundStyle(.secondary)
            Chart {
                // Break the line on missing readings and after a paused interval.
                ForEach(chartSegments(points)) { segment in
                    ForEach(segment.points) { point in
                        if let rpm = point.rpm {
                            LineMark(x: .value("時間", point.time), y: .value("轉速", rpm), series: .value("連續資料", segment.id))
                                .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
            }
            .chartYScale(domain: max(0, low-padding)...(high+padding))
            .chartXScale(domain: end.addingTimeInterval(-Double(model.minutes*60))...end)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel() } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        let seconds = max(0, Int(end.timeIntervalSince(date)))
                        Text(seconds < 10 ? "現在" : (model.minutes == 1 ? "−\(seconds) 秒" : "−\(Int((Double(seconds)/60).rounded())) 分鐘"))
                    }
                }
            } }
            .overlay { if values.isEmpty { ContentUnavailableView("等待風扇資料", systemImage: "fanblades", description: Text("取得轉速後，趨勢會自動顯示。")) } }
            .accessibilityLabel("最近 \(model.minutes) 分鐘的風扇轉速")
        }
    }
    private var fanTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
            GridRow {
                tableCell("風扇"); tableCell("目前轉速"); tableCell("硬體下限"); tableCell("硬體上限"); tableCell("模式")
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(model.snapshot?.fans ?? []) { fan in
                GridRow {
                    Label(fan.name, systemImage: "fanblades").frame(maxWidth: .infinity, alignment: .leading)
                    tableCell("\(Format.rpm(model.isStale ? nil : fan.rpm)) RPM")
                    tableCell("\(Format.rpm(fan.minimum)) RPM")
                    tableCell("\(Format.rpm(fan.maximum)) RPM")
                    tableCell(fan.mode == nil ? "未知" : fan.isAutomatic ? "自動" : "手動")
                }.monospacedDigit()
            }
        }.padding(.vertical, 8)
    }
    private func tableCell(_ text: String) -> some View { Text(text).frame(maxWidth: .infinity, alignment: .leading) }
}

private struct ChartSegment: Identifiable { let id: Int; let points: [HistoryPoint] }
private func chartSegments(_ points: [HistoryPoint]) -> [ChartSegment] {
    var groups: [[HistoryPoint]] = []; var current: [HistoryPoint] = []
    for point in points {
        if point.rpm == nil || (current.last.map { point.time.timeIntervalSince($0.time) > 3 } ?? false) {
            if !current.isEmpty { groups.append(current); current = [] }
        }
        if point.rpm != nil { current.append(point) }
    }
    if !current.isEmpty { groups.append(current) }
    return groups.enumerated().map { ChartSegment(id: $0.offset, points: $0.element) }
}

struct MenuPanel: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var control: ControlClient
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("風扇管理 Fan Control").font(.title3.weight(.semibold))
            VStack(spacing: 13) {
                metric("目前轉速", icon: "fanblades", value: "\(Format.rpm(model.usableFan?.rpm)) RPM")
                metric("CPU 平均", icon: "thermometer.medium", value: Format.temperature(model.isStale ? nil : model.snapshot?.cpu.average))
                metric("GPU 平均", icon: "cpu", value: Format.temperature(model.isStale ? nil : model.snapshot?.gpu.average))
                Text("可用感測器平均").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            MenuTrendChart(model: model)
            Divider()
            if (model.snapshot?.fans.count ?? 0) > 1 {
                Picker("風扇", selection: $model.selectedFan) { ForEach(model.snapshot?.fans ?? []) { Text($0.name).tag($0.id) } }
            }
            controls
            if !control.enabled {
                VStack(alignment: .leading, spacing: 10) {
                    Button(control.requiresApproval ? "前往系統設定允許" : "啟用風扇控制") {
                        if control.requiresApproval { control.openApproval() }
                        else { Task { await control.register() } }
                    }.buttonStyle(.borderedProminent).disabled(control.busy)
                    Text("macOS 會要求管理員授權。監測功能不需授權。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if control.busy { ProgressView("正在確認控制設定…").controlSize(.small).font(.caption) }
            if let message = control.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.snapshot?.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                Button { openWindow(id: "monitor"); model.showMainWindow() } label: { Label("開啟主視窗", systemImage: "macwindow") }
                    .buttonStyle(.plain)
                Spacer()
                SettingsLink { Image(systemName: "gearshape").font(.title3) }.buttonStyle(.plain).help("設定")
            }
            HStack {
                Text(model.isStale ? "資料尚未更新" : "每秒更新").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("結束") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
    private func metric(_ title: String, icon: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).font(.title3)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
    }
    private var controls: some View {
        VStack(spacing: 16) {
            Picker("控制模式", selection: $model.manualSelection) { Text("自動").tag(false); Text("手動").tag(true) }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.manualSelection) { _, manual in if !manual && !control.busy { Task { await model.automatic() } } }
                .disabled(control.busy)
            if model.manualSelection, let fan = model.usableFan, fan.controllable, let minimum = fan.minimum, let maximum = fan.maximum {
                HStack {
                    Text("目標轉速")
                    Spacer()
                    Text("\(Format.rpm(model.targetRPM)) RPM").monospacedDigit()
                    Text(control.ownsManual && abs((fan.target ?? -1)-model.targetRPM) < 5 ? "已套用" : "未套用")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    Slider(value: $model.targetRPM, in: minimum...maximum, step: 50).accessibilityLabel("目標風扇轉速")
                        .disabled(control.busy)
                    HStack { Text("\(Format.rpm(minimum)) RPM"); Spacer(); Text("\(Format.rpm(maximum)) RPM") }
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Button("套用轉速") { Task { await model.apply() } }.buttonStyle(.borderedProminent).disabled(!control.enabled)
                    Button("恢復自動調節") { Task { await model.automatic() } }.buttonStyle(.bordered).disabled(!control.ownsManual)
                }.disabled(control.busy)
            } else if model.manualSelection {
                Text("尚未取得有效的硬體範圍，暫時無法調速。").font(.callout).foregroundStyle(.secondary)
            } else {
                Label(model.usableFan?.isAutomatic == true ? "由 macOS 自動調節風扇" : "\(model.usableFan?.mode == nil ? "等待控制狀態" : "目前為手動調節")", systemImage: "fanblades").font(.callout).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).modifier(AdaptiveControls())
    }
}

struct SettingsView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var control: ControlClient
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage("showMenuBarTrend") private var showMenuBarTrend = true
    var body: some View {
        Form {
            Section("一般") {
                Toggle("登入時啟動", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                Text("關閉主視窗後，選單列仍會持續監測。").foregroundStyle(.secondary)
                if let loginError { Text(loginError).foregroundStyle(.orange) }
            }
            Section("風扇控制") {
                LabeledContent("服務狀態", value: control.enabled ? "已啟用" : control.requiresApproval ? "等待系統授權" : "尚未啟用")
                if !control.enabled {
                    Button(control.requiresApproval ? "開啟系統設定" : "啟用風扇控制") {
                        if control.requiresApproval { control.openApproval() } else { Task { await control.register() } }
                    }.disabled(control.busy)
                } else {
                    Button("重新啟動控制服務") { Task { await control.restartService() } }
                        .disabled(control.busy || control.ownsManual)
                }
                Text("App 結束、控制連線中斷或系統過熱時，控制服務會恢復自動調節。").font(.caption).foregroundStyle(.secondary)
            }
            Section("顯示與感測器") {
                Toggle("選單列顯示迷你走勢圖", isOn: $showMenuBarTrend)
                Text("顯示最近一分鐘的實際轉速；展開選單列可查看完整走勢。").font(.caption).foregroundStyle(.secondary)
                LabeledContent("更新頻率", value: "每秒一次")
                LabeledContent("CPU 感測器", value: "\(model.snapshot?.cpu.sensorCount ?? 0) 個")
                LabeledContent("GPU 感測器", value: "\(model.snapshot?.gpu.sensorCount ?? 0) 個")
                Text("CPU、GPU 顯示各自可讀取感測器的平均值，並非機殼或室溫。未支援的感測器會顯示 —。").font(.caption).foregroundStyle(.secondary)
                Text("macOS 26 以上適量使用 Liquid Glass；macOS 15 使用標準材質，並遵循系統的減少透明度設定。").font(.caption).foregroundStyle(.secondary)
            }
            if let message = control.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 500, height: 530).padding(8)
        .onAppear { control.refreshStatus() }
    }
}
