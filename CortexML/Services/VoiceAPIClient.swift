import Foundation

// MARK: - VoiceAPIClient

final class VoiceAPIClient {
    static let shared = VoiceAPIClient()

    private let baseURL = URL(string: "http://localhost:17493")!
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fmt.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                debugDescription: "Cannot decode date: \(s)")
        }
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private init() {}

    // MARK: - TTS

    func generateSpeech(
        text: String,
        profileId: String,
        language: String = "en",
        engine: String = "qwen",
        modelSize: String = "1.7B"
    ) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent("generate/stream"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "profile_id": profileId,
            "text": text,
            "language": language,
            "engine": engine,
            "model_size": modelSize,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
        return data
    }

    // MARK: - STT

    func transcribeAudio(audioData: Data, language: String?) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("transcribe"))
        req.httpMethod = "POST"

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        if let lang = language, !lang.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
        let result = try decoder.decode(TranscriptionResponse.self, from: data)
        return result.text
    }

    // MARK: - Profiles

    func fetchProfiles() async throws -> [VoiceProfile] {
        let req = URLRequest(url: baseURL.appendingPathComponent("profiles"))
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
        return try decoder.decode([VoiceProfile].self, from: data)
    }

    func createProfile(_ profile: VoiceProfileCreate) async throws -> VoiceProfile {
        var req = URLRequest(url: baseURL.appendingPathComponent("profiles"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(profile)
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
        return try decoder.decode(VoiceProfile.self, from: data)
    }

    func deleteProfile(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("profiles/\(id)"))
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
    }

    // MARK: - Effects

    func fetchAvailableEffects() async throws -> [VoiceEffect] {
        let req = URLRequest(url: baseURL.appendingPathComponent("effects/available"))
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)

        struct AvailableEffectsResponse: Decodable {
            struct AvailableEffect: Decodable {
                let type: String
                let defaultParams: [String: Double]?
                enum CodingKeys: String, CodingKey {
                    case type
                    case defaultParams = "default_params"
                }
            }
            let effects: [AvailableEffect]
        }

        let envelope = try decoder.decode(AvailableEffectsResponse.self, from: data)
        return envelope.effects.map { e in
            VoiceEffect(type: e.type, params: e.defaultParams ?? [:])
        }
    }

    // MARK: - Model status

    func fetchModelStatus() async throws -> [VoiceModelStatus] {
        let req = URLRequest(url: baseURL.appendingPathComponent("models/status"))
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
        return try decoder.decode([VoiceModelStatus].self, from: data)
    }

    func downloadModel(name: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("models/download"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model_name": name])
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
    }

    // MARK: - Health

    func healthCheck() async throws -> Bool {
        let req = URLRequest(url: baseURL.appendingPathComponent("health"))
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    // MARK: - Private

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
