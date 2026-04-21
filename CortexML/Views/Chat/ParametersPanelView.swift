import SwiftUI

// MARK: - ParametersPanelView

/// Right-side collapsible panel (160 px) with sampling sliders, action buttons, and usage stats.
struct ParametersPanelView: View {
    @Binding var temperature: Double
    @Binding var topP: Double
    @Binding var maxTokens: Int

    let messageCount: Int
    let totalTokens: Int
    let contextUsed: Int

    var onFork: () -> Void
    var onRegenerate: () -> Void
    var onExportMD: () -> Void
    var onClear: () -> Void

    @Environment(\.cortexTheme) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Sampling ─────────────────────────────────────────────
                sectionHeader("SAMPLING")

                ParamSlider(
                    label: "Temperature",
                    value: $temperature,
                    range: 0...2,
                    step: 0.05,
                    format: "%.2f"
                )
                ParamSlider(
                    label: "Top P",
                    value: $topP,
                    range: 0...1,
                    step: 0.05,
                    format: "%.2f"
                )
                ParamSliderInt(
                    label: "Max Tokens",
                    value: $maxTokens,
                    range: 256...32768,
                    step: 256
                )

                divider

                // ── Actions ───────────────────────────────────────────────
                sectionHeader("ACTIONS")

                panelAction("⎇", "Branch here",  onFork)
                panelAction("↺", "Regenerate",   onRegenerate)
                panelAction("⎘", "Export MD",    onExportMD)
                panelAction("✕", "Clear",        onClear)

                divider

                // ── Usage ─────────────────────────────────────────────────
                sectionHeader("USAGE")

                usageStat("Tokens",   "\(totalTokens)")
                usageStat("Messages", "\(messageCount)")
                usageStat("Context",  contextUsed > 0 ? "\(contextUsed)" : "—")
            }
            .padding(.vertical, 12)
        }
        .frame(width: 160)
        .background(t.side)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.bd).frame(width: 1)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.08 * 9.5)
            .foregroundStyle(t.lbl)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(t.bd)
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private func panelAction(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.system(size: 11))
                    .foregroundStyle(t.t4)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(t.t3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func usageStat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(t.t3)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(t.t2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
}

// MARK: - Slider subviews

private struct ParamSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    @Environment(\.cortexTheme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.t2)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(t.t3)
            }
            .padding(.horizontal, 10)
            Slider(value: $value, in: range, step: step)
                .tint(t.accent)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
    }
}

private struct ParamSliderInt: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    @Environment(\.cortexTheme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.t2)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(t.t3)
            }
            .padding(.horizontal, 10)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .tint(t.accent)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }
}

#Preview {
    ParametersPanelView(
        temperature: .constant(0.7),
        topP: .constant(0.9),
        maxTokens: .constant(4096),
        messageCount: 12,
        totalTokens: 3842,
        contextUsed: 3842,
        onFork: {},
        onRegenerate: {},
        onExportMD: {},
        onClear: {}
    )
    .frame(height: 500)
}
