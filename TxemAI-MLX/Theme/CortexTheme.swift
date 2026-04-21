import SwiftUI

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xff) / 255
        let g = Double((int >> 8)  & 0xff) / 255
        let b = Double( int        & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - CortexTheme

struct CortexTheme {
    let dark: Bool
    let accent: Color

    // Derived accent tints
    var aL: Color { accent.opacity(0.10) }   // 10% — active bg tint
    var aB: Color { accent.opacity(0.40) }   // 40% — active border

    // Window / layout backgrounds
    var win: Color  { dark ? Color(hex: "#1c1d26") : Color(hex: "#ffffff") }
    var side: Color { dark ? Color(hex: "#15161d") : Color(hex: "#fafafa") }

    // Titlebar gradient
    var titlebarTop:    Color { dark ? Color(hex: "#252636") : Color(hex: "#f7f7f7") }
    var titlebarBot:    Color { dark ? Color(hex: "#21222e") : Color(hex: "#f0f0f0") }
    var titlebarBorder: Color { dark ? Color(hex: "#2e3148") : Color(hex: "#d6d6d6") }

    // Borders / dividers
    var bd:  Color { dark ? Color(hex: "#2a2d3e") : Color(hex: "#efefef") }
    var bd2: Color { dark ? Color(hex: "#232433") : Color(hex: "#f3f3f3") }

    // Text hierarchy
    var t1: Color { dark ? Color(hex: "#e8eaed") : Color(hex: "#1a1a1a") }
    var t2: Color { dark ? Color(hex: "#b0bac8") : Color(hex: "#374151") }
    var t3: Color { dark ? Color(hex: "#6e7a96") : Color(hex: "#6b7280") }
    var t4: Color { dark ? Color(hex: "#454e68") : Color(hex: "#9ca3af") }
    var t5: Color { dark ? Color(hex: "#2e3448") : Color(hex: "#b0b8c4") }

    // Input
    var inp:   Color { dark ? Color(hex: "#222333") : Color(hex: "#f9fafb") }
    var inpBd: Color { dark ? Color(hex: "#333548") : Color(hex: "#e8eaed") }

    // States
    var hov:  Color { dark ? Color(hex: "#252636") : Color(hex: "#f5f5f5") }
    var card: Color { dark ? Color(hex: "#1e1f2d") : Color(hex: "#ffffff") }

    // Labels (metric tiles, section headers)
    var lbl: Color { dark ? Color(hex: "#4a5272") : Color(hex: "#a0a8b4") }

    // Server log — always dark regardless of mode
    var logBg: Color { dark ? Color(hex: "#09090e") : Color(hex: "#0e1016") }
    var logBd: Color { dark ? Color(hex: "#181926") : Color(hex: "#1e2330") }

    // Log level colors — fixed, never theme-aware
    let logTimestamp: Color = Color(hex: "#2d3444")
    let logINF:       Color = Color(hex: "#10b981")
    let logWRN:       Color = Color(hex: "#f59e0b")
    let logERR:       Color = Color(hex: "#ef4444")
    let logMsgINF:    Color = Color(hex: "#8892a4")
    let logMsgWRN:    Color = Color(hex: "#fbbf24")
    let logMsgERR:    Color = Color(hex: "#f87171")

    // Pill buttons
    var pill:   Color { dark ? Color(hex: "#252636") : Color(hex: "#f0f0f0") }
    var pillBd: Color { dark ? Color(hex: "#333548") : Color(hex: "#d8d8d8") }
    var pillT:  Color { dark ? Color(hex: "#8892a4") : Color(hex: "#7a7a7a") }

    // Small action buttons
    var btnBg: Color { dark ? Color(hex: "#252636") : Color(hex: "#f3f4f6") }
    var btnBd: Color { dark ? Color(hex: "#333548") : Color(hex: "#e5e7eb") }
    var btnT:  Color { dark ? Color(hex: "#8892a4") : Color(hex: "#6b7280") }
}

// MARK: - EnvironmentKey

private struct CortexThemeKey: EnvironmentKey {
    static let defaultValue = CortexTheme(dark: false, accent: AccentPreset.emerald.color)
}

extension EnvironmentValues {
    var cortexTheme: CortexTheme {
        get { self[CortexThemeKey.self] }
        set { self[CortexThemeKey.self] = newValue }
    }
}

// MARK: - ThemeProvider

/// Wraps a view so it reacts to system colorScheme and stored accent changes.
struct ThemeProvider<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("cortex_accent") private var accentRaw: String = AccentPreset.emerald.rawValue
    let content: () -> Content

    var body: some View {
        let theme = CortexTheme(
            dark: colorScheme == .dark,
            accent: Color(hex: accentRaw)
        )
        content()
            .environment(\.cortexTheme, theme)
    }
}
