import SwiftUI

/// Sheet for discovering and downloading models from HuggingFace.
/// Two-column layout: search + results on the left, active downloads on the right.
struct HFDownloaderSheet: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [HFModel] = []
    @State private var recommendedTrending: [HFModel] = []
    @State private var recommendedPopular: [HFModel] = []
    @State private var activeTasks: [HFDownloadTask] = []
    @State private var isLoadingRecommended = true
    @State private var isSearching = false
    @State private var selectedTab = 0
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var terminalTimes: [String: Date] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // MARK: Left column — search + results
            VStack(alignment: .leading, spacing: 0) {
                header
                searchBar
                Divider()
                contentArea
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)

            Divider()

            // MARK: Right column — active downloads (always visible, independent scroll)
            VStack(alignment: .leading, spacing: 0) {
                downloadsHeader
                Divider()
                downloadsPanel
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 740, height: 560)
        .task {
            await loadRecommended()
            await refreshTasks()
            startPollingTasks()
        }
        .onDisappear {
            pollTask?.cancel()
            searchDebounceTask?.cancel()
        }
    }

    // MARK: - Left column

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Download from HuggingFace")
                    .font(.system(size: 15, weight: .medium))
                Text("MLX-compatible models")
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

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search models…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: searchQuery) { _, newValue in
                    debounceSearch(newValue)
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                    isSearching = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var contentArea: some View {
        if searchQuery.isEmpty {
            if isLoadingRecommended {
                centeredProgress
            } else {
                Picker("", selection: $selectedTab) {
                    Text("Trending").tag(0)
                    Text("Popular").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                let models = selectedTab == 0 ? recommendedTrending : recommendedPopular
                modelList(models, emptyLabel: "No recommended models")
            }
        } else {
            if isSearching {
                centeredProgress
            } else {
                modelList(searchResults, emptyLabel: "No results for \"\(searchQuery)\"")
            }
        }
    }

    private func modelList(_ models: [HFModel], emptyLabel: String) -> some View {
        Group {
            if models.isEmpty {
                HStack {
                    Spacer()
                    Text(emptyLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(models) { model in
                            HFModelRow(model: model) {
                                await startDownload(model)
                            }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var centeredProgress: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.regular)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Right column

    private var downloadsHeader: some View {
        HStack {
            Text("Downloads")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            let terminated = activeTasks.filter { !$0.isActive }
            if !terminated.isEmpty {
                Button("Clear all") {
                    for task in terminated {
                        terminalTimes[task.taskId] = Date.distantPast
                    }
                    Task { await refreshTasks() }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var downloadsPanel: some View {
        Group {
            if activeTasks.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 6)
                    Text("No active downloads")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(activeTasks) { task in
                            HFTaskRow(
                                task: task,
                                onCancel: {
                                    Task {
                                        try? await APIClient.shared.cancelHFTask(taskId: task.taskId)
                                        await refreshTasks()
                                    }
                                },
                                onClear: {
                                    terminalTimes[task.taskId] = Date.distantPast
                                    Task { await refreshTasks() }
                                }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadRecommended() async {
        isLoadingRecommended = true
        do {
            let result = try await APIClient.shared.fetchHFRecommended()
            recommendedTrending = result.trending
            recommendedPopular  = result.popular
        } catch { }
        isLoadingRecommended = false
    }

    private func debounceSearch(_ query: String) {
        searchDebounceTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                let results = try await APIClient.shared.searchHuggingFace(query: query)
                if !Task.isCancelled {
                    await MainActor.run {
                        searchResults = results
                        isSearching = false
                    }
                }
            } catch {
                await MainActor.run { isSearching = false }
            }
        }
    }

    private func startDownload(_ model: HFModel) async {
        do {
            _ = try await APIClient.shared.startHFDownload(repoId: model.repoId)
            await refreshTasks()
        } catch { }
    }

    private func refreshTasks() async {
        guard let allTasks = try? await APIClient.shared.fetchHFTasks() else { return }
        let now = Date()

        for task in allTasks where !task.isActive {
            if terminalTimes[task.taskId] == nil {
                terminalTimes[task.taskId] = now
            }
        }

        activeTasks = allTasks.filter { task in
            if task.isActive { return true }
            guard let t = terminalTimes[task.taskId] else { return false }
            let grace: TimeInterval = task.isCompleted ? 2.0 : 5.0
            return now.timeIntervalSince(t) < grace
        }

        if allTasks.contains(where: { $0.isCompleted }) {
            serverState.refreshModelList()
        }
    }

    private func startPollingTasks() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await refreshTasks()
            }
        }
    }
}

// MARK: - Model row

private struct HFModelRow: View {
    let model: HFModel
    let onDownload: () async -> Void
    @State private var isDownloading = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !model.sizeFormatted.isEmpty {
                        HFBadge(model.sizeFormatted, color: .blue)
                    }
                    if let pf = model.paramsFormatted {
                        HFBadge(pf, color: .purple)
                    }
                    Label("\(formatCount(model.downloads))", systemImage: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                isDownloading = true
                Task {
                    await onDownload()
                    isDownloading = false
                }
            } label: {
                Image(systemName: isDownloading ? "hourglass" : "arrow.down.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isDownloading ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isDownloading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct HFBadge: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Task row

private struct HFTaskRow: View {
    let task: HFDownloadTask
    let onCancel: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.repoId.split(separator: "/").last.map(String.init) ?? task.repoId)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if task.isActive {
                ProgressView(value: task.progress / 100.0)
                    .progressViewStyle(.linear)

                HStack {
                    Text(task.status == "pending" ? "pending…" : String(format: "%.0f%%", task.progress))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if task.totalSize > 0 {
                        Text(formatBytes(task.downloadedSize))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

            } else {
                HStack {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                    Text(task.status)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("clear", action: onClear)
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024.0)
    }
}

#Preview {
    HFDownloaderSheet()
        .environmentObject(ServerStateViewModel())
}
