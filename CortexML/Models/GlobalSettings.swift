import Foundation

/// Full server configuration returned by GET /admin/api/global-settings.
/// Nested sections match the JSON response structure — decoded via convertFromSnakeCase.
struct GlobalSettings: Codable {
    var server: Server
    var memory: Memory
    var scheduler: Scheduler
    var cache: Cache
    var sampling: Sampling
    var auth: Auth
    var system: SystemInfo

    struct Server: Codable {
        var host: String
        var port: Int
        var logLevel: String
    }
    struct Memory: Codable {
        var maxProcessMemory: String?
        var prefillMemoryGuard: Bool?
    }
    struct Scheduler: Codable {
        var maxConcurrentRequests: Int?
    }
    struct Cache: Codable {
        var enabled: Bool
        var ssdCacheDir: String
        var ssdCacheMaxSize: String
        var hotCacheMaxSize: String?
    }
    struct Sampling: Codable {
        var maxContextWindow: Int?
        var maxTokens: Int?
        var temperature: Double?
        var topP: Double?
        var topK: Int?
        var repetitionPenalty: Double?
    }
    struct Auth: Codable {
        var apiKeySet: Bool
        var apiKey: String
        var skipApiKeyVerification: Bool
    }
    struct SystemInfo: Codable {
        var totalMemory: String
        var autoModelMemory: String
        var ssdTotal: String
    }
}

/// Partial update for POST /admin/api/global-settings.
/// nil fields are omitted from the JSON body — the backend leaves them unchanged.
struct GlobalSettingsUpdate: Encodable {
    var port: Int?
    var host: String?
    var logLevel: String?
    var maxProcessMemory: String?
    var maxConcurrentRequests: Int?
    var cacheEnabled: Bool?
    var ssdCacheDir: String?
    var ssdCacheMaxSize: String?
    var hotCacheMaxSize: String?
    var samplingMaxContextWindow: Int?
    var samplingMaxTokens: Int?
    var samplingTemperature: Double?
    var samplingTopP: Double?
    var samplingTopK: Int?
    var samplingRepetitionPenalty: Double?
    var apiKey: String?
    var skipApiKeyVerification: Bool?

    enum CodingKeys: String, CodingKey {
        case port, host
        case logLevel                 = "log_level"
        case maxProcessMemory         = "max_process_memory"
        case maxConcurrentRequests    = "max_concurrent_requests"
        case cacheEnabled             = "cache_enabled"
        case ssdCacheDir              = "ssd_cache_dir"
        case ssdCacheMaxSize          = "ssd_cache_max_size"
        case hotCacheMaxSize          = "hot_cache_max_size"
        case samplingMaxContextWindow = "sampling_max_context_window"
        case samplingMaxTokens        = "sampling_max_tokens"
        case samplingTemperature      = "sampling_temperature"
        case samplingTopP             = "sampling_top_p"
        case samplingTopK             = "sampling_top_k"
        case samplingRepetitionPenalty = "sampling_repetition_penalty"
        case apiKey                   = "api_key"
        case skipApiKeyVerification   = "skip_api_key_verification"
    }
}
