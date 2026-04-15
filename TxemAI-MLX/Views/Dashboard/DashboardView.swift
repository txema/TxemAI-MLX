import SwiftUI

/// Dashboard principal. Muestra en una sola vista:
/// - Fila de métricas (throughput, memoria, requests, cache hit)
/// - Sparklines de t/s y memoria en tiempo real
/// - Panel de logs en vivo con filtros
struct DashboardView: View {
    @EnvironmentObject var serverState: ServerStateViewModel

    var body: some View {
        VStack(spacing: 0) {
            MetricsRowView()
                .padding(12)

            SecondaryMetricsRowView()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            SparklineRowView()
                .padding(.horizontal, 12)

            LogsView()
                .padding(12)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    DashboardView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 700, height: 500)
}
