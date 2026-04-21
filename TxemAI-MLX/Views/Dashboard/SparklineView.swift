import SwiftUI

/// Reusable Canvas-based sparkline used by ThroughputChartView and model cards.
/// Draws a filled area + stroke line, normalised to the data's own min/max.
struct SparklineCanvas: View {
    let dataPoints: [Double]
    let strokeColor: Color
    let fillOpacity: Double

    init(dataPoints: [Double], strokeColor: Color, fillOpacity: Double = 0.18) {
        self.dataPoints = dataPoints
        self.strokeColor = strokeColor
        self.fillOpacity = fillOpacity
    }

    var body: some View {
        Canvas { ctx, size in
            guard dataPoints.count > 1 else { return }

            let maxV  = dataPoints.max() ?? 1
            let minV  = dataPoints.min() ?? 0
            let range = maxV - minV > 0 ? maxV - minV : 1
            let step  = size.width / CGFloat(dataPoints.count - 1)

            var linePath = Path()
            var areaPath = Path()

            for (i, v) in dataPoints.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (CGFloat(v - minV) / CGFloat(range)) * size.height
                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    areaPath.move(to: CGPoint(x: 0,  y: size.height))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
            areaPath.closeSubpath()

            ctx.stroke(linePath, with: .color(strokeColor),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            ctx.fill(areaPath, with: .color(strokeColor.opacity(fillOpacity)))
        }
    }
}

#Preview {
    SparklineCanvas(
        dataPoints: [0, 5, 3, 8, 12, 7, 15, 10, 18, 14, 20, 16],
        strokeColor: Color(hex: "#3b82f6")
    )
    .frame(width: 200, height: 48)
    .padding()
}
