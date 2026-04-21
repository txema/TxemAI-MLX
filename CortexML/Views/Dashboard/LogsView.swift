import SwiftUI

/// Panel de logs en vivo. Muestra las entradas del servidor
/// con filtros rápidos: all / errors / requests.
struct LogsView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @State private var filter: LogFilter = .all

    enum LogFilter: String, CaseIterable {
        case all, errors, requests
    }

    var filteredLogs: [LogEntry] {
        switch filter {
        case .all:      return serverState.logs
        case .errors:   return serverState.logs.filter { $0.level == .warn || $0.level == .error }
        case .requests: return serverState.logs.filter { $0.level == .ok }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("server log")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(LogFilter.allCases, id: \.self) { f in
                    Button(f.rawValue) { filter = f }
                        .buttonStyle(FilterButtonStyle(isSelected: filter == f))
                }
                Button("Clear") { serverState.logs = [] }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLogs) { entry in
                            LogLineView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .onChange(of: serverState.logs.count) {
                    if let last = filteredLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }
}

/// Línea individual de log en formato monoespaciado.
struct LogLineView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.formattedTime)
                .foregroundStyle(.tertiary)
            Text(entry.level.label)
                .foregroundStyle(entry.level.viewColor)
                .frame(width: 36, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, design: .monospaced))
        .lineLimit(1)
        .padding(.vertical, 1)
    }
}

struct FilterButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }
}

/// Color de cada nivel de log — resuelto en la View para no
/// contaminar el modelo con dependencias de SwiftUI/MainActor.
extension LogEntry.Level {
    var viewColor: Color {
        switch self {
        case .info:  return .blue
        case .ok:    return .green
        case .warn:  return .orange
        case .error: return .red
        }
    }
}

#Preview {
    LogsView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 700, height: 200)
}
