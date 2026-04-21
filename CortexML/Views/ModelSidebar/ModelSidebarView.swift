import SwiftUI

/// Panel lateral con la lista de modelos disponibles.
/// Cada modelo muestra su estado (loaded/idle), cuantización,
/// tamaño y acciones rápidas: load/unload, pin, settings.
struct ModelSidebarView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @State private var showingHFDownloader = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Models")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Lista de modelos
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(serverState.models) { model in
                        ModelRowView(model: model)
                        Divider()
                    }
                }
            }

            Divider()

            // Footer: descarga desde HuggingFace
            Button {
                showingHFDownloader = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                    Text("download from HuggingFace")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingHFDownloader) {
            HFDownloaderSheet()
                .environmentObject(serverState)
        }
    }
}

/// Fila de un modelo en el panel lateral.
struct ModelRowView: View {
    let model: LLMModel
    @EnvironmentObject var serverState: ServerStateViewModel
    @State private var isHovered = false
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.id)
                    .font(.system(size: 13, weight: .medium))
                if let alias = model.modelAlias {
                    Text(alias)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ModelStatusBadge(status: model.status)
                if model.isPinned {
                    ModelPinnedBadge()
                }
                Text("\(model.quantization) · \(model.sizeGB, specifier: "%.0f") GB")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Barra de uso de memoria (solo si está cargado)
            if model.status == .loaded {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * model.memoryFraction, height: 3)
                    }
                }
                .frame(height: 3)
            }

            // Acciones rápidas
            HStack(spacing: 4) {
                ModelActionButton(
                    label: model.status == .loaded ? "unload" : "load",
                    isActive: model.status == .loaded
                ) {
                    serverState.toggleModel(model)
                }
                ModelActionButton(label: "pin", isActive: model.isPinned) {
                    serverState.togglePin(model)
                }
                ModelActionButton(label: "settings", isActive: false) {
                    showingSettings = true
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showingSettings) {
            ModelSettingsSheet(model: model) {
                serverState.refreshModelList()
            }
        }
    }
}

struct ModelStatusBadge: View {
    let status: LLMModel.Status
    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(status.badgeBackground)
            .foregroundStyle(status.badgeForeground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct ModelPinnedBadge: View {
    var body: some View {
        Text("pinned")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.12))
            .foregroundStyle(Color.purple)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct ModelActionButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(.system(size: 10))
            .buttonStyle(ModelActionButtonStyle(isActive: isActive))
    }
}

struct ModelActionButtonStyle: ButtonStyle {
    let isActive: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(isActive ? Color.accentColor : Color.clear)
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }
}

#Preview {
    ModelSidebarView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 260, height: 500)
}
