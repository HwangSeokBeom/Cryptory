import SwiftUI

struct PremiumSummary: View {
    @ObservedObject var vm: CryptoViewModel

    private let domesticExchanges: [Exchange] = [.upbit, .bithumb, .coinone, .korbit]
    private var topCoins: [CoinInfo] { Array(COINS.prefix(8)) }

    private func avgPremium(for exchange: Exchange) -> Double? {
        let premiums = topCoins.compactMap { coin -> Double? in
            guard let exPrice = vm.prices[coin.symbol]?[exchange.rawValue]?.price,
                  let binPrice = vm.prices[coin.symbol]?[Exchange.binance.rawValue]?.price,
                  binPrice > 0 else { return nil }
            return (exPrice - binPrice) / binPrice * 100
        }
        guard !premiums.isEmpty else { return nil }
        return premiums.reduce(0, +) / Double(premiums.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                Text("김프 요약")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(domesticExchanges) { ex in
                    let avg = avgPremium(for: ex)
                    let isUp = (avg ?? 0) >= 0

                    HStack {
                        Text(ex.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(avg.map { String(format: "avg %@%.2f%%", $0 >= 0 ? "+" : "", $0) } ?? "대기중")
                            .font(.mono(13, weight: .heavy))
                            .foregroundColor(avg == nil ? .textMuted : (isUp ? .up : .down))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.bgSecondary)
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.accent.opacity(0.15), Color.accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accent.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
