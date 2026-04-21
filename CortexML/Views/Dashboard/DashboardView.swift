import SwiftUI

// MARK: - DashboardView

/// Main content area: metrics grid → throughput chart → cache tier bar → server log.
struct DashboardView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.cortexTheme) private var t

    var body: some View {
        VStack(spacing: 0) {
            // 1 · 8-tile metrics grid (4 × 2)
            MetricsGridView()
                .overlay(alignment: .bottom) {
                    Rectangle().fill(t.bd).frame(height: 1)
                }

            // 2 · Throughput area chart
            ThroughputChartView()
                .overlay(alignment: .bottom) {
                    Rectangle().fill(t.bd).frame(height: 1)
                }

            // 3 · Cache tier bar
            CacheTierBarView()
                .overlay(alignment: .bottom) {
                    Rectangle().fill(t.bd).frame(height: 1)
                }

            // 4 · Server log (fills remaining space)
            LogsView()
                .frame(maxHeight: .infinity)
        }
        .background(t.win)
        .frame(minWidth: 468, minHeight: 560)
    }
}

#Preview {
    DashboardView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 468, height: 580)
}
