import SwiftUI

// MARK: - ThroughputChartView

/// Area chart showing the last N throughput readings.
/// Canvas draws: 3 grid lines · filled area · stroke line · x-axis labels · peak annotation.
struct ThroughputChartView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.cortexTheme) private var t

    private var data: [Double] { serverState.throughputHistory }
    private var peak: Double   { data.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                Text("THROUGHPUT")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.08 * 9.5)
                    .foregroundStyle(t.lbl)
                Spacer()
                // Peak annotation
                if peak > 0 {
                    Text("↑ \(String(format: "%.1f", peak)) t/s peak")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(t.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 6)

            // Chart canvas
            GeometryReader { geo in
                let chartW = geo.size.width
                let chartH: CGFloat = 58
                ZStack(alignment: .topLeading) {
                    ThroughputCanvas(
                        data: data,
                        accentColor: t.accent,
                        gridColor: t.bd
                    )
                    .frame(width: chartW, height: chartH)
                }
                .frame(width: chartW, height: chartH)
            }
            .frame(height: 58)
            .padding(.horizontal, 14)

            // X-axis labels
            HStack {
                ForEach(xLabels, id: \.self) { lbl in
                    Text(lbl)
                        .font(.system(size: 8.5).monospacedDigit())
                        .foregroundStyle(t.t5)
                    if lbl != xLabels.last { Spacer() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 11)
        }
    }

    private var xLabels: [String] {
        // 7 evenly-spaced labels from oldest to Now
        let count = max(data.count, 1)
        let step  = count / 6
        var labels: [String] = []
        for i in 0..<6 {
            let idx = i * step
            labels.append(timeLabel(offsetFromEnd: count - 1 - idx))
        }
        labels.append("Now")
        return labels
    }

    private func timeLabel(offsetFromEnd: Int) -> String {
        let secondsAgo = offsetFromEnd * 2          // 2-second polling interval
        let date = Date().addingTimeInterval(TimeInterval(-secondsAgo))
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - ThroughputCanvas

private struct ThroughputCanvas: View {
    let data: [Double]
    let accentColor: Color
    let gridColor: Color

    var body: some View {
        Canvas { ctx, size in
            // Grid lines at 25 / 50 / 75 %
            for frac in [0.25, 0.50, 0.75] as [Double] {
                let y = size.height * (1 - frac)
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: 0, y: y))
                gridLine.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(gridLine, with: .color(gridColor),
                           style: StrokeStyle(lineWidth: 1))
            }

            guard data.count > 1 else { return }

            let maxV  = data.max() ?? 1
            let minV: Double = 0
            let range = maxV - minV > 0 ? maxV - minV : 1
            let step  = size.width / CGFloat(data.count - 1)

            var linePath = Path()
            var areaPath = Path()

            for (i, v) in data.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (CGFloat(v - minV) / CGFloat(range)) * size.height
                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    areaPath.move(to: CGPoint(x: 0, y: size.height))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
            areaPath.closeSubpath()

            // Area fill: accent 22% → accent 1%
            ctx.drawLayer { layerCtx in
                layerCtx.fill(areaPath, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: accentColor.opacity(0.22), location: 0),
                        .init(color: accentColor.opacity(0.01), location: 1),
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint:   CGPoint(x: 0, y: size.height)
                ))
            }

            ctx.stroke(linePath, with: .color(accentColor),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    ThroughputChartView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 468)
        .background(Color(hex: "#1c1d26"))
}
