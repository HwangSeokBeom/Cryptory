import SwiftUI

struct PremiumCard: View, Equatable {
    let coinViewState: KimchiPremiumCoinViewState
    let selectedExchange: Exchange

    static func == (lhs: PremiumCard, rhs: PremiumCard) -> Bool {
        lhs.coinViewState == rhs.coinViewState && lhs.selectedExchange == rhs.selectedExchange
    }

    var body: some View {
        if let cell = coinViewState.cells.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(coinViewState.symbol)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.themeText)
                            Text(coinViewState.displayName)
                                .font(.system(size: 11))
                                .foregroundColor(.textMuted)
                        }

                        HStack(spacing: 8) {
                            ExchangeIcon(exchange: selectedExchange, size: 18)
                            Text(selectedExchange.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.themeText)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        if let badgeTitle = statusBadgeTitle(for: cell) {
                            Text(badgeTitle)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(badgeForegroundColor(for: cell))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(badgeBackgroundColor(for: cell))
                                )
                                .accessibilityIdentifier("kimchiFreshnessBadge.\(coinViewState.symbol)")
                        }

                        Text(coinViewState.referenceLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.textMuted)
                    }
                }

                HStack(spacing: 10) {
                    metricBlock(
                        title: "김프",
                        value: cell.premiumText,
                        valueColor: premiumTextColor(for: cell)
                    )
                    metricDivider
                    metricBlock(
                        title: "국내가",
                        value: cell.domesticPriceText,
                        valueColor: cell.domesticPriceIsPlaceholder ? .textSecondary : .themeText
                    )
                    metricDivider
                    metricBlock(
                        title: coinViewState.referenceLabel,
                        value: cell.referencePriceText,
                        valueColor: cell.referencePriceIsPlaceholder ? .textSecondary : .themeText
                    )
                }

                HStack(spacing: 8) {
                    if let updatedAgoText = cell.updatedAgoText {
                        Text(updatedAgoText)
                    } else if cell.status == .loading {
                        Text("업데이트 확인 중")
                    }

                    if let note = secondaryNote(for: cell) {
                        Text(note)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textMuted)
                .lineLimit(2)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selectedExchange.color.opacity(0.14), lineWidth: 1)
                    )
            )
        }
    }

    private func statusBadgeTitle(for cell: KimchiPremiumExchangeCellViewState) -> String? {
        switch cell.freshnessState {
        case .loading:
            return cell.premiumIsPlaceholder ? nil : "실시간"
        case .partialUpdate:
            return "일부 지연"
        case .referencePriceDelayed, .exchangeRateDelayed, .stale:
            return "약간 지연"
        case .available:
            return "실시간"
        case .unavailable:
            return "데이터 없음"
        }
    }

    private func premiumTextColor(for cell: KimchiPremiumExchangeCellViewState) -> Color {
        if cell.status == .failed || cell.status == .unavailable || cell.premiumIsPlaceholder {
            return .textSecondary
        }
        return cell.premiumText.hasPrefix("-") ? .down : .up
    }

    private func secondaryNote(for cell: KimchiPremiumExchangeCellViewState) -> String? {
        switch cell.freshnessState {
        case .partialUpdate:
            return "확인된 가격부터 표시 중"
        case .referencePriceDelayed, .exchangeRateDelayed, .stale:
            return nil
        case .unavailable:
            return nil
        case .loading, .available:
            return nil
        }
    }

    private func metricBlock(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textMuted)
                .lineLimit(1)

            Text(value)
                .font(.mono(13, weight: .heavy))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.themeBorder)
            .frame(width: 1, height: 34)
    }

    private func badgeForegroundColor(for cell: KimchiPremiumExchangeCellViewState) -> Color {
        switch cell.freshnessState {
        case .loading, .available:
            return .up
        case .partialUpdate, .referencePriceDelayed, .exchangeRateDelayed, .stale:
            return .accent
        case .unavailable:
            return .textSecondary
        }
    }

    private func badgeBackgroundColor(for cell: KimchiPremiumExchangeCellViewState) -> Color {
        switch cell.freshnessState {
        case .loading, .available:
            return Color.up.opacity(0.12)
        case .partialUpdate, .referencePriceDelayed, .exchangeRateDelayed, .stale:
            return Color.accent.opacity(0.12)
        case .unavailable:
            return Color.bgTertiary
        }
    }
}
