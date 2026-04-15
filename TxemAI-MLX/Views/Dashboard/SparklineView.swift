import SwiftUI

/// Dos sparklines en tiempo real: tokens/s y memory pressure.
/// Muestran los últimos 60 segundos de datos.
struct SparklineRowView: View {
    @EnvironmentObject var serverState: ServerStateViewModel

    var body: some View {
        HStack(spacing: 8) {
            SparklineCard(
                title: "tokens/s — last 60s",
                value: String(format: "%.1f t/s", serverState.metrics.tokensPerSecond),
                dataPoints: serverState.metricsHistory.map(\.tokensPerSecond),
                color: Color(red: 0.498, green: 0.467, blue: 0.867)
            )
            SparklineCard(
                title: "memory pressure",
                value: String(format: "%.0f%%", serverState.metrics.memoryPressurePercent),
                dataPoints: serverState.metricsHistory.map(\.memoryPressurePercent),
                color: Color(red: 0.114, green: 0.620, blue: 0.459)
            )
        }
    }
}

/// Tarjeta con mini gráfica de línea (sparkline) usando Canvas.
struct SparklineCard: View {
    let title: String
    let value: String
    let dataPoints: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium))
            }
            SparklineCanvas(dataPoints: dataPoints, color: color)
                .frame(height: 36)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Canvas que dibuja la línea de la sparkline y el área bajo ella.
struct SparklineCanvas: View {
    let dataPoints: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard dataPoints.count > 1 else { return }
            let max = dataPoints.max() ?? 1
            let min = dataPoints.min() ?? 0
            let range = max - min > 0 ? max - min : 1
            let step = size.width / CGFloat(dataPoints.count - 1)

            var linePath = Path()
            var areaPath = Path()

            for (i, point) in dataPoints.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - ((CGFloat(point) - CGFloat(min)) / CGFloat(range)) * size.height
                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    areaPath.move(to: CGPoint(x: x, y: size.height))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
            areaPath.closeSubpath()

            context.stroke(linePath, with: .color(color), lineWidth: 1.5)
            context.fill(areaPath, with: .color(color.opacity(0.08)))
        }
    }
}

#Preview {
    SparklineRowView()
        .environmentObject(ServerStateViewModel())
        .padding()
        .frame(width: 700)
}
