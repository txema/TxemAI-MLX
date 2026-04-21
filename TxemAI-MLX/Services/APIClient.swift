import Foundation
import AppKit

class APIClient {
    static let shared = APIClient()

    private var baseURL: URL
    private var webSocketTask: URLSessionWebSocketTask?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    var apiKey: String? = UserDefaults.standard.string(forKey: "cortex_api_key")
    private var lastFetchedLastLogLine: String? = nil

    init(host: String = "localhost", port: Int = 8000) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
    }

    // MARK: - Dynamic base URL

    func updateBaseURL(host: String = "localhost", port: Int = 8000) {
        baseURL = URL(string: "http://\(host):\(port)")!
    }

    // MARK: - Log parser

    private nonisolated func parseLogLine(_ line: String) -> LogEntry {
        let clean = line.replacingOccurrences(of: #"\x1B\[[0-9;]*m"#, with: "", options: .regularExpression)
        let parts = clean.components(separatedBy: " - ")
        var level: LogEntry.Level = .info
        var message = clean
        if parts.count >= 3 {
            switch parts[2].trimmingCharacters(in: .whitespaces).uppercased() {
            case "WARNING", "WARN":   level = .warn
            case "ERROR", "CRITICAL": level = .error
            default:                  level = .info
            }
            message = parts.count >= 4
                ? parts[3...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                : parts[2...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            if message.hasPrefix("["), let end = message.firstIndex(of: "]") {
                let after = message.index(after: end)
                message = message[after...].trimmingCharacters(in: CharacterSet(charactersIn: " -"))
            }
        }
        return LogEntry(id: UUID(), timestamp: Date(), level: level, message: message)
    }

    // MARK: - Auth

    func login(apiKey: String) async throws {
        let url = baseURL.appendingPathComponent("admin/api/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct LoginBody: Encodable { let api_key: String; let remember: Bool }
        request.httpBody = try JSONEncoder().encode(LoginBody(api_key: apiKey, remember: true))
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Models

    func fetchModels() async throws -> [LLMModel] {
        let url = baseURL.appendingPathComponent("admin/api/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let list = try decoder.decode(AdminModelList.self, from: data)
        return list.models.map { entry in
            let status: LLMModel.Status
            if entry.isLoading == true       { status = .loading }
            else if entry.loaded == true     { status = .loaded }
            else                             { status = .idle }
            let sizeGB   = Double(entry.estimatedSize ?? 0) / 1_073_741_824.0
            let name     = entry.settings?.modelAlias ?? entry.settings?.displayName ?? entry.id
            let isPinned = entry.settings?.isPinned ?? entry.pinned ?? false
            let quant    = parseQuantization(from: entry.id, path: entry.modelPath) ?? ""
            return LLMModel(
                id: entry.id, name: name, quantization: quant,
                sizeGB: sizeGB, status: status, isPinned: isPinned,
                memoryFraction: sizeGB / 128.0,
                modelAlias: entry.settings?.modelAlias,
                temperature: entry.settings?.temperature,
                topP: entry.settings?.topP,
                topK: entry.settings?.topK,
                ttlSeconds: entry.settings?.ttlSeconds
            )
        }
    }

    func fetchStats(loadedModels: [LLMModel]) async throws -> ServerMetrics {
        let url = baseURL.appendingPathComponent("admin/api/stats")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        let stats = try decoder.decode(StatsResponse.self, from: data)
        let usedGB  = loadedModels.filter { $0.status == .loaded }.reduce(0.0) { $0 + $1.sizeGB }
        let totalGB = 128.0
        return ServerMetrics(
            tokensPerSecond: stats.avgGenerationTps ?? 0,
            memoryUsedGB: usedGB, memoryTotalGB: totalGB,
            memoryPressurePercent: (usedGB / totalGB) * 100,
            activeRequests: 0, queuedRequests: 0,
            cacheHitPercent: stats.cacheEfficiency ?? 0,
            totalPrefillTokens: stats.totalPromptTokens ?? 0,
            cachedTokens: stats.totalCachedTokens ?? 0,
            promptProcessingTps: stats.avgPrefillTps ?? 0
        )
    }

    private func parseQuantization(from id: String, path: String? = nil) -> String? {
        let t = (path ?? id).lowercased()
        if t.contains("8bit") || t.contains("8-bit") { return "8-bit" }
        if t.contains("4bit") || t.contains("4-bit") { return "4-bit" }
        if t.contains("-q8") || t.contains("_q8")    { return "Q8" }
        if t.contains("-q6") || t.contains("_q6")    { return "Q6" }
        if t.contains("-q5") || t.contains("_q5")    { return "Q5" }
        if t.contains("-q4") || t.contains("_q4")    { return "Q4" }
        if t.contains("-q3") || t.contains("_q3")    { return "Q3" }
        if t.contains("-q2") || t.contains("_q2")    { return "Q2" }
        if t.contains("fp16")                         { return "fp16" }
        if t.contains("bf16")                         { return "bf16" }
        return nil
    }

    func toggleModel(_ model: LLMModel) async throws {
        let action = model.status == .loaded ? "unload" : "load"
        let url = baseURL.appendingPathComponent("admin/api/models/\(model.id)/\(action)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Model Settings

    func fetchGenerationConfig(modelId: String) async throws -> ModelGenerationConfig {
        let url = baseURL.appendingPathComponent("admin/api/models/\(modelId)/generation_config")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(ModelGenerationConfig.self, from: data)
    }

    func updateModelSettings(modelId: String, settings: ModelSettingsUpdate) async throws {
        let url = baseURL.appendingPathComponent("admin/api/models/\(modelId)/settings")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(settings)
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func togglePin(_ model: LLMModel) async throws {
        let url = baseURL.appendingPathComponent("admin/api/models/\(model.id)/settings")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct PinRequest: Encodable { let is_pinned: Bool }
        request.httpBody = try JSONEncoder().encode(PinRequest(is_pinned: !model.isPinned))
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Logs

    func fetchLogs(limit: Int = 200) async throws -> [LogEntry] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("admin/api/logs"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "lines", value: "\(limit)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        let logsResponse = try decoder.decode(LogsAPIResponse.self, from: data)
        guard !logsResponse.logs.isEmpty else { return [] }
        let allLines = logsResponse.logs.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !allLines.isEmpty else { return [] }
        let newLines: [String]
        if let lastLine = lastFetchedLastLogLine, let idx = allLines.lastIndex(of: lastLine) {
            newLines = Array(allLines.dropFirst(idx + 1))
        } else {
            newLines = allLines
        }
        lastFetchedLastLogLine = allLines.last
        return newLines.map { parseLogLine($0) }
    }

    // MARK: - HuggingFace

    func searchHuggingFace(query: String) async throws -> [HFModel] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("admin/api/hf/search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "50")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(HFSearchResponse.self, from: data).models
    }

    func fetchHFRecommended() async throws -> HFRecommendedResponse {
        let url = baseURL.appendingPathComponent("admin/api/hf/recommended")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(HFRecommendedResponse.self, from: data)
    }

    func startHFDownload(repoId: String, hfToken: String = "") async throws -> HFDownloadTask {
        let url = baseURL.appendingPathComponent("admin/api/hf/download")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let repo_id: String; let hf_token: String }
        request.httpBody = try JSONEncoder().encode(Body(repo_id: repoId, hf_token: hfToken))
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(HFDownloadStartResponse.self, from: data).task
    }

    func fetchHFTasks() async throws -> [HFDownloadTask] {
        let url = baseURL.appendingPathComponent("admin/api/hf/tasks")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(HFTasksResponse.self, from: data).tasks
    }

    func cancelHFTask(taskId: String) async throws {
        let url = baseURL.appendingPathComponent("admin/api/hf/cancel/\(taskId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func removeHFTask(taskId: String) async throws {
        let url = baseURL.appendingPathComponent("admin/api/hf/task/\(taskId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Benchmark

    func startBenchmark(
        modelId: String,
        promptTokens: Int,
        completionTokens: Int,
        runs: Int
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("admin/api/bench/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable {
            let model_id: String; let prompt_tokens: Int
            let completion_tokens: Int; let runs: Int
        }
        request.httpBody = try JSONEncoder().encode(Body(
            model_id: modelId, prompt_tokens: promptTokens,
            completion_tokens: completionTokens, runs: runs
        ))
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        struct StartResponse: Decodable { let benchId: String }
        return try decoder.decode(StartResponse.self, from: data).benchId
    }

    func streamBenchmarkResults(benchId: String) -> AsyncThrowingStream<BenchmarkEvent, Error> {
        AsyncThrowingStream { (continuation: AsyncThrowingStream<BenchmarkEvent, Error>.Continuation) in
            let task = Task {
                do {
                    let url = self.baseURL.appendingPathComponent("admin/api/bench/\(benchId)/stream")
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    let (bytes, response) = try await self.session.bytes(for: request)
                    try self.validateResponse(response)
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let event = try? self.decoder.decode(BenchmarkEvent.self, from: data)
                        else { continue }
                        continuation.yield(event)
                        if event.type == "done" || event.type == "error" { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancelBenchmark(benchId: String) async throws {
        let url = baseURL.appendingPathComponent("admin/api/bench/\(benchId)/cancel")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Global Settings

    func fetchGlobalSettings() async throws -> GlobalSettings {
        let url = baseURL.appendingPathComponent("admin/api/global-settings")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(GlobalSettings.self, from: data)
    }

    func updateGlobalSettings(_ update: GlobalSettingsUpdate) async throws {
        let url = baseURL.appendingPathComponent("admin/api/global-settings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(update)
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - SSD Cache

    func clearSSDCache() async throws {
        let url = baseURL.appendingPathComponent("admin/api/ssd-cache/clear")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Chat streaming

    func streamChat(
        model: String,
        messages: [ChatMessage],
        attachments: [AttachmentItem] = [],
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { (continuation: AsyncThrowingStream<String, Error>.Continuation) in
            let task = Task {
                do {
                    let url = self.baseURL.appendingPathComponent("v1/chat/completions")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let key = self.apiKey, !key.isEmpty {
                        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }

                    // Build request messages — attachments are applied to the last user message
                    let allButLast = messages.dropLast()
                    var requestMessages: [ChatRequestMessage] = allButLast.map { msg in
                        let role = msg.role == .user ? "user" : msg.role == .system ? "system" : "assistant"
                        return .text(role: role, content: msg.content)
                    }

                    if let lastMsg = messages.last {
                        let role = lastMsg.role == .user ? "user" : lastMsg.role == .system ? "system" : "assistant"

                        // Text attachments: prepend as fenced code blocks
                        var textContent = lastMsg.content
                        for case .text(let filename, let content) in attachments {
                            let ext = URL(fileURLWithPath: filename).pathExtension
                            textContent = "[\(filename)]\n```\(ext)\n\(content)\n```\n" + textContent
                        }

                        // Image attachments: always use multimodal format when present
                        let imageAttachments = attachments.filter { $0.isImage }
                        if !imageAttachments.isEmpty {
                            var parts: [ContentPart] = [
                                ContentPart(type: "text", text: textContent, imageUrl: nil)
                            ]
                            for case .image(_, let base64, let mimeType) in attachments {
                                let dataURI = "data:\(mimeType);base64,\(base64)"
                                parts.append(ContentPart(
                                    type: "image_url", text: nil,
                                    imageUrl: ImageURL(url: dataURI)
                                ))
                            }
                            requestMessages.append(.multimodal(role: role, parts: parts))
                        } else {
                            requestMessages.append(.text(role: role, content: textContent))
                        }
                    }

                    let body = FlexibleChatRequest(
                        model: model, messages: requestMessages, stream: true,
                        temperature: temperature, topP: topP, maxTokens: maxTokens
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await self.session.bytes(for: request)
                    try self.validateResponse(response)
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let chunkData = payload.data(using: .utf8),
                              let chunk = try? self.decoder.decode(ChatCompletionChunk.self, from: chunkData),
                              let content = chunk.choices.first?.delta?.content else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - WebSocket (no disponible en oMLX DMG)

    func connectMetricsStream(onMetrics: @escaping @Sendable (ServerMetrics) -> Void) { }

    func disconnectMetricsStream() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Backend process (DMG)

    func startServer() async throws {
        let omlxURL = URL(fileURLWithPath: "/Applications/oMLX.app")
        guard FileManager.default.fileExists(atPath: omlxURL.path) else {
            throw APIError.omlxAppNotFound
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: omlxURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func stopServer() async throws { }

    // MARK: - Private helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case omlxAppNotFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:  return "Respuesta inválida del servidor"
        case .httpError(let c): return "Error HTTP \(c)"
        case .omlxAppNotFound:  return "oMLX app not found at /Applications/oMLX.app"
        }
    }
}

// MARK: - Private DTOs

private struct StatsResponse: Decodable {
    // Nombres exactos del JSON de oMLX
    let avgGenerationTps: Double?       // avg_generation_tps
    let avgPrefillTps: Double?          // avg_prefill_tps
    let cacheEfficiency: Double?        // cache_efficiency
    let totalTokensServed: Int?         // total_tokens_served
    let totalCachedTokens: Int?         // total_cached_tokens
    let totalPromptTokens: Int?         // total_prompt_tokens
    let totalRequests: Int?             // total_requests

    // Memoria de modelos activos (dentro de active_models)
    // No decodificamos el objeto anidado — lo calculamos desde LLMModel
}

private struct AdminModelList: Decodable {
    let models: [AdminModelEntry]
}

private struct AdminModelEntry: Decodable {
    let id: String
    let modelPath: String?
    let loaded: Bool?
    let isLoading: Bool?
    let estimatedSize: Int?
    let pinned: Bool?
    let settings: AdminModelSettings?
}

private struct AdminModelSettings: Decodable {
    let isPinned: Bool?
    let modelAlias: String?
    let displayName: String?
    let temperature: Double?
    let topP: Double?
    let topK: Int?
    let ttlSeconds: Int?
}

private struct LogsAPIResponse: Decodable {
    let logs: String
}

// MARK: - Chat request types

private struct FlexibleChatRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let stream: Bool
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case temperature
        case topP        = "top_p"
        case maxTokens   = "max_tokens"
    }
}

private enum ChatRequestMessage: Encodable {
    case text(role: String, content: String)
    case multimodal(role: String, parts: [ContentPart])

    private enum CodingKeys: String, CodingKey { case role, content }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let role, let content):
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
        case .multimodal(let role, let parts):
            try container.encode(role, forKey: .role)
            try container.encode(parts, forKey: .content)
        }
    }
}

private struct ContentPart: Encodable {
    let type: String
    let text: String?
    let imageUrl: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let text = text { try container.encode(text, forKey: .text) }
        if let imageUrl = imageUrl { try container.encode(imageUrl, forKey: .imageUrl) }
    }
}

private struct ImageURL: Encodable { let url: String }

private struct ChatCompletionChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let delta: Delta? }
    struct Delta: Decodable { let content: String? }
}
