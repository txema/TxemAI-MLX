import SwiftUI

/// Full server configuration sheet.
/// Covers: Appearance, Server Mode (embedded/external), Memory, Cache, Generation Defaults, Auth.
/// POST /admin/api/global-settings for updates.
struct GlobalSettingsView: View {
    var onSave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cortexTheme) private var t

    // MARK: - Appearance

    @AppStorage("cortex_accent") private var accentRaw: String = AccentPreset.emerald.rawValue

    // MARK: - Server mode

    @AppStorage("serverMode") private var serverMode: String = "embedded"
    @AppStorage("modelDirectory") private var modelDirectory: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".omlx/models")
    @ObservedObject private var serverManager = ServerManager.shared

    @State private var settings: GlobalSettings? = nil
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showClearCacheAlert = false
    @State private var statusMessage: String? = nil

    // Editable fields (mirroring GlobalSettings sections)
    @State private var port: String = ""
    @State private var host: String = ""
    @State private var logLevel: String = "INFO"
    @State private var maxConcurrentRequests: String = ""
    @State private var cacheEnabled: Bool = true
    @State private var ssdCacheDir: String = ""
    @State private var ssdCacheMaxSize: String = ""
    @State private var samplingMaxTokens: String = ""
    @State private var samplingTemperature: String = ""
    @State private var samplingTopP: String = ""
    @State private var samplingTopK: String = ""
    @State private var apiKey: String = ""
    @State private var showApiKey: Bool = false
    @State private var skipApiKeyVerification: Bool = false

    private let logLevels = ["DEBUG", "INFO", "WARNING", "ERROR"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Server Settings")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            if isLoading && serverMode == "external" {
                HStack { Spacer(); ProgressView().padding(40); Spacer() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        appearanceSection
                        Divider()
                        serverModeSection
                        Divider()

                        if serverMode == "embedded" {
                            embeddedSection
                        } else {
                            serverSection
                            Divider()
                            cacheSection
                            Divider()
                            samplingSection
                            Divider()
                            authSection

                            if let info = settings?.system {
                                Divider()
                                systemInfoSection(info)
                            }
                        }
                    }
                    .padding(24)
                }
            }

            Divider()

            // Footer
            HStack {
                if let msg = statusMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 560)
        .task { await load() }
        .alert("Clear SSD Cache", isPresented: $showClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearCache() }
        } message: {
            Text("This will delete all cached KV blocks from the SSD. Models will need to rebuild their cache on next use.")
        }
    }

    // MARK: - Appearance section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("APPEARANCE")

            row("Accent Color") {
                HStack(spacing: 10) {
                    ForEach(AccentPreset.allCases, id: \.rawValue) { preset in
                        AccentSwatch(
                            preset: preset,
                            isSelected: accentRaw == preset.rawValue
                        ) {
                            accentRaw = preset.rawValue
                        }
                    }
                    Spacer()
                }
            }

            Text("Accent color is applied across the entire app — buttons, active states, and charts.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Server Mode sections

    private var serverModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SERVER MODE")
            Picker("", selection: $serverMode) {
                Text("External").tag("external")
                Text("Embedded").tag("embedded")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(serverMode == "embedded"
                 ? "oMLX runs inside the app bundle — no separate installation required."
                 : "Connect to an oMLX server running externally (e.g. standalone oMLX.app).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var embeddedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("EMBEDDED SERVER")

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(embeddedStatusColor)
                    .frame(width: 8, height: 8)
                Text(embeddedStatusLabel)
                    .font(.system(size: 13))
                Spacer()
            }

            // Start / Stop button
            Button(action: toggleEmbeddedServer) {
                HStack {
                    if case .starting = serverManager.state {
                        ProgressView().controlSize(.small)
                    }
                    Text(embeddedButtonLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(embeddedServerRunning ? .red : .green)
            .disabled({ if case .starting = serverManager.state { return true }; return false }())

            // Last lines of startup log
            if !serverManager.startupLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(serverManager.startupLog.suffix(8), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 90)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
            }

            // Error message
            if case .error(let msg) = serverManager.state {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.systemRed))
            }

            Divider()
            sectionHeader("API KEY")
            row("API Key") {
                HStack(spacing: 0) {
                    Group {
                        if showApiKey {
                            TextField("Enter API key", text: $apiKey)
                        } else {
                            SecureField("Enter API key", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    Button { showApiKey.toggle() } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            sectionHeader("MODEL DIRECTORY")
            row("Models path") {
                HStack {
                    TextField("~/.omlx/models", text: $modelDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Select"
                        if panel.runModal() == .OK, let url = panel.url {
                            modelDirectory = url.path
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("Directory where oMLX looks for models.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Embedded server helpers

    private var embeddedServerRunning: Bool {
        if case .running = serverManager.state { return true }
        return false
    }

    private var embeddedStatusColor: Color {
        switch serverManager.state {
        case .running:  return .green
        case .starting: return .orange
        case .error:    return .red
        case .stopped:  return .gray
        }
    }

    private var embeddedStatusLabel: String {
        switch serverManager.state {
        case .stopped:            return "Stopped"
        case .starting(let p):    return p
        case .running(let port):  return "Running on port \(port)"
        case .error(let msg):     return "Error: \(msg)"
        }
    }

    private var embeddedButtonLabel: String {
        switch serverManager.state {
        case .stopped, .error:  return "Start Server"
        case .starting:         return "Starting…"
        case .running:          return "Stop Server"
        }
    }

    private func toggleEmbeddedServer() {
        if embeddedServerRunning {
            serverManager.stop()
        } else {
            let apiKey = UserDefaults.standard.string(forKey: "cortex_api_key") ?? ""
            Task {
                try? await serverManager.start(port: 8000, apiKey: apiKey)
            }
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SERVER")
            row("Host") {
                TextField("localhost", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 160)
            }
            row("Port") {
                TextField("8000", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 80)
            }
            row("Log Level") {
                Picker("", selection: $logLevel) {
                    ForEach(logLevels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            row("Max Requests") {
                TextField("", text: $maxConcurrentRequests)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 80)
            }
        }
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SSD CACHE")
            row("Enabled") { Toggle("", isOn: $cacheEnabled).labelsHidden() }
            row("Directory") {
                TextField("", text: $ssdCacheDir)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
            row("Max Size") {
                TextField("e.g. 50GB", text: $ssdCacheMaxSize)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 120)
            }
            row("") {
                Button("Clear SSD Cache…") { showClearCacheAlert = true }
                    .foregroundStyle(Color(NSColor.systemRed))
            }
        }
    }

    private var samplingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("GENERATION DEFAULTS")
            optionalRow("Max Tokens", text: $samplingMaxTokens, placeholder: "default")
            optionalRow("Temperature", text: $samplingTemperature, placeholder: "default")
            optionalRow("Top P", text: $samplingTopP, placeholder: "default")
            optionalRow("Top K", text: $samplingTopK, placeholder: "default")
        }
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("AUTH")
            row("API Key") {
                HStack(spacing: 0) {
                    Group {
                        if showApiKey {
                            TextField("••••••••", text: $apiKey)
                        } else {
                            SecureField("••••••••", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            row("Skip Verification") {
                Toggle("", isOn: $skipApiKeyVerification).labelsHidden()
            }
        }
    }

    private func systemInfoSection(_ info: GlobalSettings.SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SYSTEM (read-only)")
            infoRow("RAM", info.totalMemory)
            infoRow("Auto Model Memory", info.autoModelMemory)
            infoRow("SSD", info.ssdTotal)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    private func row<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
    }

    private func optionalRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        row(label) {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 120)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        // Always populate API key from local storage regardless of mode
        apiKey = UserDefaults.standard.string(forKey: "cortex_api_key") ?? ""

        if serverMode == "external" {
            do {
                let s = try await APIClient.shared.fetchGlobalSettings()
                settings = s
                port = "\(s.server.port)"
                host = s.server.host
                logLevel = s.server.logLevel.uppercased()
                maxConcurrentRequests = s.scheduler.maxConcurrentRequests.map { "\($0)" } ?? ""
                cacheEnabled = s.cache.enabled
                ssdCacheDir = s.cache.ssdCacheDir
                ssdCacheMaxSize = s.cache.ssdCacheMaxSize
                samplingMaxTokens = s.sampling.maxTokens.map { "\($0)" } ?? ""
                samplingTemperature = s.sampling.temperature.map { String(format: "%.2f", $0) } ?? ""
                samplingTopP = s.sampling.topP.map { String(format: "%.2f", $0) } ?? ""
                samplingTopK = s.sampling.topK.map { "\($0)" } ?? ""
                skipApiKeyVerification = s.auth.skipApiKeyVerification
            } catch {
                statusMessage = "Failed to load settings: \(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    private func save() {
        isSaving = true
        statusMessage = nil

        // Always persist API key locally before any network call
        if !apiKey.isEmpty {
            UserDefaults.standard.set(apiKey, forKey: "cortex_api_key")
            APIClient.shared.apiKey = apiKey
        }

        // Embedded mode: local save only — server manages its own config
        if serverMode == "embedded" {
            isSaving = false
            onSave?()
            dismiss()
            return
        }

        Task {
            do {
                var update = GlobalSettingsUpdate()
                update.host = host.isEmpty ? nil : host
                update.port = Int(port)
                update.logLevel = logLevel
                update.maxConcurrentRequests = Int(maxConcurrentRequests)
                update.cacheEnabled = cacheEnabled
                update.ssdCacheDir = ssdCacheDir.isEmpty ? nil : ssdCacheDir
                update.ssdCacheMaxSize = ssdCacheMaxSize.isEmpty ? nil : ssdCacheMaxSize
                update.samplingMaxTokens = Int(samplingMaxTokens)
                update.samplingTemperature = Double(samplingTemperature)
                update.samplingTopP = Double(samplingTopP)
                update.samplingTopK = Int(samplingTopK)
                if !apiKey.isEmpty { update.apiKey = apiKey }
                update.skipApiKeyVerification = skipApiKeyVerification

                try await APIClient.shared.updateGlobalSettings(update)
                await MainActor.run {
                    isSaving = false
                    onSave?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    statusMessage = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearCache() {
        Task {
            do {
                try await APIClient.shared.clearSSDCache()
                await MainActor.run { statusMessage = "SSD cache cleared." }
            } catch {
                await MainActor.run { statusMessage = "Clear failed: \(error.localizedDescription)" }
            }
        }
    }
}

// MARK: - AccentSwatch

private struct AccentSwatch: View {
    let preset: AccentPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(preset.color)
                    .frame(width: 24, height: 24)
                    .shadow(color: preset.color.opacity(isSelected ? 0.45 : 0), radius: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? preset.color : Color.clear, lineWidth: 2)
                    .padding(-3)
            )
        }
        .buttonStyle(.plain)
        .help(preset.label)
    }
}

#Preview {
    GlobalSettingsView()
}
