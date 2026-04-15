import Foundation

/// Recommended sampling params returned by GET /admin/api/models/{id}/generation_config.
/// Values are read from the model's generation_config.json and config.json on disk.
/// All fields are optional — a model may not have all of them in its config.
struct ModelGenerationConfig: Codable {
    let temperature: Double?
    let topP: Double?
    let topK: Int?
    let repetitionPenalty: Double?
    let maxContextWindow: Int?
}

/// Patch payload for PUT /admin/api/models/{id}/settings.
/// nil fields are omitted from the encoded JSON so the backend leaves them unchanged.
/// Non-nil fields are sent and the backend updates only those settings.
struct ModelSettingsUpdate: Encodable {
    var modelAlias: String?
    var isPinned: Bool?
    var ttlSeconds: Int?
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var repetitionPenalty: Double?

    enum CodingKeys: String, CodingKey {
        case modelAlias = "model_alias"
        case isPinned = "is_pinned"
        case ttlSeconds = "ttl_seconds"
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case repetitionPenalty = "repetition_penalty"
    }
}
