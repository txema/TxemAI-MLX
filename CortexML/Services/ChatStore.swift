//
//  ChatStore.swift
//  TxemAI-MLX
//
//  Created by Txema on 11/04/2026.
//

import Foundation
import Combine

@MainActor
class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published var folders: [ChatFolder] = []
    @Published var sessions: [ChatSession] = []
    @Published var personas: [Persona] = []

    private let baseURL: URL
    
    init() {
        let documentsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".txemai-mlx")
        self.baseURL = documentsPath
        
        // Ensure directories exist
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: baseURL.appendingPathComponent("chats"),
            withIntermediateDirectories: true
        )
        
        load()
    }

    // MARK: - Session Management
    
    func save(session: ChatSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        
        // Update sessions array
        if let existingIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[existingIndex] = session
        } else {
            sessions.append(session)
        }
        
        // Write to file
        let sessionURL = baseURL.appendingPathComponent("chats").appendingPathComponent("\(session.id.uuidString).json")
        try? data.write(to: sessionURL)
        
        // Update updatedAt
        var updatedSession = session
        updatedSession.updatedAt = Date()
        
        // Replace in array with updated timestamp
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].updatedAt = Date()
        }
    }
    
    func delete(session: ChatSession) {
        // Remove from array
        sessions.removeAll { $0.id == session.id }
        
        // Delete file
        let sessionURL = baseURL.appendingPathComponent("chats").appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: sessionURL)
    }
    
    func move(session: ChatSession, to folder: ChatFolder?) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        
        var updatedSession = sessions[index]
        updatedSession.folderId = folder?.id
        save(session: updatedSession)
    }
    
    // MARK: - Folder Management
    
    func save(folder: ChatFolder) {
        // FolderSettings is Codable and nested inside ChatFolder, so JSONEncoder
        // automatically encodes/decodes it as part of the ChatFolder value —
        // no extra handling needed here.
        if let existingIndex = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[existingIndex] = folder
        } else {
            folders.append(folder)
        }

        guard let data = try? JSONEncoder().encode(folders) else { return }
        let folderURL = baseURL.appendingPathComponent("folders.json")
        try? data.write(to: folderURL)
    }
    
    func rename(folder: ChatFolder, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        
        var updatedFolder = folders[index]
        updatedFolder.name = name
        save(folder: updatedFolder)
    }
    
    @discardableResult
    func setAvatar(for folder: ChatFolder, imageURL: URL) -> ChatFolder {
        let avatarsDir = baseURL.appendingPathComponent("avatars")
        try? FileManager.default.createDirectory(at: avatarsDir, withIntermediateDirectories: true)

        // Always store as .jpg regardless of source extension
        let destURL = avatarsDir.appendingPathComponent("\(folder.id).jpg")
        try? FileManager.default.removeItem(at: destURL)
        try? FileManager.default.copyItem(at: imageURL, to: destURL)

        var updated = folder
        updated.avatarPath = destURL.path
        save(folder: updated)
        return updated
    }

    func delete(folder: ChatFolder) {
        // Move sessions in this folder to root
        for session in sessions where session.folderId == folder.id {
            move(session: session, to: nil)
        }
        
        // Remove from array
        folders.removeAll { $0.id == folder.id }
        
        // Save complete array to file
        guard let data = try? JSONEncoder().encode(folders) else { return }
        let folderURL = baseURL.appendingPathComponent("folders.json")
        try? data.write(to: folderURL)
    }
    
    // MARK: - Persona Management
    
    func save(persona: Persona) {
        // Update personas array first, then encode the complete updated array
        if let existingIndex = personas.firstIndex(where: { $0.id == persona.id }) {
            personas[existingIndex] = persona
        } else {
            personas.append(persona)
        }

        guard let data = try? JSONEncoder().encode(personas) else { return }
        let personaURL = baseURL.appendingPathComponent("personas.json")
        try? data.write(to: personaURL)
    }
    
    func delete(persona: Persona) {
        // Remove from array
        personas.removeAll { $0.id == persona.id }
        
        // Update sessions using this persona to remove reference
        for session in sessions where session.personaId == persona.id {
            var updatedSession = session
            updatedSession.personaId = nil
            save(session: updatedSession)
        }
        
        // Save complete array to file
        guard let data = try? JSONEncoder().encode(personas) else { return }
        let personaURL = baseURL.appendingPathComponent("personas.json")
        try? data.write(to: personaURL)
    }
    
    // MARK: - Loading
    
    func load() {
        // Load folders
        let folderURL = baseURL.appendingPathComponent("folders.json")
        if let data = try? Data(contentsOf: folderURL),
           let loadedFolders = try? JSONDecoder().decode([ChatFolder].self, from: data) {
            folders = loadedFolders
        } else {
            folders = []
        }
        
        // Load personas
        let personaURL = baseURL.appendingPathComponent("personas.json")
        if let data = try? Data(contentsOf: personaURL),
           let loadedPersonas = try? JSONDecoder().decode([Persona].self, from: data) {
            personas = loadedPersonas
        } else {
            personas = []
        }
        
        // Load sessions from individual files
        let chatsURL = baseURL.appendingPathComponent("chats")
        if let enumerator = FileManager.default.enumerator(at: chatsURL, includingPropertiesForKeys: nil) {
            sessions.removeAll()
            
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "json" {
                if let data = try? Data(contentsOf: fileURL),
                   let session = try? JSONDecoder().decode(ChatSession.self, from: data) {
                    sessions.append(session)
                }
            }
        } else {
            sessions = []
        }
    }
    
    // MARK: - Utility Methods
    
    func createNewSession(withFirstMessage firstMessage: String) -> ChatSession {
        let truncatedTitle = String(firstMessage.prefix(50))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newSession = ChatSession(
            id: UUID(),
            title: truncatedTitle.isEmpty ? "New Chat" : truncatedTitle,
            folderId: nil,
            personaId: nil,
            modelId: nil,
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )
        
        sessions.append(newSession)
        return newSession
    }
    
    func getSession(id: UUID) -> ChatSession? {
        return sessions.first { $0.id == id }
    }
    
    func getFolder(id: UUID) -> ChatFolder? {
        return folders.first { $0.id == id }
    }
    
    func getPersona(id: UUID) -> Persona? {
        return personas.first { $0.id == id }
    }
}
