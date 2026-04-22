import Foundation

// MARK: - VoiceProfile

struct VoiceProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var language: String
    var engine: String
    var modelSize: String?
    var createdAt: Date?
    var sampleCount: Int?
    var avatarPath: String?
    var effectsChain: [VoiceEffect]?
}

// MARK: - VoiceProfileCreate

struct VoiceProfileCreate: Codable {
    var name: String
    var language: String
    var engine: String
    var modelSize: String?
}

// MARK: - VoiceEffect

struct VoiceEffect: Identifiable, Codable, Equatable {
    var id: UUID
    var type: String
    var params: [String: Double]

    init(id: UUID = UUID(), type: String, params: [String: Double]) {
        self.id     = id
        self.type   = type
        self.params = params
    }

    // id is not sent by the backend — synthesize one when decoding
    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        id       = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        type     = try c.decode(String.self, forKey: .type)
        params   = (try? c.decode([String: Double].self, forKey: .params)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, params
    }
}

// MARK: - VoiceModelStatus

struct VoiceModelStatus: Identifiable, Codable {
    var modelName: String
    var displayName: String
    var hfRepoId: String
    var downloaded: Bool
    var downloading: Bool
    var sizeMb: Double?
    var loaded: Bool

    var id: String { modelName }
}

// MARK: - TranscriptionResponse

struct TranscriptionResponse: Codable {
    var text: String
    var duration: Double
}

// MARK: - VoiceGenerationRequest

struct VoiceGenerationRequest: Codable {
    var profileId: String
    var text: String
    var language: String = "en"
    var engine: String = "qwen"
    var modelSize: String = "1.7B"
    var effectsChain: [VoiceEffect]?
}
