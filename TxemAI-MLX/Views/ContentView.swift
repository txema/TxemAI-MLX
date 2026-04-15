import SwiftUI

/// Vista raíz de la app. Layout principal:
/// - Panel lateral izquierdo: lista de modelos (ModelSidebarView)
/// - Área principal derecha: dashboard de métricas y logs (DashboardView)
/// Si no hay API key configurada, muestra SettingsView primero.
struct ContentView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @ObservedObject private var serverManager = ServerManager.shared
    @AppStorage("serverMode") private var serverMode: String = "embedded"
    @State private var showSettings: Bool = false
    @State private var showBenchmark: Bool = false
    @State private var showGlobalSettings: Bool = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            ModelSidebarView()
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
        } detail: {
            DashboardView()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                connectionIndicator
            }
            if serverMode == "embedded" {
                ToolbarItem(placement: .primaryAction) {
                    embeddedServerButton
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "chat")
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .help("Chat")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBenchmark = true
                } label: {
                    Image(systemName: "speedometer")
                }
                .help("Benchmark")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showGlobalSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showBenchmark) {
            BenchmarkView()
                .environmentObject(serverState)
        }
        .sheet(isPresented: $showGlobalSettings) {
            GlobalSettingsView {
                serverState.reconnect()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView {
                serverState.reconnect()
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(NSColor.windowBackgroundColor), for: .windowToolbar)
        .onAppear {
            if serverState.connectionState == .needsApiKey {
                showSettings = true
            }
        }
        .onChange(of: serverState.connectionState) {
            if serverState.connectionState == .needsApiKey {
                showSettings = true
            }
        }
    }

    @ViewBuilder
    private var embeddedServerButton: some View {
        switch serverManager.state {
        case .stopped, .error:
            Button {
                let apiKey = UserDefaults.standard.string(forKey: "omlx_api_key") ?? ""
                Task { try? await serverManager.start(port: 8000, apiKey: apiKey) }
            } label: {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
            }
            .help("Start embedded server")
        case .running:
            Button {
                serverManager.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            .help("Stop embedded server")
        case .starting:
            ProgressView()
                .controlSize(.small)
                .help("Starting…")
        }
    }

    /// Indicador de conexión en la toolbar — plain HStack so macOS 26 renders no glass pill.
    private var connectionIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
            Text(indicatorLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var indicatorColor: Color {
        switch serverState.connectionState {
        case .connected:    return .green
        case .connecting:   return .orange
        case .disconnected: return .red
        case .needsApiKey:  return .red
        }
    }

    private var indicatorLabel: String {
        switch serverState.connectionState {
        case .connected:    return "connected · port \(serverState.serverPort)"
        case .connecting:   return "connecting..."
        case .disconnected: return "disconnected"
        case .needsApiKey:  return "api key required"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerStateViewModel())
}
