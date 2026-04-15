import SwiftUI

extension Color {
    // MARK: - Hex Initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Design Tokens
    static let bg = Color(hex: "#0A0E17")
    static let bgCard = Color(hex: "#111827")
    static let bgSecondary = Color(hex: "#1A2236")
    static let bgTertiary = Color(hex: "#1F2A40")
    static let themeBorder = Color(hex: "#2A3550")
    static let borderLight = Color(hex: "#354265")
    static let themeText = Color(hex: "#E8ECF4")
    static let textSecondary = Color(hex: "#8B95A8")
    static let textMuted = Color(hex: "#5A6478")
    static let up = Color(hex: "#EF4444")
    static let upBg = Color(hex: "#EF4444").opacity(0.1)
    static let down = Color(hex: "#3B82F6")
    static let downBg = Color(hex: "#3B82F6").opacity(0.1)
    static let accent = Color(hex: "#F59E0B")
    static let accentBg = Color(hex: "#F59E0B").opacity(0.12)
    static let primary = Color(hex: "#6366F1")
    static let success = Color(hex: "#10B981")
    static let danger = Color(hex: "#EF4444")
}
