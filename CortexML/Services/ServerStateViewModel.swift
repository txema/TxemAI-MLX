import Foundation
import Combine

@MainActor
class ServerStateViewModel: ObservableObject {

    enum ConnectionState {
        case connecting, connected, disconnected, needsApiKey
    }

    // MARK: - Estado
    @Published var isServerRunning: Bool = false
    @Published var serverPort: Int = 8000
    @Published var connectionState: ConnectionState = .disconnected
    @Published var startServerError: String? = nil

    // MARK: - Modelos
    @Published var models: [LLMModel] = []
    var activeModelName: String? {
        models.first(where: { $0.status == .loaded })?.name
    }

    // MARK: - Métricas
    @Published var metrics: ServerMetrics = .empty
    @Published var metricsHistory: [ServerMetrics] = []
    private let historyMaxLength = 60

    // MARK: - Logs
    @Published var logs: [LogEntry] = []

    // MARK: - Internos
    private let api = APIClient.shared
    private var pollModelsTask: Task<Void, Never>?
    private var pollMetricsTask: Task<Void, Never>?
    private var pollLogsTask: Task<Void, Never>?
    private var logWatcher: LogFileWatcher?
    private var usingAPILogs = false // true once /api/logs returns entries

    // MARK: - Singleton
    static let shared = ServerStateViewModel()

    // MARK: - Init
    init() {
        // When the embedded server finishes starting, connect automatically.
        NotificationCenter.default.addObserver(
            forName: .embeddedServerDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.connect()
            }
        }
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        let serverMode = UserDefaults.standard.string(forKey: "serverMode") ?? "embedded"

        if serverMode == "embedded" {
            // User starts the server manually via the toolbar button.
            // Never auto-start and never show the API key dialog.
            connectionState = .disconnected
            return
        }

        // External mode: require API key before connecting
        let savedKey = UserDefaults.standard.string(forKey: "omlx_api_key") ?? ""
        if savedKey.isEmpty {
            connectionState = .needsApiKey
            return
        }
        api.apiKey = savedKey
        await connect()
    }

    func reconnect() {
        Task { await connect() }
    }

    // MARK: - Conexión

    private func connect() async {
        connectionState = .connecting

        // Login admin
        do {
            if let key = api.apiKey, !key.isEmpty {
                try await api.login(apiKey: key)
            }
        } catch {
            connectionState = .disconnected
            return
        }

        // Carga inicial de modelos
        do {
            let fetched = try await api.fetchModels()
            models = fetched
            connectionState = .connected
            isServerRunning = true
        } catch {
            connectionState = .disconnected
            return
        }

        // Carga inicial de métricas
        await refreshMetrics()

        // Carga inicial de logs via API; cae a LogFileWatcher si está vacío
        await refreshLogs(initial: true)

        // Poll modelos cada 5s
        startPollingModels()

        // Poll métricas cada 2s
        startPollingMetrics()

        // Poll logs cada 3s
        startPollingLogs()
    }

    // MARK: - Polling modelos

    private func startPollingModels() {
        pollModelsTask?.cancel()
        pollModelsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshModels()
            }
        }
    }

    private func refreshModels() async {
        do {
            let fetched = try await api.fetchModels()
            models = fetched
            if connectionState != .connected {
                connectionState = .connected
                isServerRunning = true
            }
        } catch {
            if connectionState == .connected {
                connectionState = .disconnected
                isServerRunning = false
            }
        }
    }

    // MARK: - Polling métricas (cada 2s via /admin/api/stats)

    private func startPollingMetrics() {
        pollMetricsTask?.cancel()
        pollMetricsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await refreshMetrics()
            }
        }
    }

    private func refreshMetrics() async {
        do {
            let newMetrics = try await api.fetchStats(loadedModels: models)
            appendMetrics(newMetrics)
        } catch {
            // Fallo silencioso — no desconectamos por un fallo de métricas
        }
    }

    // MARK: - Logs

    private func refreshLogs(initial: Bool = false) async {
        do {
            let newEntries = try await api.fetchLogs(limit: 200)
            if !newEntries.isEmpty {
                if !usingAPILogs {
                    // First successful API log fetch — stop file watcher
                    usingAPILogs = true
                    logWatcher?.stop()
                    logWatcher = nil
                    if initial { logs = newEntries }
                } else {
                    logs.append(contentsOf: newEntries)
                }
                if logs.count > 500 {
                    logs = Array(logs.suffix(500))
                }
            } else if initial {
                // API returned empty — fall back to LogFileWatcher
                startLogWatcher()
            }
        } catch {
            if initial {
                startLogWatcher()
            }
        }
    }

    private func startPollingLogs() {
        pollLogsTask?.cancel()
        pollLogsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await refreshLogs()
            }
        }
    }

    private func startLogWatcher() {
        let logPath = (NSHomeDirectory() as NSString).appendingPathComponent(".omlx/logs/server.log")
        logWatcher = LogFileWatcher(path: logPath) { [weak self] entry in
            self?.logs.append(entry)
        }
        logWatcher?.start()
    }

    // MARK: - Métricas

    func appendMetrics(_ newMetrics: ServerMetrics) {
        metrics = newMetrics
        metricsHistory.append(newMetrics)
        if metricsHistory.count > historyMaxLength {
            metricsHistory.removeFirst()
        }
    }

    // MARK: - Acciones de modelos

    func refreshModelList() {
        Task { await refreshModels() }
    }

    func toggleModel(_ model: LLMModel) {
        guard let idx = models.firstIndex(of: model) else { return }
        models[idx].status = model.status == .loaded ? .idle : .loading
        Task {
            do {
                try await api.toggleModel(model)
                try? await Task.sleep(for: .seconds(1))
            } catch { }
            await refreshModels()
        }
    }

    func togglePin(_ model: LLMModel) {
        guard let idx = models.firstIndex(of: model) else { return }
        models[idx].isPinned.toggle()
        Task {
            do {
                try await api.togglePin(model)
            } catch {
                if let revertIdx = models.firstIndex(of: model) {
                    models[revertIdx].isPinned = model.isPinned
                }
            }
        }
    }

    // MARK: - Servidor

    func startServer() {
        Task {
            do {
                try await api.startServer()
                connectionState = .connecting
                // Poll every 2s for up to 30s until the server responds
                for _ in 0..<15 {
                    try await Task.sleep(for: .seconds(2))
                    if (try? await api.fetchModels()) != nil {
                        await connect()
                        return
                    }
                }
                // Server did not respond within 30s
                connectionState = .disconnected
            } catch APIError.omlxAppNotFound {
                startServerError = APIError.omlxAppNotFound.errorDescription
                connectionState = .disconnected
            } catch {
                connectionState = .disconnected
            }
        }
    }

    func stopServer() {
        // DMG install: we don't manage the oMLX process — just disconnect the frontend.
        isServerRunning = false
        connectionState = .disconnected
        api.disconnectMetricsStream()
        pollModelsTask?.cancel()
        pollMetricsTask?.cancel()
        pollLogsTask?.cancel()
        logWatcher?.stop()
        usingAPILogs = false
    }
}

// MARK: - Mock data para #Preview únicamente

extension LLMModel {
    static let mockModels: [LLMModel] = [
        LLMModel(id: "Qwen3-Coder-Next", name: "Qwen3-Coder-Next", quantization: "8-bit", sizeGB: 85, status: .loaded, isPinned: true, memoryFraction: 0.66),
        LLMModel(id: "Gemma-4-31B", name: "Gemma-4-31B", quantization: "Q4", sizeGB: 18, status: .idle, isPinned: false, memoryFraction: 0),
        LLMModel(id: "Qwen3.5-122B", name: "Qwen3.5-122B", quantization: "Q4", sizeGB: 71, status: .idle, isPinned: false, memoryFraction: 0),
        LLMModel(id: "DeepSeek-V3-0324", name: "DeepSeek V3-0324", quantization: "Q4", sizeGB: 390, status: .idle, isPinned: false, memoryFraction: 0),
    ]
}

extension LogEntry {
    static let mockEntries: [LogEntry] = [
        LogEntry(id: UUID(), timestamp: Date().addingTimeInterval(-60), level: .info, message: "server started · port 8000 · OpenAI compatible"),
        LogEntry(id: UUID(), timestamp: Date().addingTimeInterval(-50), level: .info, message: "model loaded · Qwen3-Coder-Next 8bit · 85.2 GB"),
        LogEntry(id: UUID(), timestamp: Date().addingTimeInterval(-40), level: .warn, message: "memory pressure high · 92 GB used · LRU eviction triggered"),
        LogEntry(id: UUID(), timestamp: Date().addingTimeInterval(-30), level: .ok,   message: "request completed · 128 tokens · 25.2 t/s"),
        LogEntry(id: UUID(), timestamp: Date().addingTimeInterval(-20), level: .info, message: "KV block evicted to SSD · cold tier · 128 blocks"),
        LogEntry(id: UUID(), timestamp: Date().addingTimeInterval(-10), level: .ok,   message: "request completed · 512 tokens · 23.8 t/s"),
        LogEntry(id: UUID(), timestamp: Date(),                         level: .ok,   message: "request completed · 256 tokens · 24.1 t/s · cache hit"),
    ]
}
