import SwiftUI

/// Sheet for running throughput benchmarks on a loaded model.
/// Uses POST /admin/api/bench/start + GET /admin/api/bench/{id}/stream (SSE).
struct BenchmarkView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.dismiss) private var dismiss

    // Config
    @State private var selectedModelId: String = ""
    @State private var selectedPromptLength: Int = 1024
    @State private var generationLength: Int = 128
    @State private var runs: Int = 1

    // Run state
    @State private var isRunning = false
    @State private var progress: Double = 0
    @State private var progressLabel = ""
    @State private var results: [BenchmarkResult] = []
    @State private var errorMessage: String? = nil
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var currentBenchId: String? = nil

    private let validPromptLengths = [1024, 4096, 8192, 16384, 32768, 65536, 131072, 200000]

    private var loadedModels: [LLMModel] {
        serverState.models.filter { $0.status == .loaded }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 16) {
                configSection
                Divider()
                resultsSection
            }
            .padding(20)
        }
        .frame(width: 460)
        .onAppear {
            if let first = loadedModels.first { selectedModelId = first.id }
        }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Benchmark")
                    .font(.system(size: 15, weight: .medium))
                Text("Throughput test — PP and TG speed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model picker
            HStack {
                Text("Model")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                if loadedModels.isEmpty {
                    Text("No models loaded")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                } else {
                    Picker("", selection: $selectedModelId) {
                        ForEach(loadedModels) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Prompt tokens
            HStack {
                Text("Prompt tokens")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Picker("", selection: $selectedPromptLength) {
                    ForEach(validPromptLengths, id: \.self) { n in
                        Text(formatTokenCount(n)).tag(n)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }

            // Gen tokens
            HStack {
                Text("Gen tokens")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                TextField("128", value: $generationLength, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            // Run button / cancel
            HStack {
                if isRunning {
                    Button("Cancel", action: cancelRun)
                        .buttonStyle(.bordered)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Run") { startRun() }
                        .buttonStyle(.borderedProminent)
                        .disabled(loadedModels.isEmpty || selectedModelId.isEmpty)
                }
            }

            if !progressLabel.isEmpty {
                Text(progressLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.systemRed))
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !results.isEmpty {
                HStack {
                    Text("Test")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Prefill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text("Gen")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }

                Divider()

                ForEach(results) { result in
                    HStack {
                        Text(result.label)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.1f t/s", result.ppTps))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(width: 80, alignment: .trailing)
                        Text(String(format: "%.1f t/s", result.tgTps))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 80, alignment: .trailing)
                    }
                }

                if results.count > 1 {
                    Divider()
                    let avgPP = results.map(\.ppTps).reduce(0, +) / Double(results.count)
                    let avgTG = results.map(\.tgTps).reduce(0, +) / Double(results.count)
                    HStack {
                        Text("average")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.1f t/s", avgPP))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(width: 80, alignment: .trailing)
                        Text(String(format: "%.1f t/s", avgTG))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startRun() {
        guard !selectedModelId.isEmpty else { return }
        streamTask?.cancel()
        isRunning = true
        progress = 0
        progressLabel = "Starting…"
        results = []
        errorMessage = nil

        streamTask = Task {
            do {
                let benchId = try await APIClient.shared.startBenchmark(
                    modelId: selectedModelId,
                    promptTokens: selectedPromptLength,
                    completionTokens: generationLength,
                    runs: runs
                )
                currentBenchId = benchId

                for try await event in APIClient.shared.streamBenchmarkResults(benchId: benchId) {
                    if Task.isCancelled { break }
                    await MainActor.run { handle(event) }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }

    private func cancelRun() {
        streamTask?.cancel()
        if let benchId = currentBenchId {
            Task { try? await APIClient.shared.cancelBenchmark(benchId: benchId) }
        }
        isRunning = false
        progressLabel = ""
    }

    private func handle(_ event: BenchmarkEvent) {
        switch event.type {
        case "progress":
            let cur = event.current ?? 0
            let tot = event.total ?? 1
            progress = Double(cur) / Double(max(tot, 1))
            progressLabel = event.message ?? ""

        case "result":
            guard let data = event.data else { return }
            let label: String
            if data.testType == "batch", let bs = data.batchSize {
                label = "batch \(bs)×  pp\(formatTokenCount(data.pp))/tg\(data.tg)"
            } else {
                label = "pp\(formatTokenCount(data.pp)) / tg\(data.tg)"
            }
            results.append(BenchmarkResult(label: label, ppTps: data.processingTps, tgTps: data.genTps))

        case "done":
            progress = 1
            progressLabel = ""

        case "upload_done":
            isRunning = false

        case "error":
            errorMessage = event.message ?? "Unknown error"
            isRunning = false

        default:
            break
        }
    }

    private func formatTokenCount(_ n: Int) -> String {
        switch n {
        case 1024:   return "1K"
        case 4096:   return "4K"
        case 8192:   return "8K"
        case 16384:  return "16K"
        case 32768:  return "32K"
        case 65536:  return "64K"
        case 131072: return "128K"
        case 200000: return "200K"
        default:     return "\(n)"
        }
    }
}

#Preview {
    BenchmarkView()
        .environmentObject(ServerStateViewModel())
}
