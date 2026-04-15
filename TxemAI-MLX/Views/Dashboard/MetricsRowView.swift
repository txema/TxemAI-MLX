import SwiftUI

/// Fila de 4 tarjetas de métricas siempre visibles en la parte superior del dashboard:
/// throughput (t/s), memoria usada, requests activos, cache hit rate.
struct MetricsRowView: View {
    @EnvironmentObject var serverState: ServerStateViewModel

    var body: some View {
        HStack(spacing: 8) {
            MetricCard(
                label: "throughput",
                value: String(format: "%.1f", serverState.metrics.tokensPerSecond),
                unit: "t/s",
                subtitle: "↑ generation"
            )
            MetricCard(
                label: "memory used",
                value: String(format: "%.0f", serverState.metrics.memoryUsedGB),
                unit: "GB",
                subtitle: "of \(String(format: "%.0f", serverState.metrics.memoryTotalGB)) GB"
            )
            MetricCard(
                label: "active requests",
                value: "\(serverState.metrics.activeRequests)",
                unit: "",
                subtitle: "\(serverState.metrics.queuedRequests) queued"
            )
            MetricCard(
                label: "cache hit",
                value: String(format: "%.0f", serverState.metrics.cacheHitPercent),
                unit: "%",
                subtitle: "KV hot tier"
            )
        }
    }
}

/// Tarjeta individual de métrica.
struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .medium))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Secondary metrics row (prefill tokens, cached tokens, cache efficiency, prompt t/s)

struct SecondaryMetricsRowView: View {
    @EnvironmentObject var serverState: ServerStateViewModel

    var body: some View {
        HStack(spacing: 8) {
            MetricCard(
                label: "prefill tokens",
                value: formatCount(serverState.metrics.totalPrefillTokens),
                unit: "",
                subtitle: "total processed"
            )
            MetricCard(
                label: "cached tokens",
                value: formatCount(serverState.metrics.cachedTokens),
                unit: "",
                subtitle: "KV cache hits"
            )
            MetricCard(
                label: "cache efficiency",
                value: String(format: "%.0f", serverState.metrics.cacheHitPercent),
                unit: "%",
                subtitle: "reuse rate"
            )
            MetricCard(
                label: "prompt t/s",
                value: String(format: "%.1f", serverState.metrics.promptProcessingTps),
                unit: "t/s",
                subtitle: "prefill speed"
            )
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

#Preview {
    MetricsRowView()
        .environmentObject(ServerStateViewModel())
        .padding()
        .frame(width: 700)
}
