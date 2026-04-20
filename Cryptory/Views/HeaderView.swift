import SwiftUI

struct ExchangeButtonBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct HeaderView: View {
    @ObservedObject var vm: CryptoViewModel
    private let controlHeight: CGFloat = 44
    private let controlCornerRadius: CGFloat = 18
    private let exchangeMinimumWidth: CGFloat = 136

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            brandSection
                .frame(maxWidth: .infinity, alignment: .leading)

            if vm.shouldShowExchangeSelector {
                exchangeButton
                    .layoutPriority(1)
                    .anchorPreference(key: ExchangeButtonBoundsPreferenceKey.self, value: .bounds) { $0 }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color.bg.opacity(0.98), Color.bg.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.18)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.themeBorder.opacity(0.7))
                    .frame(height: 1)
            }
        )
        .animation(.easeInOut(duration: 0.2), value: vm.activeTab)
    }

    private var brandSection: some View {
        HStack(alignment: .center, spacing: 12) {
            brandMark
            brandText
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BrandIdentity.accessibilityLabel)
    }

    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accent, Color(hex: "#D97706")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)

            Text("₿")
                .font(.system(size: 18, weight: .black))
                .foregroundColor(.black.opacity(0.86))
        }
    }

    private var brandText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(BrandIdentity.koreanName)
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.themeText)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Text(BrandIdentity.englishName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineLimit(1)

            Text(BrandIdentity.tagline)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textMuted)
                .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var exchangeButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                vm.showExchangeMenu.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                ExchangeIcon(exchange: vm.selectedExchange, size: 20)
                    .fixedSize()

                Text(vm.selectedExchange.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.themeText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 10, height: 10)
            }
            .padding(.horizontal, 12)
            .frame(minWidth: exchangeMinimumWidth, idealWidth: 150, maxWidth: 170)
            .frame(height: controlHeight)
            .background(controlBackground(cornerRadius: controlCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func controlBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.bgSecondary.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
    }
}
