import SwiftUI
import UniformTypeIdentifiers

/// Sheet for editing the system prompt and sampling overrides of a folder.
struct FolderSettingsSheet: View {
    let folder: ChatFolder
    @ObservedObject private var store = ChatStore.shared
    @Environment(\.dismiss) private var dismiss

    // Local editable state — committed only on Save
    @State private var systemPrompt: String
    @State private var tempEnabled: Bool
    @State private var tempValue: Double
    @State private var topPEnabled: Bool
    @State private var topPValue: Double
    @State private var topKEnabled: Bool
    @State private var topKValue: Int
    @State private var maxTokensEnabled: Bool
    @State private var maxTokensValue: Int
    @State private var avatarPath: String?

    init(folder: ChatFolder) {
        self.folder = folder
        let s = folder.settings
        _systemPrompt    = State(initialValue: s.systemPrompt)
        _tempEnabled     = State(initialValue: s.temperature != nil)
        _tempValue       = State(initialValue: s.temperature ?? 0.7)
        _topPEnabled     = State(initialValue: s.topP != nil)
        _topPValue       = State(initialValue: s.topP ?? 0.9)
        _topKEnabled     = State(initialValue: s.topK != nil)
        _topKValue       = State(initialValue: s.topK ?? 40)
        _maxTokensEnabled = State(initialValue: s.maxTokens != nil)
        _maxTokensValue  = State(initialValue: s.maxTokens ?? 2048)
        _avatarPath      = State(initialValue: folder.avatarPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────────────
            HStack(alignment: .firstTextBaseline) {
                Text("Folder Settings")
                    .font(.system(size: 15, weight: .semibold))
                Text("· \(folder.name)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)

            Divider()

            // ── Body ───────────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Avatar
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Avatar", systemImage: "photo.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            if let path = avatarPath, let nsImage = NSImage(contentsOfFile: path) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color(NSColor.tertiaryLabelColor).opacity(0.15))
                                        .frame(width: 60, height: 60)
                                    Image(systemName: "folder")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Choose Image", action: openImagePicker)
                                .font(.system(size: 12))
                        }
                    }

                    Divider()

                    // System Prompt
                    VStack(alignment: .leading, spacing: 6) {
                        Label("System Prompt", systemImage: "text.quote")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 12))
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    }

                    Divider()

                    // Model Parameters
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Model Parameters", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        // Temperature
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Toggle(isOn: $tempEnabled) {
                                    Text("Temperature")
                                        .font(.system(size: 12))
                                }
                                .toggleStyle(.checkbox)
                                Spacer()
                                if tempEnabled {
                                    Text(String(format: "%.2f", tempValue))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if tempEnabled {
                                Slider(value: $tempValue, in: 0...2)
                            }
                        }

                        // Top P
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Toggle(isOn: $topPEnabled) {
                                    Text("Top P")
                                        .font(.system(size: 12))
                                }
                                .toggleStyle(.checkbox)
                                Spacer()
                                if topPEnabled {
                                    Text(String(format: "%.2f", topPValue))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if topPEnabled {
                                Slider(value: $topPValue, in: 0...1)
                            }
                        }

                        // Top K
                        HStack {
                            Toggle(isOn: $topKEnabled) {
                                Text("Top K")
                                    .font(.system(size: 12))
                            }
                            .toggleStyle(.checkbox)
                            Spacer()
                            if topKEnabled {
                                Stepper("\(topKValue)", value: $topKValue, in: 0...200)
                                    .font(.system(size: 12))
                            }
                        }

                        // Max Tokens
                        HStack {
                            Toggle(isOn: $maxTokensEnabled) {
                                Text("Max Tokens")
                                    .font(.system(size: 12))
                            }
                            .toggleStyle(.checkbox)
                            Spacer()
                            if maxTokensEnabled {
                                TextField("", value: $maxTokensValue, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // ── Footer buttons ─────────────────────────────────────────────
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 380, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Save

    private func save() {
        var updated = folder
        updated.settings = FolderSettings(
            systemPrompt: systemPrompt,
            temperature: tempEnabled ? tempValue : nil,
            topP: topPEnabled ? topPValue : nil,
            topK: topKEnabled ? topKValue : nil,
            maxTokens: maxTokensEnabled ? maxTokensValue : nil
        )
        updated.avatarPath = avatarPath
        store.save(folder: updated)
        dismiss()
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .heic, .gif, .webP]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let updatedFolder = ChatStore.shared.setAvatar(for: self.folder, imageURL: url)
            self.avatarPath = updatedFolder.avatarPath
        }
    }
}
