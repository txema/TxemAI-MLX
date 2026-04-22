import SwiftUI

// MARK: - ModelSidebarView

struct ModelSidebarView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.cortexTheme) private var t
    @State private var showingHFDownloader = false

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("MODELS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.08 * 9.5)
                    .foregroundStyle(t.lbl)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // Model list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(serverState.models) { model in
                        ModelCardView(model: model)
                    }
                }
                .padding(.horizontal, 6)
            }

            Divider()
                .background(t.bd)

            // Download footer
            Button {
                showingHFDownloader = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11))
                    Text("Download from HuggingFace")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(t.t3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
        }
        .background(t.side)
        .sheet(isPresented: $showingHFDownloader) {
            HFDownloaderSheet()
                .environmentObject(serverState)
        }
    }
}

// MARK: - ModelCardView

struct ModelCardView: View {
    let model: LLMModel
    @EnvironmentObject var serverState: ServerStateViewModel
    @Environment(\.cortexTheme) private var t
    @State private var isHovered = false
    @State private var showingSettings = false

    private var isLoaded: Bool { model.status == .loaded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1 · Header row
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(t.t1)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let alias = model.modelAlias {
                        Text(alias)
                            .font(.system(size: 9.5))
                            .foregroundStyle(t.t4)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
                StatusBadgeView(status: model.status)
            }
            .padding(.bottom, 3)

            // 2 · VRAM row
            HStack(spacing: 4) {
                Group {
                    Text(String(format: "%.0f", model.sizeGB))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(t.t3)
                    + Text(" / 128")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(t.t5)
                    + Text(" GB")
                        .font(.system(size: 10))
                        .foregroundStyle(t.t5)
                }
                Spacer(minLength: 0)
                if !model.quantization.isEmpty {
                    Text(model.quantization)
                        .font(.system(size: 9))
                        .foregroundStyle(t.t4)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(t.btnBg)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.bottom, 4)

            // 3 · VRAM bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(t.bd2)
                        .frame(height: 3)
                    if isLoaded {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: [t.accent, t.accent.opacity(0.73)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * model.memoryFraction, height: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#d1d5db"))
                            .frame(width: geo.size.width * model.memoryFraction, height: 3)
                    }
                }
            }
            .frame(height: 3)
            .padding(.bottom, 5)

            // 4 · Bottom row: sparkline + action buttons
            HStack(spacing: 6) {
                // Mini sparkline
                MiniSparkline(
                    data: serverState.throughputHistory,
                    isLoaded: isLoaded
                )
                .frame(width: 54, height: 18)

                Spacer(minLength: 0)

                // Action buttons — visible on hover or loaded state
                if isHovered || isLoaded {
                    HStack(spacing: 4) {
                        if isLoaded {
                            CardActionButton(
                                label: "unload",
                                bg: Color(hex: "#fef2f2"),
                                fg: Color(hex: "#dc2626")
                            ) { serverState.toggleModel(model) }
                        } else {
                            CardActionButton(
                                label: "load",
                                bg: t.aL,
                                fg: t.accent
                            ) { serverState.toggleModel(model) }
                        }
                        CardActionButton(
                            label: "pin",
                            bg: t.btnBg,
                            fg: model.isPinned ? t.accent : t.t3
                        ) { serverState.togglePin(model) }
                        CardActionButton(
                            label: "•••",
                            bg: t.btnBg,
                            fg: t.t3
                        ) { showingSettings = true }
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isLoaded {
                    t.aL
                } else if isHovered {
                    t.hov
                } else {
                    Color.clear
                }
            }
        )
        .overlay(alignment: .leading) {
            if isLoaded {
                Rectangle()
                    .fill(t.accent)
                    .frame(width: 2.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isLoaded)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showingSettings) {
            ModelSettingsSheet(model: model) {
                serverState.refreshModelList()
            }
        }
    }
}

// MARK: - StatusBadgeView

struct StatusBadgeView: View {
    let status: LLMModel.Status
    @Environment(\.cortexTheme) private var t

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .shadow(color: isLoaded ? t.accent.opacity(0.53) : .clear, radius: 2)
            Text(status.rawValue)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.01 * 9.5)
                .foregroundStyle(isLoaded ? t.accent : t.t4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isLoaded ? t.aL : t.btnBg)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isLoaded ? t.aB : t.bd, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var isLoaded: Bool { status == .loaded }

    private var dotColor: Color {
        switch status {
        case .loaded:  return t.accent
        case .idle:    return t.t4
        case .loading: return Color(hex: "#f59e0b")
        }
    }
}

// MARK: - CardActionButton

struct CardActionButton: View {
    let label: String
    let bg: Color
    let fg: Color
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .buttonStyle(.plain)
    }
}

// MARK: - MiniSparkline

struct MiniSparkline: View {
    let data: [Double]
    let isLoaded: Bool
    @Environment(\.cortexTheme) private var t

    var body: some View {
        Canvas { ctx, size in
            guard data.count > 1 else { return }
            let pts = data
            let maxV = pts.max() ?? 1
            let minV = pts.min() ?? 0
            let range = maxV - minV > 0 ? maxV - minV : 1
            let step = size.width / CGFloat(pts.count - 1)

            var line = Path()
            var area = Path()

            for (i, v) in pts.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (CGFloat(v - minV) / CGFloat(range)) * size.height
                if i == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                    area.move(to: CGPoint(x: x, y: size.height))
                    area.addLine(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                    area.addLine(to: CGPoint(x: x, y: y))
                }
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()

            let strokeColor: Color = isLoaded ? t.accent : t.t5
            let fillColor:   Color = isLoaded ? t.accent.opacity(0.22) : t.t5.opacity(0.10)

            ctx.stroke(line, with: .color(strokeColor), lineWidth: 1.5)
            ctx.fill(area,  with: .color(fillColor))
        }
    }
}

#Preview {
    ModelSidebarView()
        .environmentObject(ServerStateViewModel())
        .frame(width: 192, height: 600)
}
