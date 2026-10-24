import AppKit
import SwiftUI
import Charts
import FanCore

enum MenuBarTrendIcon {
    static func image(for trend: FanTrend) -> NSImage {
        let paths = trend.segments.map { segment in
            segment.points.compactMap { point -> CGPoint? in
                guard let rpm = point.rpm else { return nil }
                return CGPoint(x: 21 + point.time.timeIntervalSince(trend.start) / 60 * 31,
                               y: 3 + (rpm - trend.lowerBound) / (trend.upperBound - trend.lowerBound) * 12)
            }
        }
        let fan = NSImage(systemSymbolName: "fanblades", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        let image = NSImage(size: NSSize(width: 54, height: 18), flipped: false) { _ in
            fan?.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
            NSColor.black.setStroke()
            NSColor.black.setFill()
            for points in paths {
                guard let first = points.first else { continue }
                if points.count == 1 {
                    NSBezierPath(ovalIn: NSRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2)).fill()
                } else {
                    let path = NSBezierPath()
                    path.lineWidth = 1.4; path.lineJoinStyle = .round; path.lineCapStyle = .round
                    path.move(to: first)
                    for point in points.dropFirst() { path.line(to: point) }
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuTrendChart: View {
    @ObservedObject var model: MonitorModel
    var body: some View {
        let trend = model.menuTrend
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("轉速走勢", systemImage: "waveform.path").font(.subheadline.weight(.medium))
                Spacer()
                Text("最近 1 分鐘").font(.caption).foregroundStyle(.secondary)
            }
            if trend.points.isEmpty {
                Text("正在收集轉速資料…")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                plot(trend).frame(height: 90)
                    .accessibilityLabel("最近一分鐘的實際風扇轉速，橫軸為時間，縱軸為 RPM")
                    .accessibilityValue("最低 \(Format.rpm(trend.minimum))，最高 \(Format.rpm(trend.maximum)) RPM")
            }
            HStack {
                Text("\(Format.rpm(trend.minimum))–\(Format.rpm(trend.maximum)) RPM")
                Spacer()
                Text(model.isStale ? "等待更新" : "每秒更新")
            }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func plot(_ trend: FanTrend) -> some View {
        Chart {
            ForEach(trend.segments) { segment in
                ForEach(segment.points) { point in
                    if let rpm = point.rpm {
                        AreaMark(x: .value("時間", point.time), yStart: .value("基線", trend.lowerBound),
                                 yEnd: .value("轉速", rpm), series: .value("連續資料", segment.id))
                            .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.16), .accentColor.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("時間", point.time), y: .value("轉速", rpm), series: .value("連續資料", segment.id))
                            .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 1.8))
                        if segment.points.count == 1 {
                            PointMark(x: .value("時間", point.time), y: .value("轉速", rpm))
                                .foregroundStyle(Color.accentColor).symbolSize(12)
                        }
                    }
                }
            }
        }
        .chartXScale(domain: trend.start...trend.end)
        .chartYScale(domain: trend.lowerBound...trend.upperBound)
        .chartLegend(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
            AxisValueLabel().font(.system(size: 9))
        } }
        .chartXAxis { AxisMarks(values: [trend.start, trend.end.addingTimeInterval(-30), trend.end]) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    let seconds = Int(trend.end.timeIntervalSince(date).rounded())
                    Text(seconds == 0 ? "現在" : "−\(seconds) 秒").font(.system(size: 9))
                }
            }
        } }
    }
}
