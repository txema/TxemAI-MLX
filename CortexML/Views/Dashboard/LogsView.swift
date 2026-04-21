import SwiftUI

// MARK: - LogsView

/// Server log panel — always uses a dark palette regardless of light/dark mode.
struct LogsView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.cortexTheme) private var t
    @State private var filter: LogFilter = .all

    enum LogFilter: String, CaseIterable, Identifiable {
        case all, errors, warnings
        var id: Self { self }
    }

    var filteredLogs: [LogEntry] {
        switch filter {
        case .all:      return serverState.logs
        case .errors:   return serverState.logs.filter { $0.level == .error }
        case .warnings: return serverState.logs.filter { $0.level == .warn || $0.level == .error }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 0) {
                ForEach(LogFilter.allCases) { f in
                    LogFilterButton(
                        label: f.rawValue.uppercased(),
                        isSelected: filter == f,
                        action: { filter = f }
                    )
                }
                Spacer()
                Button("CLEAR") { serverState.logs = [] }
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "#4b5563"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(hex: "#0e1016"))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(hex: "#1e2330"))
                    .frame(height: 1)
            }

            // Log lines
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLogs) { entry in
                            LogLineView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .onChange(of: serverState.logs.count) {
                    if let last = filteredLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        // Always dark — intentional, not inverted in light mode
        .background(t.logBg)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(t.logBd, lineWidth: 1)
        )
    }
}

// MARK: - LogFilterButton

private struct LogFilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? Color(hex: "#e2e8f0") : Color(hex: "#4b5563"))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isSelected ? Color(hex: "#1e2330") : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color(hex: "#2d3444") : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LogLineView

struct LogLineView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.formattedTime)
                .foregroundStyle(Color(hex: "#2d3444"))
                .frame(minWidth: 56, alignment: .leading)
            Text(entry.level.label)
                .foregroundStyle(entry.level.logColor)
                .fontWeight(.bold)
                .frame(width: 26, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(entry.level.logMessageColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.vertical, 1.5)
    }
}

// MARK: - Log level colors (always fixed, dark-scheme)

extension LogEntry.Level {
    var logColor: Color {
        switch self {
        case .info:  return Color(hex: "#10b981")
        case .ok:    return Color(hex: "#10b981")
        case .warn:  return Color(hex: "#f59e0b")
        case .error: return Color(hex: "#ef4444")
        }
    }
    var logMessageColor: Color {
        switch self {
        case .info:  return Color(hex: "#8892a4")
        case .ok:    return Color(hex: "#8892a4")
        case .warn:  return Color(hex: "#fbbf24")
        case .error: return Color(hex: "#f87171")
        }
    }
}

#Preview {
    LogsView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 468, height: 220)
}
