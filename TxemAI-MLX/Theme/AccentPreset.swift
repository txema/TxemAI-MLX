import SwiftUI

enum AccentPreset: String, CaseIterable {
    case emerald = "#10b981"
    case blue    = "#3b82f6"
    case violet  = "#8b5cf6"
    case amber   = "#f59e0b"
    case pink    = "#ec4899"

    var color: Color { Color(hex: rawValue) }

    var label: String {
        switch self {
        case .emerald: "Emerald"
        case .blue:    "Blue"
        case .violet:  "Violet"
        case .amber:   "Amber"
        case .pink:    "Pink"
        }
    }
}
