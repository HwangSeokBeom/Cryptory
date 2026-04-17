import SwiftUI

struct PremiumCard: View {
    let coinViewState: KimchiPremiumCoinViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Text(coinViewState.symbol)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.themeText)
                    Text(coinViewState.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }
                Spacer()
                Text(coinViewState.referenceLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }

            HStack(spacing: 6) {
                ForEach(coinViewState.cells) { cell in
                    VStack(spacing: 4) {
                        ExchangeIcon(exchange: cell.exchange, size: 16)

                        Text(cell.exchange.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)

                        Text(cell.premiumText)
                            .font(.mono(13, weight: .heavy))
                            .foregroundColor(textColor(for: cell))

                        Text(cell.domesticPriceText)
                            .font(.mono(9))
                            .foregroundColor(.textMuted)

                        Text("환산 \(cell.referencePriceText)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.textSecondary)

                        if let warningMessage = cell.warningMessage, !warningMessage.isEmpty {
                            Text(warningMessage)
                                .font(.system(size: 8))
                                .foregroundColor(.accent)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.bgTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.themeBorder, lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func textColor(for cell: KimchiPremiumExchangeCellViewState) -> Color {
        if cell.isStale {
            return .accent
        }
        return cell.premiumText.hasPrefix("-") ? .down : .up
    }
}
