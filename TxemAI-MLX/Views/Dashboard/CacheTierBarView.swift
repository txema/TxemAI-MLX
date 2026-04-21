import SwiftUI

// MARK: - CacheTierBarView

/// Horizontal segmented bar showing Hot (model VRAM) vs Cold (free) memory.
/// A "warm" SSD tier will be wired in once the API exposes SSD cache occupancy.
struct CacheTierBarView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.cortexTheme) private var t

    private var total: Double { serverState.metrics.memoryTotalGB }
    private var hot:   Double { min(serverState.metrics.memoryUsedGB, total) }
    private var cold:  Double { max(total - hot, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label
            HStack {
                Text("CACHE TIERS — \(Int(total)) GB")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.08 * 9.5)
                    .foregroundStyle(t.lbl)
                Spacer()
            }

            // Bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Hot segment (loaded models)
                    if hot > 0 {
                        RoundedRectangleSegment(
                            width: geo.size.width * (hot / total),
                            isFirst: true,
                            isLast: cold <= 0
                        )
                        .fill(LinearGradient(
                            colors: [t.accent, t.accent.opacity(0.67)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    }
                    // Cold segment (free)
                    if cold > 0 {
                        RoundedRectangleSegment(
                            width: geo.size.width * (cold / total),
                            isFirst: hot <= 0,
                            isLast: true
                        )
                        .fill(t.bd2)
                    }
                }
            }
            .frame(height: 7)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Legend
            HStack(spacing: 14) {
                LegendItem(color: t.accent, label: "Hot (VRAM)", value: hot)
                LegendItem(color: t.bd2,    label: "Cold (free)", value: cold)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Helpers

private struct RoundedRectangleSegment: Shape {
    let width: CGFloat
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        Rectangle().path(in: CGRect(x: rect.minX, y: rect.minY,
                                    width: width, height: rect.height))
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let value: Double
    @Environment(\.cortexTheme) private var t

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label)  ")
                .font(.system(size: 9.5))
                .foregroundStyle(t.t3)
            + Text(String(format: "%.0f GB", value))
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(t.t3)
        }
    }
}

#Preview {
    CacheTierBarView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 468)
        .background(Color(hex: "#1c1d26"))
}
