import SwiftUI
import AVFoundation

// MARK: - VoiceStudioView

struct VoiceStudioView: View {
    @ObservedObject private var voiceManager = VoiceManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cortexTheme) private var t

    @State private var selectedProfile: VoiceProfile?
    @State private var testText: String = "Hello, this is a test of the voice synthesis engine."
    @State private var selectedLanguage: String = "en"
    @State private var selectedModelSize: String = "1.7B"
    @State private var isGenerating: Bool = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @State private var generatedAudioData: Data?
    @State private var audioDuration: Double = 0
    @State private var audioProgress: Double = 0
    @State private var playbackTimer: Timer?

    @State private var profiles: [VoiceProfile] = []
    @State private var availableEffects: [VoiceEffect] = []
    @State private var activeEffects: [VoiceEffect] = []
    @State private var modelStatuses: [VoiceModelStatus] = []

    @State private var showNewProfileSheet: Bool = false
    @State private var errorMessage: String?
    @State private var isDownloadingModel: String? = nil

    private let languages = ["en", "zh", "ja", "ko", "fr", "de", "es", "it", "pt", "ru"]
    private let modelSizes = ["0.6B", "1.7B"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Voice Studio")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 0) {
                leftPanel
                Rectangle().fill(t.bd).frame(width: 1)
                rightPanel
            }
        }
        .background(t.win)
        .task { await loadData() }
        .sheet(isPresented: $showNewProfileSheet) { newProfileSheet }
        .alert("Voice Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Server state indicator
            serverStateRow
            Rectangle().fill(t.bd).frame(height: 1)

            // Profile list
            if profiles.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(t.t4)
                    Text("No profiles")
                        .font(.system(size: 11.5))
                        .foregroundStyle(t.t4)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(profiles) { profile in
                            profileRow(profile)
                        }
                    }
                }
            }

            Rectangle().fill(t.bd).frame(height: 1)
            Button {
                showNewProfileSheet = true
            } label: {
                Label("New Profile", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .frame(width: 220)
        .background(t.side)
    }

    private var serverStateRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(serverStateColor)
                .frame(width: 7, height: 7)
            Text(serverStateLabel)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(t.t3)
            Spacer()
            if case .stopped = voiceManager.state {
                Button {
                    Task { try? await voiceManager.start() }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            } else if case .running = voiceManager.state {
                Button { voiceManager.stop() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else if case .starting = voiceManager.state {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func profileRow(_ profile: VoiceProfile) -> some View {
        let isSelected = selectedProfile?.id == profile.id
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? t.accent : t.t2)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(profile.engine)
                    Text("·")
                    Text(profile.language.uppercased())
                }
                .font(.system(size: 9.5))
                .foregroundStyle(t.t4)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? t.aL : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(t.accent).frame(width: 2.5) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProfile = profile
            activeEffects = profile.effectsChain ?? []
        }
        .contextMenu {
            Button("Delete", role: .destructive) { deleteProfile(profile) }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                testVoiceSection
                Rectangle().fill(t.bd).frame(height: 1)
                if selectedProfile != nil { effectsSection }
                Rectangle().fill(t.bd).frame(height: 1)
                modelsSection
            }
        }
    }

    // MARK: Test Voice Section

    private var testVoiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("TEST VOICE")

            TextEditor(text: $testText)
                .font(.system(size: 12))
                .foregroundStyle(t.t1)
                .scrollContentBackground(.hidden)
                .background(t.inp)
                .frame(minHeight: 80, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.inpBd, lineWidth: 1))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Language")
                        .font(.system(size: 9.5))
                        .foregroundStyle(t.t4)
                    Picker("", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang.uppercased()).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Model Size")
                        .font(.system(size: 9.5))
                        .foregroundStyle(t.t4)
                    Picker("", selection: $selectedModelSize) {
                        ForEach(modelSizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }

                Spacer()

                Button {
                    Task { await generateSpeech() }
                } label: {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Generate", systemImage: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || selectedProfile == nil || testText.isEmpty)
            }

            if generatedAudioData != nil { audioPlayerView }
        }
        .padding(16)
    }

    private var audioPlayerView: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(t.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(t.btnBg)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(t.accent)
                            .frame(width: geo.size.width * audioProgress, height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(audioDuration * audioProgress))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(t.t4)
                    Spacer()
                    Text(formatTime(audioDuration))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(t.t4)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Effects Section

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("EFFECTS")

            if availableEffects.isEmpty {
                Text("No effects available")
                    .font(.system(size: 11))
                    .foregroundStyle(t.t4)
            } else {
                ForEach(availableEffects) { effect in
                    let isActive = activeEffects.contains(where: { $0.type == effect.type })
                    effectRow(effect, isActive: isActive)
                }
            }

            if !activeEffects.isEmpty {
                Button {
                    Task { await saveEffectsToProfile() }
                } label: {
                    Label("Save Effects to Profile", systemImage: "checkmark.circle")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func effectRow(_ effect: VoiceEffect, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { isActive },
                set: { on in
                    if on {
                        if !activeEffects.contains(where: { $0.type == effect.type }) {
                            activeEffects.append(effect)
                        }
                    } else {
                        activeEffects.removeAll { $0.type == effect.type }
                    }
                }
            )) {
                Text(effect.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(t.t1)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if isActive, let idx = activeEffects.firstIndex(where: { $0.type == effect.type }) {
                ForEach(Array(activeEffects[idx].params.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 10.5))
                            .foregroundStyle(t.t3)
                            .frame(width: 100, alignment: .leading)
                        Slider(value: Binding(
                            get: { activeEffects[idx].params[key] ?? 0 },
                            set: { activeEffects[idx].params[key] = $0 }
                        ), in: 0...1)
                        Text(String(format: "%.2f", activeEffects[idx].params[key] ?? 0))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(t.t4)
                            .frame(width: 36)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("MODELS")
                Spacer()
                Button {
                    Task { await loadModelStatuses() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(t.t3)
                }
                .buttonStyle(.plain)
            }

            if modelStatuses.isEmpty {
                Text("Model status unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(t.t4)
            } else {
                ForEach(modelStatuses) { model in
                    modelStatusRow(model)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func modelStatusRow(_ model: VoiceModelStatus) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(t.t1)
                HStack(spacing: 6) {
                    if model.loaded {
                        Text("loaded")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.green)
                    } else if model.downloaded {
                        Text("downloaded")
                            .font(.system(size: 9.5))
                            .foregroundStyle(t.t3)
                    } else {
                        Text("not downloaded")
                            .font(.system(size: 9.5))
                            .foregroundStyle(t.t4)
                    }
                    if let mb = model.sizeMb {
                        Text("· \(Int(mb)) MB")
                            .font(.system(size: 9.5))
                            .foregroundStyle(t.t4)
                    }
                }
            }
            Spacer()
            if !model.downloaded {
                if isDownloadingModel == model.modelName {
                    ProgressView().controlSize(.mini)
                } else {
                    Button("Download") {
                        Task { await downloadModel(model.modelName) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - New Profile Sheet

    private var newProfileSheet: some View {
        NewVoiceProfileSheet { profile in
            guard case .running = voiceManager.state else {
                errorMessage = "Voice server is not running. Start it first."
                return
            }
            Task {
                do {
                    let created = try await VoiceAPIClient.shared.createProfile(profile)
                    profiles.append(created)
                    selectedProfile = created
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.08 * 9.5)
            .foregroundStyle(t.lbl)
    }

    private var serverStateColor: Color {
        switch voiceManager.state {
        case .running:  return .green
        case .starting: return Color(hex: "#f59e0b")
        case .error:    return Color(hex: "#ef4444")
        case .stopped:  return t.t4
        }
    }

    private var serverStateLabel: String {
        switch voiceManager.state {
        case .running(let p): return "voice · port \(p)"
        case .starting(let m): return m
        case .error:          return "voice error"
        case .stopped:        return "voice stopped"
        }
    }

    private func formatTime(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Actions

    private func loadData() async {
        async let p: Void = loadProfiles()
        async let e: Void = loadAvailableEffects()
        async let m: Void = loadModelStatuses()
        _ = await (p, e, m)
    }

    private func loadProfiles() async {
        guard case .running = voiceManager.state else { return }
        do { profiles = try await VoiceAPIClient.shared.fetchProfiles() } catch {}
    }

    private func loadAvailableEffects() async {
        guard case .running = voiceManager.state else { return }
        do { availableEffects = try await VoiceAPIClient.shared.fetchAvailableEffects() } catch {}
    }

    private func loadModelStatuses() async {
        guard case .running = voiceManager.state else { return }
        do { modelStatuses = try await VoiceAPIClient.shared.fetchModelStatus() } catch {}
    }

    private func generateSpeech() async {
        guard let profile = selectedProfile else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let data = try await VoiceAPIClient.shared.generateSpeech(
                text: testText,
                profileId: profile.id,
                language: selectedLanguage,
                engine: profile.engine,
                modelSize: selectedModelSize
            )
            generatedAudioData = data
            setupAudioPlayer(with: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setupAudioPlayer(with data: Data) {
        stopPlayback()
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioDuration = audioPlayer?.duration ?? 0
            audioProgress = 0
        } catch {
            errorMessage = "Cannot load audio: \(error.localizedDescription)"
        }
    }

    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        if isPlaying {
            stopPlayback()
        } else {
            player.play()
            isPlaying = true
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    guard let p = self.audioPlayer else { return }
                    self.audioProgress = p.duration > 0 ? p.currentTime / p.duration : 0
                    if !p.isPlaying { self.stopPlayback() }
                }
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func deleteProfile(_ profile: VoiceProfile) {
        Task {
            do {
                try await VoiceAPIClient.shared.deleteProfile(id: profile.id)
                profiles.removeAll { $0.id == profile.id }
                if selectedProfile?.id == profile.id { selectedProfile = nil }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveEffectsToProfile() async {
        guard let profile = selectedProfile else { return }
        var req = URLRequest(url: URL(string: "http://localhost:17493/profiles/\(profile.id)/effects")!)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let body = try? encoder.encode(["effects_chain": activeEffects]) else { return }
        req.httpBody = body
        do {
            let (_, _) = try await URLSession.shared.data(for: req)
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx].effectsChain = activeEffects
                selectedProfile = profiles[idx]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadModel(_ name: String) async {
        isDownloadingModel = name
        defer { isDownloadingModel = nil }
        do {
            try await VoiceAPIClient.shared.downloadModel(name: name)
            await loadModelStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - NewVoiceProfileSheet

private struct NewVoiceProfileSheet: View {
    let onCreate: (VoiceProfileCreate) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cortexTheme) private var t

    @State private var name: String = ""
    @State private var language: String = "en"
    @State private var engine: String = "qwen"
    @State private var modelSize: String = "1.7B"

    private let engines = ["qwen", "qwen_custom_voice", "kokoro"]
    private let languages = ["en", "zh", "ja", "ko", "fr", "de", "es", "it"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Voice Profile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.t1)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(16)
            Rectangle().fill(t.bd).frame(height: 1)

            Form {
                TextField("Profile Name", text: $name)
                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                Picker("Engine", selection: $engine) {
                    ForEach(engines, id: \.self) { Text($0).tag($0) }
                }
                if engine != "kokoro" {
                    Picker("Model Size", selection: $modelSize) {
                        Text("0.6B").tag("0.6B")
                        Text("1.7B").tag("1.7B")
                    }
                }
            }
            .formStyle(.grouped)

            Rectangle().fill(t.bd).frame(height: 1)
            Button("Create Profile") {
                onCreate(VoiceProfileCreate(name: name, language: language,
                                            engine: engine, modelSize: engine == "kokoro" ? nil : modelSize))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(16)
        }
        .frame(width: 360, height: 340)
        .background(t.win)
    }
}

#Preview {
    VoiceStudioView()
        .frame(width: 700, height: 500)
}
