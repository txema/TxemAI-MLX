import SwiftUI

// MARK: - MetricsGridView  (replaces MetricsRowView + SecondaryMetricsRowView)

struct MetricsGridView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.cortexTheme) private var t

    private var m: ServerMetrics { serverState.metrics }

    private var cacheEfficiency: Double {
        m.totalPrefillTokens > 0
            ? Double(m.cachedTokens) / Double(m.totalPrefillTokens) * 100
            : 0
    }

    var body: some View {
        // 4-column × 2-row grid with 1px bd separators between cells
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MetricTile(
                    label: "THROUGHPUT",
                    value: String(format: "%.1f", m.tokensPerSecond),
                    unit: "t/s",
                    sub: "↑ generation",
                    hasRight: true, hasBottom: true
                )
                MetricTile(
                    label: "MEMORY USED",
                    value: String(format: "%.0f", m.memoryUsedGB),
                    unit: "GB",
                    sub: "of \(Int(m.memoryTotalGB)) GB total",
                    hasRight: true, hasBottom: true
                )
                MetricTile(
                    label: "ACTIVE REQ.",
                    value: "\(m.activeRequests)",
                    unit: "",
                    sub: "\(m.queuedRequests) queued",
                    hasRight: true, hasBottom: true
                )
                MetricTile(
                    label: "CACHE HIT",
                    value: String(format: "%.0f", m.cacheHitPercent * 100),
                    unit: "%",
                    sub: "KV hot tier",
                    hasRight: false, hasBottom: true
                )
            }
            HStack(spacing: 0) {
                MetricTile(
                    label: "PREFILL TOKENS",
                    value: formatCount(m.totalPrefillTokens),
                    unit: "",
                    sub: "total processed",
                    hasRight: true, hasBottom: false
                )
                MetricTile(
                    label: "CACHED TOKENS",
                    value: formatCount(m.cachedTokens),
                    unit: "",
                    sub: "KV cache hits",
                    hasRight: true, hasBottom: false
                )
                MetricTile(
                    label: "CACHE EFFIC.",
                    value: String(format: "%.0f", cacheEfficiency),
                    unit: "%",
                    sub: "reuse rate",
                    hasRight: true, hasBottom: false
                )
                MetricTile(
                    label: "PROMPT SPEED",
                    value: String(format: "%.0f", m.promptProcessingTps),
                    unit: "t/s",
                    sub: "prefill speed",
                    hasRight: false, hasBottom: false
                )
            }
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - MetricTile

private struct MetricTile: View {
    let label: String
    let value: String
    let unit: String
    let sub: String
    let hasRight: Bool
    let hasBottom: Bool

    @Environment(\.cortexTheme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.07 * 9.5)
                .foregroundStyle(t.lbl)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 21, weight: .heavy).monospacedDigit())
                    .foregroundStyle(t.t1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(t.lbl)
                }
            }

            Text(sub)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(t.t4)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Right border
        .overlay(alignment: .trailing) {
            if hasRight {
                Rectangle().fill(t.bd).frame(width: 1)
            }
        }
        // Bottom border
        .overlay(alignment: .bottom) {
            if hasBottom {
                Rectangle().fill(t.bd).frame(height: 1)
            }
        }
    }
}

#Preview {
    MetricsGridView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 468)
}
