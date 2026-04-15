import SwiftUI

struct PremiumCard: View {
    @ObservedObject var vm: CryptoViewModel
    let coin: CoinInfo

    private var binancePrice: Double? {
        vm.prices[coin.symbol]?[Exchange.binance.rawValue]?.price
    }

    private let domesticExchanges: [Exchange] = [.upbit, .bithumb, .coinone, .korbit]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text(coin.symbol)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.themeText)
                    Text(coin.name)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }
                Spacer()
                Text("기준: \(formattedPrice(binancePrice)) KRW")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }

            // 4-column grid
            HStack(spacing: 6) {
                ForEach(domesticExchanges) { ex in
                    let exPrice = vm.prices[coin.symbol]?[ex.rawValue]?.price
                    let premium = premiumValue(domesticPrice: exPrice)
                    let isUp = (premium ?? 0) >= 0

                    VStack(spacing: 4) {
                        ExchangeIcon(exchange: ex, size: 16)

                        Text(ex.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)

                        Text(formattedPremium(premium))
                            .font(.mono(13, weight: .heavy))
                            .foregroundColor(premium == nil ? .textMuted : (isUp ? .up : .down))

                        Text(formattedPrice(exPrice))
                            .font(.mono(9))
                            .foregroundColor(.textMuted)
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

    private func premiumValue(domesticPrice: Double?) -> Double? {
        guard let binancePrice, let domesticPrice, binancePrice > 0 else { return nil }
        return (domesticPrice - binancePrice) / binancePrice * 100
    }

    private func formattedPremium(_ premium: Double?) -> String {
        guard let premium else { return "—" }
        return String(format: "%@%.2f%%", premium >= 0 ? "+" : "", premium)
    }

    private func formattedPrice(_ price: Double?) -> String {
        guard let price else { return "—" }
        return PriceFormatter.formatPrice(price)
    }
}
