import SwiftUI

/// Sheet for per-model configuration.
/// Loads generation_config suggestions on appear and saves via PUT /admin/api/models/{id}/settings.
struct ModelSettingsSheet: View {
    let model: LLMModel
    var onSave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String = ""
    @State private var ttlSeconds: Double = 0
    @State private var temperature: Double = 0.7
    @State private var topP: Double = 0.9
    @State private var topK: Double = 50
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Settings")
                    .font(.system(size: 16, weight: .medium))
                Text(model.id)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                settingsFields
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.systemRed))
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 380)
        .task { await loadConfig() }
    }

    private var settingsFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Alias
            VStack(alignment: .leading, spacing: 4) {
                Text("ALIAS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField("Optional display name", text: $alias)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            // Idle TTL
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("IDLE TTL")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(ttlSeconds == 0 ? "disabled" : "\(Int(ttlSeconds))s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $ttlSeconds, in: 0...3600, step: 60)
            }

            Divider()

            SettingsSliderRow(label: "TEMPERATURE",
                              value: $temperature,
                              range: 0...2, step: 0.01,
                              format: "%.2f")

            SettingsSliderRow(label: "TOP P",
                              value: $topP,
                              range: 0...1, step: 0.01,
                              format: "%.2f")

            // Top-K (integer values, bound via Double)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TOP K")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(topK))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $topK, in: 0...200, step: 1)
            }
        }
    }

    private func loadConfig() async {
        alias      = model.modelAlias ?? ""
        ttlSeconds = Double(model.ttlSeconds ?? 0)

        // Start from the model file defaults (generation_config.json / config.json),
        // then override with any values the user has explicitly saved.
        if let config = try? await APIClient.shared.fetchGenerationConfig(modelId: model.id) {
            temperature = config.temperature ?? 0.7
            topP        = config.topP ?? 0.9
            topK        = Double(config.topK ?? 50)
        }

        // Saved per-model settings take priority over model-file defaults.
        if let saved = model.temperature { temperature = saved }
        if let saved = model.topP        { topP        = saved }
        if let saved = model.topK        { topK        = Double(saved) }

        isLoading = false
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let trimmed = alias.trimmingCharacters(in: .whitespaces)
                let settings = ModelSettingsUpdate(
                    modelAlias: trimmed.isEmpty ? nil : trimmed,
                    isPinned: nil,
                    ttlSeconds: Int(ttlSeconds),
                    temperature: temperature,
                    topP: topP,
                    topK: Int(topK),
                    repetitionPenalty: nil
                )
                try await APIClient.shared.updateModelSettings(modelId: model.id, settings: settings)
                await MainActor.run {
                    onSave?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Reusable slider row

private struct SettingsSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

#Preview {
    ModelSettingsSheet(model: LLMModel(
        id: "Qwen3-Coder-Next",
        name: "Qwen3 Coder Next",
        quantization: "8-bit",
        sizeGB: 85,
        status: .loaded,
        isPinned: true,
        memoryFraction: 0.66
    ))
}
