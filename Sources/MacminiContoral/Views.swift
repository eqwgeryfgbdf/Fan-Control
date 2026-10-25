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
    private var columns: [GridItem] {
        (model.snapshot?.fans.count ?? 0) <= 1
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 340), spacing: 20, alignment: .top)]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("風扇轉速").font(.system(size: 30, weight: .semibold))
                        Text(deviceTitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("\(model.snapshot?.fans.count ?? 0) 顆風扇").font(.title3.weight(.medium))
                        Label(model.isStale ? "等待感測器" : "每秒更新", systemImage: model.isStale ? "clock" : "circle.fill")
                            .font(.caption).foregroundStyle(model.isStale ? Color.secondary : Color.accentColor)
                    }
                }
                HStack(spacing: 20) {
                    Picker("顯示範圍", selection: $model.minutes) {
                        Text("1 分鐘").tag(1); Text("5 分鐘").tag(5); Text("15 分鐘").tag(15)
                    }.pickerStyle(.segmented).frame(width: 280)
                    Spacer()
                    Label("CPU \(Format.temperature(model.isStale ? nil : model.snapshot?.cpu.average))", systemImage: "thermometer.medium")
                    Label("GPU \(Format.temperature(model.isStale ? nil : model.snapshot?.gpu.average))", systemImage: "cpu")
                }.font(.callout).monospacedDigit()
                if let error = model.snapshot?.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                if let fans = model.snapshot?.fans, !fans.isEmpty {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(fans.sorted { $0.id < $1.id }) { fan in
                            FanDashboardCard(model: model, control: control, fan: fan)
                        }
                    }
                } else {
                    ContentUnavailableView("尚未偵測到風扇", systemImage: "fanblades", description: Text("取得硬體資料後，這台 Mac 的所有風扇會直接顯示在這裡。"))
                        .frame(minHeight: 300)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(control.health.rawValue, systemImage: control.health == .ready ? "checkmark.circle" : "info.circle")
                        if let message = control.message { Text(message).fixedSize(horizontal: false, vertical: true) }
                    }.font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    SettingsLink { Label("控制設定", systemImage: "gearshape") }
                }
                Divider()
                HStack {
                    if model.historyPaused { Label("圖表已暫停，感測器仍持續更新", systemImage: "pause.circle") }
                    Spacer()
                    Text(model.snapshot?.timestamp ?? model.now, style: .time)
                    Text("· macOS 15+")
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 820, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Remains accessible even when many cards require scrolling.
                Button("全部恢復自動", systemImage: "arrow.counterclockwise") {
                    Task { await model.restoreAllFans() }
                }.disabled(!control.canRestore || control.busy)
                    .help("將此 App 控制的所有風扇交回 macOS 自動調節")
                Button { model.historyPaused.toggle() } label: {
                    Label(model.historyPaused ? "繼續圖表" : "暫停圖表", systemImage: model.historyPaused ? "play" : "pause")
                }.help("暫停圖表記錄；即時監測與風扇控制仍持續運作")
                SettingsLink { Label("設定", systemImage: "gearshape") }
            }
        }
    }
    private var deviceTitle: String {
        guard let s = model.snapshot else { return "正在連接這台 Mac…" }
        let name = s.model == "Mac16,10" || s.model == "Mac16,11" ? "Mac mini" : s.model
        return "\(name) · \(s.chip)"
    }
}

private struct FanDashboardCard: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var control: ControlClient
    let fan: FanReading
    @State private var rpmInput: String
    init(model: MonitorModel, control: ControlClient, fan: FanReading) {
        self.model = model; self.control = control; self.fan = fan
        let initialRPM = [fan.target, fan.minimum].compactMap { $0 }.first {
            (try? ControlPolicy.validate(rpm: $0, fan: fan)) != nil
        }
        _rpmInput = State(initialValue: initialRPM.map { String(Int($0)) } ?? "")
    }
    private var enteredRPM: Double? { FanQuickControl.parse(rpmInput, for: fan) }
    private var canApply: Bool { control.canApply && !model.isStale && (model.snapshot?.thermalState ?? 2) < 2 }
    private var modeText: String {
        if control.recoveryPending && control.ownedFans.contains(fan.id) { return "正在恢復自動" }
        if model.isStale || fan.mode == nil { return "等待硬體狀態" }
        return fan.isAutomatic ? "macOS 自動" : "手動調節"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(fan.name, systemImage: "fanblades").font(.headline)
                Spacer()
                Text(modeText).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.rpm(model.isStale ? nil : fan.rpm)).font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("RPM").foregroundStyle(.secondary)
                Spacer()
            }.monospacedDigit().accessibilityElement(children: .combine)
            chart.frame(height: 210)
            HStack {
                Text("下限 \(Format.rpm(fan.minimum))")
                Spacer()
                Text("上限 \(Format.rpm(fan.maximum)) RPM")
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            controls
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.07)) }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if fan.controllable {
                HStack {
                    Text("目標轉速").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    TextField("目標 RPM", text: $rpmInput)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 76)
                        .accessibilityLabel("\(fan.name)目標轉速，RPM")
                        .onSubmit { if canApply, let rpm = enteredRPM { apply(rpm) } }
                    Text("RPM").font(.caption).foregroundStyle(.secondary)
                    Button("套用") { if let rpm = enteredRPM { apply(rpm) } }
                        .buttonStyle(.borderedProminent).disabled(!canApply || enteredRPM == nil)
                        .accessibilityLabel("套用\(fan.name)轉速")
                }
                HStack(spacing: 8) {
                    Text("快捷").font(.caption).foregroundStyle(.secondary)
                    ForEach(FanQuickControl.presets(for: fan), id: \.self) { rpm in
                        Button("\(Int(rpm))") { rpmInput = String(Int(rpm)); apply(rpm) }
                            .controlSize(.small).disabled(!canApply)
                            .accessibilityLabel("\(fan.name)快速套用 \(Int(rpm)) RPM")
                    }
                }
                if enteredRPM == nil {
                    Text("請輸入 \(Format.rpm(fan.minimum))–\(Format.rpm(fan.maximum)) 的整數轉速。")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("硬體目標 \(Format.rpm(model.isStale ? nil : fan.target)) RPM")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text("尚未取得有效的硬體範圍，暫時無法調速。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(12).modifier(AdaptiveControls())
    }
    private func apply(_ rpm: Double) {
        Task { await model.apply(fanID: fan.id, rpm: rpm) }
    }
    private var chart: some View {
        let points = model.visibleHistory(for: fan.id)
        let values = points.compactMap(\.rpm)
        let low = values.min() ?? 1000
        let high = values.max() ?? 1000
        let padding = max(100, (high-low) * 0.15)
        let end = model.historyEnd
        return Chart {
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
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    let seconds = max(0, Int(end.timeIntervalSince(date)))
                    Text(seconds < (model.minutes == 1 ? 10 : 30) ? "現在" : (model.minutes == 1 ? "−\(seconds) 秒" : "−\(Int((Double(seconds)/60).rounded())) 分鐘"))
                        .fixedSize()
                }
            }
        } }
        .overlay { if values.isEmpty { Text("等待轉速資料").font(.callout).foregroundStyle(.secondary) } }
        .accessibilityLabel("\(fan.name)最近 \(model.minutes) 分鐘的轉速")
    }
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
    @State private var rpmInput = ""
    private var enteredRPM: Double? { model.usableFan.flatMap { FanQuickControl.parse(rpmInput, for: $0) } }
    private var canApply: Bool { control.canApply && !model.isStale && (model.snapshot?.thermalState ?? 2) < 2 }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fan Control").font(.title3.weight(.semibold))
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
            Label(control.health.rawValue, systemImage: control.health == .ready ? "checkmark.circle" : "info.circle")
                .font(.caption).foregroundStyle(.secondary)
            if control.enabled, control.health == .outdated || control.health == .disconnected {
                Button("重新啟動控制服務") { Task { await control.restartService() } }
                    .disabled(!control.canRestart)
            }
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
        .padding(18)
        .frame(width: 380)
        .onAppear { rpmInput = String(Int(model.targetRPM)) }
        .onChange(of: model.targetRPM) { _, rpm in rpmInput = String(Int(rpm)) }
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
        VStack(spacing: 12) {
            Picker("控制模式", selection: Binding(get: { model.manualSelection }, set: { manual in
                if manual { model.manualSelection = true }
                else { Task { await model.automatic() } }
            })) { Text("自動").tag(false); Text("手動").tag(true) }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(control.busy)
            Text(control.recoveryPending ? "正在確認恢復自動" : model.usableFan?.mode == nil ? "等待硬體狀態" : model.usableFan?.isAutomatic == true ? "目前由 macOS 自動調節" : "目前為手動調節")
                .font(.caption).foregroundStyle(.secondary)
            if model.manualSelection, let fan = model.usableFan, fan.controllable, let minimum = fan.minimum, let maximum = fan.maximum {
                HStack {
                    Text("目標轉速")
                    Spacer()
                    TextField("RPM", text: $rpmInput)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 80)
                        .accessibilityLabel("輸入目標轉速，RPM")
                        .onSubmit { if canApply, let rpm = enteredRPM { Task { await model.apply(rpm: rpm) } } }
                    Text("RPM").font(.caption).foregroundStyle(.secondary)
                    Text(control.ownsManual && control.ownedFans.contains(fan.id) && abs((fan.target ?? -1)-(enteredRPM ?? -1000)) < 5 ? "已套用" : "未套用")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    Slider(value: Binding(get: { model.targetRPM }, set: {
                        model.targetRPM = $0; rpmInput = String(Int($0))
                    }), in: minimum...maximum, step: 50).accessibilityLabel("目標風扇轉速")
                        .disabled(control.busy)
                    HStack { Text("\(Format.rpm(minimum)) RPM"); Spacer(); Text("\(Format.rpm(maximum)) RPM") }
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if enteredRPM == nil {
                    Text("請輸入 \(Int(minimum))–\(Int(maximum)) 的整數轉速。")
                        .font(.caption).foregroundStyle(.orange)
                }
                let presets = FanQuickControl.presets(for: fan)
                if !presets.isEmpty {
                    HStack(spacing: 6) {
                        Text("快速套用").font(.caption).foregroundStyle(.secondary)
                        ForEach(presets, id: \.self) { rpm in
                            Button("\(Int(rpm))") {
                                rpmInput = String(Int(rpm))
                                Task { await model.apply(rpm: rpm) }
                            }.help("立即套用 \(Int(rpm)) RPM").accessibilityLabel("快速套用 \(Int(rpm)) RPM")
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }.disabled(!canApply)
                }
                HStack {
                    Button("套用轉速") { if let rpm = enteredRPM { Task { await model.apply(rpm: rpm) } } }
                        .buttonStyle(.borderedProminent).disabled(!canApply || enteredRPM == nil)
                    Button("恢復自動調節") { Task { await model.automatic() } }.buttonStyle(.bordered).disabled(!control.canRestore)
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
    @AppStorage("menuBarShowsRPM") private var menuBarShowsRPM = true
    @AppStorage("menuBarShowsCPU") private var menuBarShowsCPU = true
    @AppStorage("menuBarShowsGPU") private var menuBarShowsGPU = true
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
                LabeledContent("服務狀態", value: control.health.rawValue)
                if let version = control.helperVersion { LabeledContent("控制服務版本", value: version) }
                if !control.enabled {
                    Button(control.requiresApproval ? "開啟系統設定" : "啟用風扇控制") {
                        if control.requiresApproval { control.openApproval() } else { Task { await control.register() } }
                    }.disabled(control.busy)
                } else {
                    Button("重新啟動控制服務") { Task { await control.restartService() } }
                        .disabled(!control.canRestart)
                }
                Text("App 結束、控制連線中斷、讀值持續失效或系統過熱時，控制服務會恢復自動調節。").font(.caption).foregroundStyle(.secondary)
            }
            Section("選單列") {
                Toggle("顯示風扇轉速", isOn: $menuBarShowsRPM)
                Toggle("顯示 CPU 溫度", isOn: $menuBarShowsCPU)
                Toggle("顯示 GPU 溫度", isOn: $menuBarShowsGPU)
                Toggle("選單列顯示迷你走勢圖", isOn: $showMenuBarTrend)
                Text("可依選單列空間選擇顯示項目。關閉所有數字時保留圖示；展開後仍能查看完整讀值與最近一分鐘走勢。").font(.caption).foregroundStyle(.secondary)
            }
            Section("感測器") {
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
