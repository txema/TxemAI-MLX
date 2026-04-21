import Foundation

/// Snapshot de métricas del servidor en un momento dado.
/// Se recibe vía WebSocket cada segundo desde el backend.
/// Debe ser Sendable para poder usarse en contextos concurrentes.
struct ServerMetrics: Codable, Sendable {
    var tokensPerSecond: Double
    var memoryUsedGB: Double
    var memoryTotalGB: Double
    var memoryPressurePercent: Double
    var activeRequests: Int
    var queuedRequests: Int
    var cacheHitPercent: Double
    var totalPrefillTokens: Int = 0
    var cachedTokens: Int = 0
    var promptProcessingTps: Double = 0

    static let empty = ServerMetrics(
        tokensPerSecond: 0,
        memoryUsedGB: 0,
        memoryTotalGB: 128,
        memoryPressurePercent: 0,
        activeRequests: 0,
        queuedRequests: 0,
        cacheHitPercent: 0
    )
}

/// Entrada individual del log del servidor.
/// Sendable para poder enviarse entre actores.
struct LogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: Level
    let message: String

    enum Level: String, Codable, Sendable {
        case info  = "INF"
        case ok    = "OK"
        case warn  = "WRN"
        case error = "ERR"

        var label: String { rawValue }
        // Color resuelto en la View, no aquí, para evitar dependencia de MainActor
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

/// Mensaje en la vista de chat.
struct ChatMessage: Identifiable, Sendable {
    let id: UUID = UUID()
    let role: Role
    var content: String
    var imageData: Data? = nil              // thumbnail data for user messages with images
    var textAttachmentNames: [String] = [] // filenames of text attachments shown in bubble
    var tokensPerSecond: Double? = nil     // filled after assistant response completes
    var durationSeconds: Double? = nil     // filled after assistant response completes

    // Branch navigation — all versions stored here (oldest→newest).
    // Empty means single version; ≥ 2 means branching has occurred.
    // `content` always reflects `contentVariants[activeVariant]` when variants exist.
    var contentVariants: [String] = []
    var activeVariant: Int = 0

    var hasBranches: Bool { contentVariants.count > 1 }
    var totalVariants: Int { max(1, contentVariants.count) }

    enum Role: Sendable { case user, assistant, system }
}
