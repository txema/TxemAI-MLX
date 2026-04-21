//
//  ChatModels.swift
//  TxemAI-MLX
//

import Foundation

// A "Persona" = system prompt + model parameters
struct Persona: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var systemPrompt: String
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var maxTokens: Int?
    var preferredModel: String?
}

// A single chat session
struct ChatSession: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var folderId: UUID?
    var personaId: UUID?
    var modelId: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var messages: [PersistedMessage] = []

    // Equatable y Hashable basados solo en id — evita comparar el array de mensajes
    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// A message stored on disk
struct PersistedMessage: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var role: String               // "user" | "assistant" | "system"
    var content: String
    var timestamp: Date = Date()
    var tokensPerSecond: Double?
    var durationSeconds: Double?
    var imageBase64: String? = nil         // base64 encoded image data
    var textAttachmentNames: [String] = [] // filenames shown in user bubble

    // Branch navigation — mirrors ChatMessage.contentVariants/activeVariant.
    // Older JSON files without these keys decode cleanly via default values.
    var contentVariants: [String] = []
    var activeVariant: Int = 0

    static func == (lhs: PersistedMessage, rhs: PersistedMessage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// Sampling overrides and system prompt stored per-folder
struct FolderSettings: Codable {
    var systemPrompt: String = ""
    var temperature: Double? = nil
    var topP: Double? = nil
    var topK: Int? = nil
    var maxTokens: Int? = nil
}

// A folder for grouping chats
struct ChatFolder: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var settings: FolderSettings = FolderSettings()
    var avatarPath: String? = nil   // absolute path to a copied JPG/PNG on disk

    static func == (lhs: ChatFolder, rhs: ChatFolder) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// A file or image attached to a chat message before sending
enum AttachmentItem: Identifiable, Sendable {
    case text(filename: String, content: String)
    case image(filename: String, base64: String, mimeType: String)

    var id: String {
        switch self {
        case .text(let filename, _): return filename
        case .image(let filename, _, _): return filename
        }
    }

    var filename: String {
        switch self {
        case .text(let f, _): return f
        case .image(let f, _, _): return f
        }
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}
