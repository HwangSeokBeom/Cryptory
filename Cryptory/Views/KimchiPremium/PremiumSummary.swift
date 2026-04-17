import SwiftUI

struct PremiumSummary: View {
    let coinViewStates: [KimchiPremiumCoinViewState]

    private var exchanges: [Exchange] {
        let exchangeSet = Set(coinViewStates.flatMap { $0.cells.map(\.exchange) })
        return exchangeSet.sorted { $0.displayName < $1.displayName }
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
                ForEach(exchanges) { exchange in
                    let premiums = premiumValues(for: exchange)
                    let average = premiums.isEmpty ? nil : premiums.reduce(0, +) / Double(premiums.count)
                    let isUp = (average ?? 0) >= 0

                    HStack {
                        Text(exchange.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(average.map { String(format: "avg %@%.2f%%", $0 >= 0 ? "+" : "", $0) } ?? "대기중")
                            .font(.mono(13, weight: .heavy))
                            .foregroundColor(average == nil ? .textMuted : (isUp ? .up : .down))
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

    private func premiumValues(for exchange: Exchange) -> [Double] {
        coinViewStates.compactMap { coinViewState in
            coinViewState.cells.first { $0.exchange == exchange }
        }
        .compactMap { cell in
            let normalized = cell.premiumText.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
            return Double(normalized)
        }
    }
}
