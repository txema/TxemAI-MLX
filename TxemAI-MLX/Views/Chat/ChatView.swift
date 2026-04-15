import SwiftUI
import UniformTypeIdentifiers
import MarkdownUI

/// Vista de chat con layout de dos paneles.
/// Ventana secundaria que conecta con el modelo actualmente cargado en el backend vía /v1/chat/completions.
struct ChatView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @ObservedObject private var store = ChatStore.shared
    
    // Current session state
    @State private var currentSession: ChatSession? = nil
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamTask: Task<Void, Never>? = nil
    
    // Sidebar state
    @State private var selectedFolderId: UUID? = nil
    @State private var showingPersonasSheet = false
    @State private var showingFoldersSheet = false

    // Inline rename state — sessions
    @State private var renamingSessionId: UUID? = nil
    @State private var renameText: String = ""
    @FocusState private var renameFocused: Bool

    // Inline rename state — folders
    @State private var renamingFolderId: UUID? = nil
    @State private var renameFolderText: String = ""
    @FocusState private var renameFolderFocused: Bool

    // Folder settings sheet
    @State private var selectedFolderForSettings: ChatFolder? = nil

    // Appearance sheet
    @State private var showingAppearanceSheet = false
    
    // Attachments
    @State private var attachments: [AttachmentItem] = []

    // Alerts
    @State private var showNoModelAlert: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // ── Left Panel: History Sidebar (220px fixed) ───────────────
            sidebarPanel
            
            Divider()
            
            // ── Right Panel: Active Chat Area ────────────────────────────
            chatPanel
        }
        .frame(minWidth: 700, minHeight: 400)
        .alert("No Model Loaded", isPresented: $showNoModelAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Load a model in the sidebar before starting a chat.")
        }
        .onDisappear { streamTask?.cancel() }
        .sheet(isPresented: $showingFoldersSheet) { FoldersManagerView() }
        .sheet(item: $selectedFolderForSettings) { folder in
            FolderSettingsSheet(folder: folder)
        }
        .sheet(isPresented: $showingAppearanceSheet) { ChatAppearanceSheet() }
    }

    // MARK: - Left Panel (Sidebar)

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            // Header: New Chat button — top, centrado
            Button(action: createNewChat) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("New Chat")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if store.sessions.isEmpty && store.folders.isEmpty {
                // Estado vacío — centrado verticalmente
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(.tertiary)
                    Text("No chats yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                // Folders Section
                if !store.folders.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("FOLDERS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        ForEach(store.folders) { folder in
                            if renamingFolderId == folder.id {
                                TextField("Folder name", text: $renameFolderText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.accentColor.opacity(0.18))
                                    .focused($renameFolderFocused)
                                    .onSubmit { commitFolderRename(folder) }
                                    .onExitCommand { renamingFolderId = nil }
                            } else {
                                FolderRowView(
                                    folder: folder,
                                    isSelected: selectedFolderId == folder.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { toggleFolderSelection(folder) }
                                .contextMenu {
                                    Button("Add Chat to Folder", action: { createNewChatInFolder(folder) })
                                    Divider()
                                    Button("Folder Settings") { selectedFolderForSettings = folder }
                                    Divider()
                                    Button("Rename", action: { startRenameFolder(folder) })
                                    Button("Delete", role: .destructive, action: { deleteFolder(folder) })
                                }
                            }
                        }

                        Divider()
                    }
                }

                // Sessions Section
                VStack(alignment: .leading, spacing: 0) {
                    Text("RECENT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, store.folders.isEmpty ? 12 : 8)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredSessions) { session in
                                if renamingSessionId == session.id {
                                    TextField("Chat name", text: $renameText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.accentColor.opacity(0.18))
                                        .focused($renameFocused)
                                        .onSubmit { commitRename(session) }
                                        .onExitCommand { renamingSessionId = nil }
                                } else {
                                    SessionRowView(
                                        session: session,
                                        isActive: currentSession?.id == session.id
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { loadSession(session) }
                                    .contextMenu {
                                        Button("Rename", action: { renameSession(session) })
                                        Button("Move to Folder", action: { showFolderPickerForSession(session) })
                                        Button("Delete", role: .destructive, action: { deleteSession(session) })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Footer: Manage Folders — siempre al fondo
            Divider()
            Button("Manage Folders") {
                showingFoldersSheet = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Right Panel (Chat Area)

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Model indicator
                Circle()
                    .fill(serverState.activeModelName != nil ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(serverState.activeModelName ?? "no model loaded")
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                // Persona picker
                if !store.personas.isEmpty {
                    Picker("", selection: $currentSession) {
                        Text("No persona").tag(nil as ChatSession?)
                        ForEach(store.personas) { persona in
                            Text(persona.name).tag(persona.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                // More menu (export, appearance, clear)
                Menu {
                    Button("Export as Markdown", action: exportChatAsMarkdown)
                    Button("Chat Appearance...") { showingAppearanceSheet = true }
                    Divider()
                    Button("Clear Chat", role: .destructive, action: clearMessages)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Messages area — takes all available vertical space so the input stays small
            if messages.isEmpty && !isStreaming {
                emptyChatState
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            let isThinking = isStreaming
                                && msg.id == messages.last?.id
                                && msg.role == .assistant
                                && msg.content.isEmpty
                            let folderAvatarPath: String? = currentSession?.folderId
                                .flatMap { fid in store.folders.first(where: { $0.id == fid })?.avatarPath }

                            ChatBubble(message: msg, isThinking: isThinking, folderAvatarPath: folderAvatarPath)
                                .id(msg.id)

                            // Show token/s and duration for assistant messages
                            if msg.role == .assistant && !msg.content.isEmpty,
                               let tps = msg.tokensPerSecond, let dur = msg.durationSeconds {
                                Text(String(format: "%.1f t/s · %.1fs", tps, dur))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: messages.last?.content) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            } // end if/else empty state

            Divider()

            // Attachment chips (shown above input when there are attachments)
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                attachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 32)
            }

            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                // Paperclip button
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(attachments.count >= 3 ? Color.secondary : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(attachments.count >= 3)
                .padding(.bottom, 8)

                // TextEditor con placeholder y altura dinámica (max 160px)
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Message... (⌘↵ to send)")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 36, maxHeight: 160)
                        .fixedSize(horizontal: false, vertical: true)
                        .disabled(isStreaming)
                }

                Button {
                    if isStreaming { cancelStream() } else { sendMessage() }
                } label: {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isStreaming ? Color.accentColor : (inputText.isEmpty ? Color.secondary : Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(!isStreaming && inputText.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty Chat State

    private var emptyChatState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Start a conversation")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            if let model = serverState.activeModelName {
                Text(model)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar Actions

    private func createNewChat() {
        // Auto-save previous session if it had messages
        if let session = currentSession, !messages.isEmpty {
            saveCurrentSession()
        }

        // Clear messages and reset session
        messages = []
        currentSession = nil
        inputText = ""
    }

    private func loadSession(_ session: ChatSession) {
        // Save current session if it has messages
        if let current = currentSession, !messages.isEmpty {
            saveCurrentSession()
        }

        // Load the selected session — skip system messages in the UI
        currentSession = session
        messages = session.messages
            .filter { $0.role != "system" }
            .map { pm in
                var msg = ChatMessage(role: roleFromString(pm.role), content: pm.content)
                msg.tokensPerSecond = pm.tokensPerSecond
                msg.durationSeconds = pm.durationSeconds
                msg.imageData = pm.imageBase64.flatMap { Data(base64Encoded: $0) }
                msg.textAttachmentNames = pm.textAttachmentNames
                return msg
            }
    }

    private func saveCurrentSession() {
        guard let model = serverState.activeModelName else { return }

        if var session = currentSession {
            // Update existing session
            session.messages = messages.map { msg in
                PersistedMessage(
                    id: msg.id,
                    role: stringFromRole(msg.role),
                    content: msg.content,
                    timestamp: Date(),
                    tokensPerSecond: msg.tokensPerSecond,
                    durationSeconds: msg.durationSeconds,
                    imageBase64: msg.imageData?.base64EncodedString(),
                    textAttachmentNames: msg.textAttachmentNames
                )
            }
            session.updatedAt = Date()
            store.save(session: session)
        } else if !messages.isEmpty {
            // Create new session from first user message
            let firstUserMessage = messages.first { $0.role == .user }
            let title = firstUserMessage?.content.prefix(50).trimmingCharacters(in: .whitespaces) ?? "New Chat"

            var newSession = store.createNewSession(withFirstMessage: String(title))
            newSession.modelId = model
            newSession.messages = messages.map { msg in
                PersistedMessage(
                    id: msg.id,
                    role: stringFromRole(msg.role),
                    content: msg.content,
                    timestamp: Date(),
                    tokensPerSecond: msg.tokensPerSecond,
                    durationSeconds: msg.durationSeconds,
                    imageBase64: msg.imageData?.base64EncodedString(),
                    textAttachmentNames: msg.textAttachmentNames
                )
            }

            store.save(session: newSession)
            currentSession = newSession
        }
    }

    private func createNewChatInFolder(_ folder: ChatFolder) {
        // Save current session if it has messages
        if !messages.isEmpty { saveCurrentSession() }

        // Build new session inside the folder
        var newSession = ChatSession(
            id: UUID(),
            title: "New Chat",
            folderId: folder.id,
            personaId: nil,
            modelId: serverState.activeModelName,
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )

        // Inject folder system prompt as a hidden system message if set
        if !folder.settings.systemPrompt.isEmpty {
            newSession.messages = [
                PersistedMessage(
                    id: UUID(),
                    role: "system",
                    content: folder.settings.systemPrompt,
                    timestamp: Date()
                )
            ]
        }

        store.save(session: newSession)

        // Show the folder in the sidebar and open the new chat
        selectedFolderId = folder.id
        currentSession = newSession
        messages = []   // system msg stored in session.messages but not shown in UI
        inputText = ""
    }

    private func toggleFolderSelection(_ folder: ChatFolder) {
        if selectedFolderId == folder.id {
            selectedFolderId = nil  // Deselect
        } else {
            selectedFolderId = folder.id  // Select this folder
        }
    }

    private var filteredSessions: [ChatSession] {
        if let folderId = selectedFolderId {
            return store.sessions.filter { $0.folderId == folderId }
        } else if let current = currentSession {
            // Show all sessions when no folder is selected, but highlight current
            return store.sessions.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            return store.sessions.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func startRenameFolder(_ folder: ChatFolder) {
        renamingFolderId = folder.id
        renameFolderText = folder.name
        renameFolderFocused = true
    }

    private func commitFolderRename(_ folder: ChatFolder) {
        let newName = renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty {
            store.rename(folder: folder, to: newName)
        }
        renamingFolderId = nil
    }

    private func deleteFolder(_ folder: ChatFolder) {
        store.delete(folder: folder)
    }

    private func renameSession(_ session: ChatSession) {
        renamingSessionId = session.id
        renameText = session.title
        renameFocused = true
    }

    private func commitRename(_ session: ChatSession) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty {
            var updated = session
            updated.title = newName
            store.save(session: updated)
            if currentSession?.id == session.id { currentSession = updated }
        }
        renamingSessionId = nil
    }

    private func deleteSession(_ session: ChatSession) {
        store.delete(session: session)
        if currentSession?.id == session.id {
            currentSession = nil
            messages = []
        }
    }

    private func showFolderPickerForSession(_ session: ChatSession) {
        guard !store.folders.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Folders"
            alert.informativeText = "Create a folder first using 'Manage Folders'."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Move to Folder"
        alert.informativeText = "Select a destination for this chat."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        popup.addItem(withTitle: "— Root (no folder) —")
        for folder in store.folders {
            popup.addItem(withTitle: folder.name)
        }
        // Pre-select current folder if set
        if let folderId = session.folderId,
           let idx = store.folders.firstIndex(where: { $0.id == folderId }) {
            popup.selectItem(at: idx + 1)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let selected = popup.indexOfSelectedItem
        if selected == 0 {
            store.move(session: session, to: nil)
        } else {
            store.move(session: session, to: store.folders[selected - 1])
        }
    }

    // MARK: - Chat Actions

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        guard let model = serverState.activeModelName else {
            showNoModelAlert = true
            return
        }

        let text = inputText
        inputText = ""

        let currentAttachments = attachments
        attachments = []  // clear immediately

        var userMsg = ChatMessage(role: .user, content: text)
        if let firstImage = currentAttachments.first(where: { $0.isImage }),
           case .image(_, let base64, _) = firstImage {
            userMsg.imageData = Data(base64Encoded: base64)
        }
        userMsg.textAttachmentNames = currentAttachments.compactMap {
            if case .text(let filename, _) = $0 { return filename }
            return nil
        }
        messages.append(userMsg)
        let assistant = ChatMessage(role: .assistant, content: "")
        messages.append(assistant)
        let assistantId = assistant.id

        isStreaming = true
        // Capture messages before the empty assistant placeholder for the API call
        var apiMessages = Array(messages.dropLast())

        // Always inject folder system prompt when session belongs to a folder
        if let folderId = currentSession?.folderId,
           let folder = store.folders.first(where: { $0.id == folderId }),
           !folder.settings.systemPrompt.isEmpty {
            apiMessages.insert(
                ChatMessage(role: .system, content: folder.settings.systemPrompt),
                at: 0
            )
        }

        streamTask = Task {
            let startTime = Date()
            var tokenCount = 0
            do {
                for try await token in APIClient.shared.streamChat(
                    model: model,
                    messages: apiMessages,
                    attachments: currentAttachments
                ) {
                    if Task.isCancelled { break }
                    tokenCount += 1
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += token
                        }
                    }
                }

                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }),
                       !messages[idx].content.isEmpty {
                        messages[idx].tokensPerSecond = duration > 0 ? Double(tokenCount) / duration : nil
                        messages[idx].durationSeconds = duration
                    }
                }

                // Auto-save after assistant response completes (metrics now set)
                saveCurrentSession()

            } catch {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }),
                       messages[idx].content.isEmpty {
                        messages[idx].content = "[Error: \(error.localizedDescription)]"
                    }
                }
            }
            await MainActor.run { isStreaming = false }
        }
    }

    private func cancelStream() {
        streamTask?.cancel()
        isStreaming = false
        // Remove the empty assistant placeholder if cancelled before first token arrived
        if messages.last?.role == .assistant && messages.last?.content.isEmpty == true {
            messages.removeLast()
        }
    }

    private func clearMessages() {
        // Save current session before clearing
        if !messages.isEmpty {
            saveCurrentSession()
        }
        messages = []
    }

    private func exportChatAsMarkdown() {
        guard !messages.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (currentSession?.title.isEmpty == false
            ? currentSession!.title : "chat") + ".md"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            var lines: [String] = []
            let title = self.currentSession?.title.isEmpty == false
                ? self.currentSession!.title : "Chat Export"
            lines.append("# \(title)")
            lines.append("")

            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            lines.append("*Exported: \(formatter.string(from: Date()))*")
            lines.append("")
            lines.append("---")
            lines.append("")

            for msg in self.messages {
                switch msg.role {
                case .user:
                    lines.append("**User:**")
                    lines.append("")
                    lines.append(msg.content)
                    lines.append("")
                case .assistant:
                    lines.append("**Assistant:**")
                    lines.append("")
                    lines.append(msg.content)
                    if let tps = msg.tokensPerSecond, let dur = msg.durationSeconds {
                        lines.append("")
                        lines.append(String(format: "*%.1f t/s · %.1fs*", tps, dur))
                    }
                    lines.append("")
                case .system:
                    continue
                }
                lines.append("---")
                lines.append("")
            }

            let content = lines.joined(separator: "\n")
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .plainText, .sourceCode, .json, .commaSeparatedText,
            .jpeg, .png, .gif, .webP, .pdf
        ] + ["swift", "py", "js", "ts", "md"].compactMap { UTType(filenameExtension: $0) }

        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls.prefix(3 - self.attachments.count)
            for url in urls {
                let ext = url.pathExtension.lowercased()
                let imageExts = ["jpg", "jpeg", "png", "gif", "webp"]
                if imageExts.contains(ext) {
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let base64 = data.base64EncodedString()
                    let mimeType = (ext == "jpg" || ext == "jpeg") ? "image/jpeg"
                        : ext == "png" ? "image/png"
                        : ext == "gif" ? "image/gif"
                        : "image/webp"
                    self.attachments.append(.image(filename: url.lastPathComponent, base64: base64, mimeType: mimeType))
                } else {
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    self.attachments.append(.text(filename: url.lastPathComponent, content: content))
                }
            }
        }
    }

    // MARK: - Helper Methods for Role Conversion

    private func roleFromString(_ roleString: String) -> ChatMessage.Role {
        switch roleString.lowercased() {
        case "user": return .user
        case "system": return .system
        default: return .assistant
        }
    }

    private func stringFromRole(_ role: ChatMessage.Role) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }
}

// MARK: - Supporting Views

struct ChatBubble: View {
    let message: ChatMessage
    var isThinking: Bool = false
    var folderAvatarPath: String? = nil

    @AppStorage("userBubbleColor")      private var userColorHex: String = "#1E4D8C"
    @AppStorage("assistantBubbleColor") private var assistantColorHex: String = ""

    private var userBubbleColor: Color {
        Color(hexString: userColorHex) ?? Color(NSColor.controlBackgroundColor)
    }
    private var assistantBubbleColor: Color {
        assistantColorHex.isEmpty ? .clear : (Color(hexString: assistantColorHex) ?? .clear)
    }

    var body: some View {
        switch message.role {
        case .user:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                userContent
                    .containerRelativeFrame(.horizontal) { w, _ in w * 0.75 }
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                // Avatar: folder image if available, else brain icon
                if let path = folderAvatarPath, let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                if isThinking {
                    ThinkingIndicator()
                        .padding(.vertical, 4)
                } else {
                    assistantContent
                }
                Spacer(minLength: 0)
            }
        case .system:
            EmptyView()
        }
    }

    @ViewBuilder private var userContent: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let data = message.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(userBubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !message.textAttachmentNames.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(message.textAttachmentNames, id: \.self) { name in
                        Label(name, systemImage: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data = message.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !message.content.isEmpty {
                Markdown(message.content)
                    .markdownTheme(.gitHub.text { ForegroundColor(.primary) })
                    .textSelection(.enabled)
                    .padding(assistantBubbleColor == .clear ? 0 : 10)
                    .background(assistantBubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: assistantBubbleColor == .clear ? 0 : 10))
            }
        }
    }
}

/// Three pulsing dots shown while waiting for the first token.
private struct ThinkingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Sidebar Row Views

private struct FolderRowView: View {
    let folder: ChatFolder
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let path = folder.avatarPath, let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
            } else {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 12))
            }
            Text(folder.name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}

private struct SessionRowView: View {
    let session: ChatSession
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title.isEmpty ? "New Chat" : session.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Text(formattedDate)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: session.updatedAt)
    }
}

private struct AttachmentChip: View {
    let attachment: AttachmentItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attachment.isImage ? "photo" : "doc.text")
                .font(.system(size: 10))
            Text(attachment.filename)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: 120)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }
}

// MARK: - Folders Manager Sheet

struct FoldersManagerView: View {
    @ObservedObject private var store = ChatStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Folders")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            // List
            if store.folders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No folders yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.folders) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(folder.name)
                                .font(.system(size: 13))
                            Spacer()
                            Button { renameFolder(folder) } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Rename")
                            Button { deleteFolder(folder) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Delete")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer — create
            Button(action: createFolder) {
                Label("New Folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(12)
        }
        .frame(width: 320, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Actions

    private func createFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter a name for the folder."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "Folder name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.save(folder: ChatFolder(name: name))
    }

    private func renameFolder(_ folder: ChatFolder) {
        let alert = NSAlert()
        alert.messageText = "Rename Folder"
        alert.informativeText = "Enter a new name for \"\(folder.name)\"."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = folder.name
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.rename(folder: folder, to: name)
    }

    private func deleteFolder(_ folder: ChatFolder) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(folder.name)\"?"
        alert.informativeText = "Sessions in this folder will be moved to root."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.delete(folder: folder)
    }
}

// MARK: - Chat Appearance Sheet

struct ChatAppearanceSheet: View {
    @AppStorage("userBubbleColor")      private var userColorHex: String = "#1E4D8C"
    @AppStorage("assistantBubbleColor") private var assistantColorHex: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat Appearance")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                ColorPicker("User message color", selection: userColorBinding, supportsOpacity: false)
                    .font(.system(size: 13))
                ColorPicker("Assistant message color", selection: assistantColorBinding, supportsOpacity: false)
                    .font(.system(size: 13))

                Button("Reset to defaults") {
                    userColorHex = "#1E4D8C"
                    assistantColorHex = ""
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(20)

            Spacer()
        }
        .frame(width: 320, height: 220)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var userColorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: userColorHex) ?? .blue },
            set: { userColorHex = $0.hexString() }
        )
    }

    private var assistantColorBinding: Binding<Color> {
        Binding(
            get: { assistantColorHex.isEmpty ? Color(NSColor.controlBackgroundColor) : (Color(hexString: assistantColorHex) ?? Color(NSColor.controlBackgroundColor)) },
            set: { assistantColorHex = $0.hexString() }
        )
    }
}

// MARK: - Color Hex Helpers

extension Color {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        self.init(
            .sRGB,
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255,
            opacity: 1
        )
    }

    func hexString() -> String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent   * 255),
                      Int(c.greenComponent * 255),
                      Int(c.blueComponent  * 255))
    }
}

#Preview {
    ChatView()
        .environmentObject(ServerStateViewModel())
}
