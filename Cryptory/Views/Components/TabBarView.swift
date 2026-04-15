import SwiftUI
import UIKit

enum AppTabBarAppearance {
    private static let backgroundColor = UIColor(hex: "#12192A", alpha: 0.88)
    private static let shadowColor = UIColor(hex: "#2A3550", alpha: 0.38)
    private static let selectedColor = UIColor(hex: "#F59E0B")
    private static let normalColor = UIColor(hex: "#A6B1C5")

    static func configure() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = backgroundColor
        appearance.shadowColor = shadowColor

        let itemAppearance = UITabBarItemAppearance(style: .stacked)
        itemAppearance.normal.iconColor = normalColor
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalColor,
            .font: UIFont.systemFont(ofSize: 11, weight: .medium)
        ]
        itemAppearance.selected.iconColor = selectedColor
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = true
        UITabBar.appearance().tintColor = selectedColor
        UITabBar.appearance().unselectedItemTintColor = normalColor
    }
}

private extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
