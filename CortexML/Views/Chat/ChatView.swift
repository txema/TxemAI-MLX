import SwiftUI
import UniformTypeIdentifiers
import MarkdownUI

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @ObservedObject private var store = ChatStore.shared
    @Environment(\.cortexTheme) private var t

    // Session state
    @State private var currentSession: ChatSession? = nil
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamTask: Task<Void, Never>? = nil

    // Sidebar state
    @State private var selectedFolderId: UUID? = nil
    @State private var showingPersonasSheet = false
    @State private var showingFoldersSheet = false

    // Inline rename — sessions
    @State private var renamingSessionId: UUID? = nil
    @State private var renameText: String = ""
    @FocusState private var renameFocused: Bool

    // Inline rename — folders
    @State private var renamingFolderId: UUID? = nil
    @State private var renameFolderText: String = ""
    @FocusState private var renameFolderFocused: Bool

    // Folder settings sheet
    @State private var selectedFolderForSettings: ChatFolder? = nil

    // Attachments
    @State private var attachments: [AttachmentItem] = []

    // Alerts
    @State private var showNoModelAlert: Bool = false

    // Phase-2 state
    @State private var showParamsPanel: Bool = false
    @State private var showSearchBar: Bool = false
    @State private var showSystemPrompt: Bool = false
    @State private var searchQuery: String = ""
    @State private var temperature: Double = 0.7
    @State private var topP: Double = 0.9
    @State private var maxTokens: Int = 4096

    // Phase-3 — inline edit state
    @State private var editingMessageId: UUID? = nil
    @State private var editText: String = ""

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            sidebarPanel
            Rectangle().fill(t.bd).frame(width: 1)
            chatMainPanel
            if showParamsPanel {
                ParametersPanelView(
                    temperature: $temperature,
                    topP: $topP,
                    maxTokens: $maxTokens,
                    messageCount: messages.filter { $0.role != .system }.count,
                    totalTokens: estimatedTotalTokens,
                    contextUsed: estimatedTotalTokens,
                    onFork: {
                        if let last = messages.last(where: { $0.role == .assistant }) {
                            regenMessage(last)
                        }
                    },
                    onRegenerate: {
                        if let last = messages.last(where: { $0.role == .assistant }) {
                            regenMessage(last)
                        }
                    },
                    onExportMD: exportChatAsMarkdown,
                    onClear: clearMessages
                )
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .background(t.win)
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
    }

    // MARK: - Sidebar (168 px)

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            // New Chat button
            Button(action: createNewChat) {
                Text("New Chat")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(t.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .shadow(color: t.accent.opacity(0.27), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Rectangle().fill(t.bd).frame(height: 1)

            if store.sessions.isEmpty && store.folders.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundStyle(t.t4)
                    Text("No chats yet")
                        .font(.system(size: 11.5))
                        .foregroundStyle(t.t4)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Folders
                        if !store.folders.isEmpty {
                            sidebarSectionHeader("FOLDERS")
                            ForEach(store.folders) { folder in
                                if renamingFolderId == folder.id {
                                    TextField("Folder name", text: $renameFolderText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(t.t1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(t.aL)
                                        .focused($renameFolderFocused)
                                        .onSubmit { commitFolderRename(folder) }
                                        .onExitCommand { renamingFolderId = nil }
                                } else {
                                    SidebarFolderRow(
                                        folder: folder,
                                        isSelected: selectedFolderId == folder.id
                                    )
                                    .onTapGesture { toggleFolderSelection(folder) }
                                    .contextMenu {
                                        Button("Add Chat to Folder") { createNewChatInFolder(folder) }
                                        Divider()
                                        Button("Folder Settings") { selectedFolderForSettings = folder }
                                        Divider()
                                        Button("Rename") { startRenameFolder(folder) }
                                        Button("Delete", role: .destructive) { deleteFolder(folder) }
                                    }
                                }
                            }
                            Rectangle().fill(t.bd).frame(height: 1).padding(.vertical, 4)
                        }

                        // Sessions
                        sidebarSectionHeader("RECENT")
                        ForEach(filteredSessions) { session in
                            if renamingSessionId == session.id {
                                TextField("Chat name", text: $renameText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(t.t1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(t.aL)
                                    .focused($renameFocused)
                                    .onSubmit { commitRename(session) }
                                    .onExitCommand { renamingSessionId = nil }
                            } else {
                                SidebarSessionRow(
                                    session: session,
                                    isActive: currentSession?.id == session.id
                                )
                                .onTapGesture { loadSession(session) }
                                .contextMenu {
                                    Button("Rename") { renameSession(session) }
                                    Button("Move to Folder") { showFolderPickerForSession(session) }
                                    Button("Delete", role: .destructive) { deleteSession(session) }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle().fill(t.bd).frame(height: 1)

            // Footer: Manage Folders
            Button("Manage Folders") { showingFoldersSheet = true }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(t.t4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 168)
        .background(t.side)
    }

    @ViewBuilder
    private func sidebarSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.08 * 9.5)
            .foregroundStyle(t.lbl)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: - Main Chat Panel

    private var chatMainPanel: some View {
        VStack(spacing: 0) {
            modelStrip
            if showSearchBar  { searchBarView }
            if showSystemPrompt { systemPromptPanel }
            Rectangle().fill(t.bd).frame(height: 1)
            messagesArea
            if !attachments.isEmpty { attachmentChipsRow }
            inputArea
        }
        .background(t.win)
    }

    // MARK: Model Strip

    private var modelStrip: some View {
        HStack(spacing: 8) {
            // Active dot
            Circle()
                .fill(serverState.activeModelName != nil ? t.accent : t.t4)
                .frame(width: 7, height: 7)
                .shadow(color: serverState.activeModelName != nil ? t.accent.opacity(0.5) : .clear,
                        radius: 3)
            Text(serverState.activeModelName ?? "no model loaded")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.t1)
                .lineLimit(1)
            Spacer()
            // Token count
            if estimatedTotalTokens > 0 {
                Text("\(estimatedTotalTokens) tokens")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(t.t4)
            }
            // Toolbar buttons
            toolbarButton("magnifyingglass") { withAnimation(.easeInOut(duration: 0.15)) { showSearchBar.toggle() } }
            toolbarButton("text.alignleft")  { withAnimation(.easeInOut(duration: 0.15)) { showSystemPrompt.toggle() } }
            toolbarButton("slider.horizontal.3") { withAnimation(.easeInOut(duration: 0.15)) { showParamsPanel.toggle() } }
            Menu {
                Button("Export as Markdown", action: exportChatAsMarkdown)
                Divider()
                Button("Clear Chat", role: .destructive, action: clearMessages)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(t.t3)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(t.win)
    }

    @ViewBuilder
    private func toolbarButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(t.t3)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    // MARK: Search Bar

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(t.t4)
            TextField("Search messages…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(t.t1)
            if !searchQuery.isEmpty {
                Text("\(searchResultCount) results")
                    .font(.system(size: 10))
                    .foregroundStyle(t.t4)
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.t4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(t.win)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.bd).frame(height: 1)
        }
    }

    private var searchResultCount: Int {
        guard !searchQuery.isEmpty else { return 0 }
        return messages.filter { $0.content.localizedCaseInsensitiveContains(searchQuery) }.count
    }

    // MARK: System Prompt Panel

    private var systemPromptPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SYSTEM PROMPT")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.07 * 9.5)
                .foregroundStyle(Color(hex: "#92400e"))
            TextEditor(text: systemPromptBinding)
                .font(.system(size: 11))
                .frame(height: 48)
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: "#fde68a"), lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: "#fffbeb"))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: "#fde68a")).frame(height: 1)
        }
    }

    private var systemPromptBinding: Binding<String> {
        Binding(
            get: {
                if let folderId = currentSession?.folderId,
                   let folder = store.folders.first(where: { $0.id == folderId }) {
                    return folder.settings.systemPrompt
                }
                return ""
            },
            set: { newValue in
                guard let fId = currentSession?.folderId,
                      let idx = store.folders.firstIndex(where: { $0.id == fId }) else { return }
                var updated = store.folders[idx]
                updated.settings.systemPrompt = newValue
                store.save(folder: updated)
            }
        )
    }

    // MARK: Messages Area

    @ViewBuilder
    private var messagesArea: some View {
        let displayMessages = filteredMessages
        if displayMessages.isEmpty && !isStreaming {
            emptyChatState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(displayMessages) { msg in
                            let isThinking = isStreaming
                                && msg.id == messages.last?.id
                                && msg.role == .assistant
                                && msg.content.isEmpty
                            ChatBubble(
                                message: msg,
                                isThinking: isThinking,
                                isEditing: editingMessageId == msg.id,
                                editText: $editText,
                                onCopy:   { copyMessage(msg) },
                                onFork:   { regenMessage(msg) },
                                onRegen:  { regenMessage(msg) },
                                onEdit:   {
                                    editText = msg.content
                                    editingMessageId = msg.id
                                },
                                onEditSubmit:  { submitEdit() },
                                onEditCancel:  { editingMessageId = nil },
                                onPrevVariant: { navigateVariant(msg, delta: -1) },
                                onNextVariant: { navigateVariant(msg, delta: +1) }
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: messages.last?.content) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var filteredMessages: [ChatMessage] {
        let base = messages.filter { $0.role != .system }
        guard showSearchBar && !searchQuery.isEmpty else { return base }
        return base.filter { $0.content.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var emptyChatState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(t.t4)
            Text("Start a conversation")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(t.t3)
            if let model = serverState.activeModelName {
                Text(model)
                    .font(.system(size: 11))
                    .foregroundStyle(t.t4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Attachment Chips

    private var attachmentChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        attachments.removeAll { $0.id == attachment.id }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(t.win)
        .overlay(alignment: .top) {
            Rectangle().fill(t.bd).frame(height: 1)
        }
    }

    // MARK: Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.bd).frame(height: 1)
            VStack(spacing: 4) {
                // Input container
                HStack(alignment: .bottom, spacing: 6) {
                    // Image attach
                    Button { openFilePicker(imageOnly: true) } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(t.t4)
                    }
                    .buttonStyle(.plain)
                    .disabled(attachments.count >= 3)
                    .padding(.bottom, 2)

                    // File attach
                    Button { openFilePicker(imageOnly: false) } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14))
                            .foregroundStyle(attachments.count >= 3 ? t.t5 : t.t4)
                    }
                    .buttonStyle(.plain)
                    .disabled(attachments.count >= 3)
                    .padding(.bottom, 2)

                    // TextEditor
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Message… (⌘↵ to send)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(t.t4)
                                .padding(.horizontal, 2)
                                .padding(.vertical, 1)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $inputText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(t.t1)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: 20, maxHeight: 100)
                            .fixedSize(horizontal: false, vertical: true)
                            .disabled(isStreaming)
                    }

                    // Send / Stop button
                    Button {
                        if isStreaming { cancelStream() } else { sendMessage() }
                    } label: {
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(sendButtonFg)
                            .frame(width: 28, height: 28)
                            .background(sendButtonBg)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .shadow(color: sendButtonShadow, radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && inputText.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(t.inp)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(t.inpBd, lineWidth: 1))

                // Footer row: param summary + token counter
                HStack {
                    HStack(spacing: 8) {
                        paramLabel("T", String(format: "%.2f", temperature))
                        paramLabel("Top-P", String(format: "%.2f", topP))
                        paramLabel("Max", "\(maxTokens)")
                    }
                    Spacer()
                    Text("\(inputText.count) / \(maxTokens)")
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(t.t4)
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(t.win)
    }

    @ViewBuilder
    private func paramLabel(_ name: String, _ value: String) -> some View {
        (Text(name + " ").foregroundStyle(t.t4)
         + Text(value).foregroundStyle(t.t3).fontWeight(.semibold))
            .font(.system(size: 9.5, design: .monospaced))
    }

    private var sendButtonBg: Color {
        (isStreaming || !inputText.isEmpty) ? t.accent : Color(hex: "#e8eaed")
    }
    private var sendButtonFg: Color {
        (isStreaming || !inputText.isEmpty) ? .white : Color(hex: "#b0b8c4")
    }
    private var sendButtonShadow: Color {
        (isStreaming || !inputText.isEmpty) ? t.accent.opacity(0.27) : .clear
    }

    // MARK: - Computed helpers

    private var estimatedTotalTokens: Int {
        messages.reduce(0) { acc, msg in
            if let tps = msg.tokensPerSecond, let dur = msg.durationSeconds {
                return acc + Int(tps * dur)
            }
            return acc
        }
    }

    // MARK: - Business Logic (preserved from original)

    private func createNewChat() {
        if currentSession != nil && !messages.isEmpty { saveCurrentSession() }
        messages = []; currentSession = nil; inputText = ""
    }

    private func loadSession(_ session: ChatSession) {
        if currentSession != nil && !messages.isEmpty { saveCurrentSession() }
        currentSession = session
        editingMessageId = nil
        messages = session.messages
            .filter { $0.role != "system" }
            .map { pm in
                var msg = ChatMessage(role: roleFromString(pm.role), content: pm.content)
                msg.tokensPerSecond = pm.tokensPerSecond
                msg.durationSeconds = pm.durationSeconds
                msg.imageData = pm.imageBase64.flatMap { Data(base64Encoded: $0) }
                msg.textAttachmentNames = pm.textAttachmentNames
                msg.contentVariants = pm.contentVariants
                msg.activeVariant   = pm.activeVariant
                return msg
            }
    }

    private func saveCurrentSession() {
        guard let model = serverState.activeModelName else { return }
        if var session = currentSession {
            session.messages = messages.map { toPersistedMessage($0) }
            session.updatedAt = Date()
            store.save(session: session)
        } else if !messages.isEmpty {
            let firstUser = messages.first { $0.role == .user }
            let title = firstUser?.content.prefix(50).trimmingCharacters(in: .whitespaces) ?? "New Chat"
            var newSession = store.createNewSession(withFirstMessage: String(title))
            newSession.modelId = model
            newSession.messages = messages.map { toPersistedMessage($0) }
            store.save(session: newSession)
            currentSession = newSession
        }
    }

    private func toPersistedMessage(_ msg: ChatMessage) -> PersistedMessage {
        PersistedMessage(
            id: msg.id, role: stringFromRole(msg.role), content: msg.content,
            timestamp: Date(), tokensPerSecond: msg.tokensPerSecond,
            durationSeconds: msg.durationSeconds,
            imageBase64: msg.imageData?.base64EncodedString(),
            textAttachmentNames: msg.textAttachmentNames,
            contentVariants: msg.contentVariants,
            activeVariant: msg.activeVariant
        )
    }

    private func createNewChatInFolder(_ folder: ChatFolder) {
        if !messages.isEmpty { saveCurrentSession() }
        var newSession = ChatSession(
            id: UUID(), title: "New Chat", folderId: folder.id,
            personaId: nil, modelId: serverState.activeModelName,
            createdAt: Date(), updatedAt: Date(), messages: []
        )
        if !folder.settings.systemPrompt.isEmpty {
            newSession.messages = [PersistedMessage(
                id: UUID(), role: "system", content: folder.settings.systemPrompt, timestamp: Date()
            )]
        }
        store.save(session: newSession)
        selectedFolderId = folder.id
        currentSession = newSession
        messages = []; inputText = ""
    }

    private func toggleFolderSelection(_ folder: ChatFolder) {
        selectedFolderId = selectedFolderId == folder.id ? nil : folder.id
    }

    private var filteredSessions: [ChatSession] {
        let base = selectedFolderId != nil
            ? store.sessions.filter { $0.folderId == selectedFolderId }
            : store.sessions
        return base.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func startRenameFolder(_ folder: ChatFolder) {
        renamingFolderId = folder.id; renameFolderText = folder.name; renameFolderFocused = true
    }
    private func commitFolderRename(_ folder: ChatFolder) {
        let n = renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { store.rename(folder: folder, to: n) }
        renamingFolderId = nil
    }
    private func deleteFolder(_ folder: ChatFolder)  { store.delete(folder: folder) }
    private func renameSession(_ session: ChatSession) {
        renamingSessionId = session.id; renameText = session.title; renameFocused = true
    }
    private func commitRename(_ session: ChatSession) {
        let n = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty {
            var u = session; u.title = n; store.save(session: u)
            if currentSession?.id == session.id { currentSession = u }
        }
        renamingSessionId = nil
    }
    private func deleteSession(_ session: ChatSession) {
        store.delete(session: session)
        if currentSession?.id == session.id { currentSession = nil; messages = [] }
    }
    private func showFolderPickerForSession(_ session: ChatSession) {
        guard !store.folders.isEmpty else {
            let a = NSAlert(); a.messageText = "No Folders"
            a.informativeText = "Create a folder first."; a.alertStyle = .informational
            a.addButton(withTitle: "OK"); a.runModal(); return
        }
        let alert = NSAlert(); alert.messageText = "Move to Folder"
        alert.informativeText = "Select a destination."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move"); alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        popup.addItem(withTitle: "— Root (no folder) —")
        for f in store.folders { popup.addItem(withTitle: f.name) }
        if let fId = session.folderId, let idx = store.folders.firstIndex(where: { $0.id == fId }) {
            popup.selectItem(at: idx + 1)
        }
        alert.accessoryView = popup
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let sel = popup.indexOfSelectedItem
        store.move(session: session, to: sel == 0 ? nil : store.folders[sel - 1])
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        guard let model = serverState.activeModelName else { showNoModelAlert = true; return }
        let text = inputText; inputText = ""
        let currentAttachments = attachments; attachments = []
        var userMsg = ChatMessage(role: .user, content: text)
        if let img = currentAttachments.first(where: { $0.isImage }),
           case .image(_, let b64, _) = img { userMsg.imageData = Data(base64Encoded: b64) }
        userMsg.textAttachmentNames = currentAttachments.compactMap {
            if case .text(let name, _) = $0 { return name }; return nil
        }
        messages.append(userMsg)
        let assistant = ChatMessage(role: .assistant, content: "")
        messages.append(assistant)
        var apiMessages = Array(messages.dropLast())
        injectSystemPrompt(into: &apiMessages)
        startStreaming(model: model, context: apiMessages,
                       attachments: currentAttachments, assistantId: assistant.id)
    }

    // MARK: - Shared streaming engine

    private func startStreaming(model: String,
                                context: [ChatMessage],
                                attachments: [AttachmentItem] = [],
                                assistantId: UUID) {
        isStreaming = true
        streamTask = Task {
            let start = Date(); var count = 0
            do {
                for try await token in APIClient.shared.streamChat(
                    model: model, messages: context, attachments: attachments,
                    temperature: temperature, topP: topP, maxTokens: maxTokens
                ) {
                    if Task.isCancelled { break }
                    count += 1
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += token
                            // Keep variants array in sync during branched streaming
                            if !messages[idx].contentVariants.isEmpty {
                                messages[idx].contentVariants[messages[idx].activeVariant] += token
                            }
                        }
                    }
                }
                let dur = Date().timeIntervalSince(start)
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }),
                       !messages[idx].content.isEmpty {
                        messages[idx].tokensPerSecond = dur > 0 ? Double(count) / dur : nil
                        messages[idx].durationSeconds = dur
                    }
                }
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

    private func injectSystemPrompt(into msgs: inout [ChatMessage]) {
        if let fId = currentSession?.folderId,
           let folder = store.folders.first(where: { $0.id == fId }),
           !folder.settings.systemPrompt.isEmpty {
            msgs.insert(ChatMessage(role: .system, content: folder.settings.systemPrompt), at: 0)
        }
    }

    // MARK: - Phase-3 Branch Operations

    /// Regenerate / Fork: creates a new variant of an assistant message.
    private func regenMessage(_ msg: ChatMessage) {
        guard !isStreaming else { return }
        guard let model = serverState.activeModelName else { showNoModelAlert = true; return }
        guard let idx = messages.firstIndex(where: { $0.id == msg.id }),
              messages[idx].role == .assistant else { return }

        var m = messages[idx]
        if m.contentVariants.isEmpty {
            // First regen: seed variants with the original content
            m.contentVariants = [m.content]
            m.activeVariant   = 0
        }
        // Append new empty slot and make it active
        m.contentVariants.append("")
        m.activeVariant = m.contentVariants.count - 1
        m.content = ""
        m.tokensPerSecond = nil
        m.durationSeconds = nil
        messages[idx] = m
        // Truncate continuation after this message
        messages = Array(messages[...idx])

        var context = Array(messages[..<idx])
        injectSystemPrompt(into: &context)
        startStreaming(model: model, context: context, assistantId: msg.id)
    }

    /// Edit a user message inline: saves old content as a variant, replaces content,
    /// truncates continuation and re-generates.
    private func submitEdit() {
        guard let editId = editingMessageId,
              let idx = messages.firstIndex(where: { $0.id == editId }) else {
            editingMessageId = nil; return
        }
        guard let model = serverState.activeModelName else { showNoModelAlert = true; return }
        let newContent = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty, newContent != messages[idx].content else {
            editingMessageId = nil; return
        }

        var m = messages[idx]
        if m.contentVariants.isEmpty {
            m.contentVariants = [m.content]
            m.activeVariant   = 0
        }
        m.contentVariants.append(newContent)
        m.activeVariant = m.contentVariants.count - 1
        m.content = newContent
        messages[idx] = m
        messages = Array(messages[...idx])
        editingMessageId = nil

        // Fresh assistant placeholder
        let assistant = ChatMessage(role: .assistant, content: "")
        messages.append(assistant)
        var context = Array(messages.dropLast())
        injectSystemPrompt(into: &context)
        startStreaming(model: model, context: context, assistantId: assistant.id)
    }

    /// Navigate between message content variants (delta: -1 older, +1 newer).
    private func navigateVariant(_ msg: ChatMessage, delta: Int) {
        guard let idx = messages.firstIndex(where: { $0.id == msg.id }) else { return }
        var m = messages[idx]
        guard m.hasBranches else { return }
        let newVariant = m.activeVariant + delta
        guard newVariant >= 0 && newVariant < m.contentVariants.count else { return }
        m.content       = m.contentVariants[newVariant]
        m.activeVariant = newVariant
        messages[idx]   = m
        // Truncate continuation when switching variant
        messages = Array(messages[...idx])
        saveCurrentSession()
    }

    private func cancelStream() {
        streamTask?.cancel(); isStreaming = false
        if messages.last?.role == .assistant && messages.last?.content.isEmpty == true {
            messages.removeLast()
        }
    }

    private func clearMessages() {
        if !messages.isEmpty { saveCurrentSession() }
        messages = []
    }

    private func copyMessage(_ msg: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(msg.content, forType: .string)
    }

    private func exportChatAsMarkdown() {
        guard !messages.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (currentSession?.title.isEmpty == false ? currentSession!.title : "chat") + ".md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var lines: [String] = ["# \(self.currentSession?.title ?? "Chat Export")", ""]
            let fmt = DateFormatter(); fmt.dateStyle = .long; fmt.timeStyle = .short
            lines += ["*Exported: \(fmt.string(from: Date()))*", "", "---", ""]
            for msg in self.messages {
                switch msg.role {
                case .user:
                    lines += ["**User:**", "", msg.content, ""]
                case .assistant:
                    var block = ["**Assistant:**", "", msg.content]
                    if let tps = msg.tokensPerSecond, let dur = msg.durationSeconds {
                        block.append(String(format: "\n*%.1f t/s · %.1fs*", tps, dur))
                    }
                    lines += block + [""]
                case .system: continue
                }
                lines += ["---", ""]
            }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func openFilePicker(imageOnly: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if imageOnly {
            panel.allowedContentTypes = [.jpeg, .png, .gif, .webP]
        } else {
            panel.allowedContentTypes = [
                .plainText, .sourceCode, .json, .commaSeparatedText, .pdf
            ] + ["swift", "py", "js", "ts", "md"].compactMap { UTType(filenameExtension: $0) }
        }
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls.prefix(3 - self.attachments.count)
            for url in urls {
                let ext = url.pathExtension.lowercased()
                let imgExts = ["jpg","jpeg","png","gif","webp"]
                if imgExts.contains(ext) {
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let mime = (ext == "jpg" || ext == "jpeg") ? "image/jpeg"
                        : ext == "png" ? "image/png" : ext == "gif" ? "image/gif" : "image/webp"
                    self.attachments.append(.image(filename: url.lastPathComponent,
                                                   base64: data.base64EncodedString(), mimeType: mime))
                } else {
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    self.attachments.append(.text(filename: url.lastPathComponent, content: content))
                }
            }
        }
    }

    private func roleFromString(_ s: String) -> ChatMessage.Role {
        switch s.lowercased() { case "user": .user; case "system": .system; default: .assistant }
    }
    private func stringFromRole(_ r: ChatMessage.Role) -> String {
        switch r { case .user: "user"; case .assistant: "assistant"; case .system: "system" }
    }
}

// MARK: - ChatBubble

struct ChatBubble: View {
    let message: ChatMessage
    var isThinking: Bool = false
    var isEditing: Bool = false
    @Binding var editText: String
    var onCopy:        () -> Void = {}
    var onFork:        () -> Void = {}
    var onRegen:       () -> Void = {}
    var onEdit:        () -> Void = {}
    var onEditSubmit:  () -> Void = {}
    var onEditCancel:  () -> Void = {}
    var onPrevVariant: () -> Void = {}
    var onNextVariant: () -> Void = {}

    // Convenience init — use when edit binding is not needed
    init(message: ChatMessage,
         isThinking: Bool = false,
         onCopy: @escaping () -> Void = {},
         onFork: @escaping () -> Void = {},
         onRegen: @escaping () -> Void = {},
         onEdit: @escaping () -> Void = {},
         onPrevVariant: @escaping () -> Void = {},
         onNextVariant: @escaping () -> Void = {}) {
        self.message = message
        self.isThinking = isThinking
        self.isEditing = false
        self._editText = .constant("")
        self.onCopy = onCopy
        self.onFork = onFork
        self.onRegen = onRegen
        self.onEdit = onEdit
        self.onPrevVariant = onPrevVariant
        self.onNextVariant = onNextVariant
    }

    // Full init — use from ChatView where edit state is managed
    init(message: ChatMessage,
         isThinking: Bool = false,
         isEditing: Bool,
         editText: Binding<String>,
         onCopy:        @escaping () -> Void = {},
         onFork:        @escaping () -> Void = {},
         onRegen:       @escaping () -> Void = {},
         onEdit:        @escaping () -> Void = {},
         onEditSubmit:  @escaping () -> Void = {},
         onEditCancel:  @escaping () -> Void = {},
         onPrevVariant: @escaping () -> Void = {},
         onNextVariant: @escaping () -> Void = {}) {
        self.message = message
        self.isThinking = isThinking
        self.isEditing = isEditing
        self._editText = editText
        self.onCopy = onCopy
        self.onFork = onFork
        self.onRegen = onRegen
        self.onEdit = onEdit
        self.onEditSubmit = onEditSubmit
        self.onEditCancel = onEditCancel
        self.onPrevVariant = onPrevVariant
        self.onNextVariant = onNextVariant
    }

    @Environment(\.cortexTheme) private var t
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 0) {
            switch message.role {
            case .user:      userBubble
            case .assistant: assistantBubble
            case .system:    EmptyView()
            }
            if (isHovered || isEditing) && message.role != .system {
                messageFooter
                    .transition(.opacity)
            }
        }
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
    }

    // MARK: User bubble

    @ViewBuilder
    private var userBubble: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let data = message.imageData, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if isEditing {
                    // Inline edit editor
                    VStack(alignment: .trailing, spacing: 4) {
                        TextEditor(text: $editText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(t.t1)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: 32, maxHeight: 120)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(t.aL)
                            .clipShape(UnevenRoundedRectangle(cornerRadii:
                                .init(topLeading: 14, bottomLeading: 14, bottomTrailing: 4, topTrailing: 14)))
                            .overlay(
                                UnevenRoundedRectangle(cornerRadii:
                                    .init(topLeading: 14, bottomLeading: 14, bottomTrailing: 4, topTrailing: 14))
                                .stroke(t.accent.opacity(0.5), lineWidth: 1.5)
                            )
                        HStack(spacing: 6) {
                            Button("Cancel", action: onEditCancel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(t.t3)
                                .buttonStyle(.plain)
                            Button("Send", action: onEditSubmit)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(t.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .buttonStyle(.plain)
                        }
                    }
                } else if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(t.accent)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(t.aL)
                        .clipShape(UnevenRoundedRectangle(cornerRadii:
                            .init(topLeading: 14, bottomLeading: 14, bottomTrailing: 4, topTrailing: 14)))
                        .overlay(
                            UnevenRoundedRectangle(cornerRadii:
                                .init(topLeading: 14, bottomLeading: 14, bottomTrailing: 4, topTrailing: 14))
                            .stroke(t.aB, lineWidth: 1)
                        )
                }
                if !message.textAttachmentNames.isEmpty {
                    ForEach(message.textAttachmentNames, id: \.self) { name in
                        Label(name, systemImage: "doc.text")
                            .font(.system(size: 10.5))
                            .foregroundStyle(t.t3)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(t.btnBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxWidth: UIConstants.userBubbleMaxFraction, alignment: .trailing)
        }
    }

    // MARK: Assistant bubble

    @ViewBuilder
    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [t.accent, t.accent.opacity(0.73)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: t.accent.opacity(0.27), radius: 3)
                Text("G")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)

            if isThinking {
                ThinkingIndicator().padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Markdown(message.content)
                        .markdownTheme(
                            .gitHub
                            .text { ForegroundColor(t.t1); FontSize(12.5) }
                            .code { FontFamilyVariant(.monospaced); FontSize(10.5); BackgroundColor(t.btnBg) }
                        )
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(t.card)
                        .clipShape(UnevenRoundedRectangle(cornerRadii:
                            .init(topLeading: 4, bottomLeading: 14, bottomTrailing: 14, topTrailing: 14)))
                        .overlay(
                            UnevenRoundedRectangle(cornerRadii:
                                .init(topLeading: 4, bottomLeading: 14, bottomTrailing: 14, topTrailing: 14))
                            .stroke(t.bd, lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Message footer (hover-revealed)

    @ViewBuilder
    private var messageFooter: some View {
        HStack(spacing: 6) {
            if message.role == .assistant {
                // Stats
                if let tps = message.tokensPerSecond, let dur = message.durationSeconds {
                    Text(String(format: "%.1f t/s · %.1fs", tps, dur))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(t.t4)
                }
                // Branch nav
                if message.hasBranches {
                    branchNavControl
                }
                Spacer()
                footerActionButton("⎇ Fork",  onFork)
                footerActionButton("↺ Regen", onRegen)
                footerActionButton("⎘ Copy",  onCopy)
            } else {
                // Branch nav for user edits
                if message.hasBranches {
                    branchNavControl
                }
                Spacer()
                if !isEditing {
                    footerActionButton("✎ Edit", onEdit)
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, message.role == .user ? 0 : 34)
    }

    @ViewBuilder
    private var branchNavControl: some View {
        HStack(spacing: 2) {
            Button(action: onPrevVariant) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(message.activeVariant > 0 ? t.t3 : t.t5)
            }
            .buttonStyle(.plain)
            .disabled(message.activeVariant == 0)

            Text("\(message.activeVariant + 1) / \(message.totalVariants)")
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(t.t3)
                .frame(minWidth: 30)

            Button(action: onNextVariant) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(message.activeVariant < message.totalVariants - 1 ? t.t3 : t.t5)
            }
            .buttonStyle(.plain)
            .disabled(message.activeVariant >= message.totalVariants - 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(t.btnBg)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.bd, lineWidth: 1))
    }

    @ViewBuilder
    private func footerActionButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(t.t3)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(t.btnBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.bd, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - UIConstants

private enum UIConstants {
    static let userBubbleMaxFraction: CGFloat = 0.72
}

// MARK: - ThinkingIndicator

private struct ThinkingIndicator: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                               value: animate)
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Sidebar Row Views

private struct SidebarFolderRow: View {
    let folder: ChatFolder
    let isSelected: Bool
    @Environment(\.cortexTheme) private var t

    var body: some View {
        HStack(spacing: 6) {
            Text(isSelected ? "▾" : "▸")
                .font(.system(size: 8))
                .foregroundStyle(t.t4)
            if let path = folder.avatarPath, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 14, height: 14).clipShape(Circle())
            } else {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? t.accent : t.t3)
            }
            Text(folder.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(t.t2)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? t.aL : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(t.accent).frame(width: 2.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
}

private struct SidebarSessionRow: View {
    let session: ChatSession
    let isActive: Bool
    @Environment(\.cortexTheme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title.isEmpty ? "New Chat" : session.title)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? t.accent : t.t2)
                .lineLimit(2)
            Text(formattedDate)
                .font(.system(size: 9.5))
                .foregroundStyle(t.t4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? t.aL : Color.clear)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle().fill(t.accent).frame(width: 2.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }

    private var formattedDate: String {
        let f = DateFormatter(); f.dateStyle = .short; return f.string(from: session.updatedAt)
    }
}

private struct AttachmentChip: View {
    let attachment: AttachmentItem
    let onRemove: () -> Void
    @Environment(\.cortexTheme) private var t

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attachment.isImage ? "photo" : "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(t.t3)
            Text(attachment.filename)
                .font(.system(size: 11))
                .foregroundStyle(t.t2)
                .lineLimit(1).frame(maxWidth: 120)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(t.t4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(t.btnBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.bd, lineWidth: 1))
    }
}

// MARK: - FoldersManagerView

struct FoldersManagerView: View {
    @ObservedObject private var store = ChatStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cortexTheme) private var t

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Folders")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.t1)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Rectangle().fill(t.bd).frame(height: 1)
            if store.folders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(t.t4)
                    Text("No folders yet").font(.system(size: 13)).foregroundStyle(t.t3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.folders) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(t.t3)
                            Text(folder.name).font(.system(size: 13)).foregroundStyle(t.t2)
                            Spacer()
                            Button { renameFolder(folder) } label: {
                                Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(t.t3)
                            }.buttonStyle(.plain)
                            Button { deleteFolder(folder) } label: {
                                Image(systemName: "trash").font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "#ef4444").opacity(0.8))
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.plain)
            }
            Rectangle().fill(t.bd).frame(height: 1)
            Button(action: createFolder) {
                Label("New Folder", systemImage: "folder.badge.plus").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(t.accent)
            .frame(maxWidth: .infinity)
            .padding(12)
        }
        .frame(width: 320, height: 400)
        .background(t.win)
    }

    private func createFolder() {
        let a = NSAlert(); a.messageText = "New Folder"; a.alertStyle = .informational
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.placeholderString = "Folder name"; a.accessoryView = tf
        a.window.initialFirstResponder = tf
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { store.save(folder: ChatFolder(name: n)) }
    }
    private func renameFolder(_ folder: ChatFolder) {
        let a = NSAlert(); a.messageText = "Rename Folder"; a.alertStyle = .informational
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.stringValue = folder.name; a.accessoryView = tf
        a.window.initialFirstResponder = tf
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { store.rename(folder: folder, to: n) }
    }
    private func deleteFolder(_ folder: ChatFolder) {
        let a = NSAlert(); a.messageText = "Delete \"\(folder.name)\"?"
        a.informativeText = "Sessions will be moved to root."; a.alertStyle = .warning
        a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        if a.runModal() == .alertFirstButtonReturn { store.delete(folder: folder) }
    }
}

#Preview {
    ChatView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 520, height: 720)
}
