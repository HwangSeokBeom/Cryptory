import SwiftUI

extension Font {
    /// Monospaced font for prices and numbers
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// UI text font
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    func monoStyle(size: CGFloat, weight: Font.Weight = .bold, color: Color = .themeText) -> some View {
        self
            .font(.mono(size, weight: weight))
            .foregroundColor(color)
    }
}
