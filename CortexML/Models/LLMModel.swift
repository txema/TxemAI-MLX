import SwiftUI

/// Representa un modelo LLM disponible en el servidor.
struct LLMModel: Identifiable, Codable, Equatable {
    let id: String          // nombre del directorio, ej: "Qwen3-Coder-Next"
    let name: String        // nombre display
    let quantization: String // "Q4", "Q8", "8-bit", etc.
    let sizeGB: Double      // tamaño en GB
    var status: Status
    var isPinned: Bool
    var memoryFraction: Double // 0.0-1.0, proporción de la memoria total usada
    var modelAlias: String? = nil   // User-set alias (nil if none set)
    var temperature: Double? = nil  // Saved per-model temperature (nil = not set by user)
    var topP: Double? = nil         // Saved per-model top_p
    var topK: Int? = nil            // Saved per-model top_k
    var ttlSeconds: Int? = nil      // Saved per-model idle TTL (nil = not set / use default)

    enum Status: String, Codable {
        case loaded = "loaded"
        case idle   = "idle"
        case loading = "loading"

        var badgeBackground: Color {
            switch self {
            case .loaded:  return Color.green.opacity(0.12)
            case .idle:    return Color(NSColor.controlBackgroundColor)
            case .loading: return Color.orange.opacity(0.12)
            }
        }
        var badgeForeground: Color {
            switch self {
            case .loaded:  return Color.green
            case .idle:    return Color.secondary
            case .loading: return Color.orange
            }
        }
    }
}
