import SwiftUI

struct HoldingCard: View {
    @ObservedObject var vm: CryptoViewModel
    let holding: Holding

    private var coin: CoinInfo? {
        COINS.first { $0.symbol == holding.symbol }
    }

    private var currentPrice: Double {
        vm.prices[holding.symbol]?[vm.exchange.rawValue]?.price ?? holding.avgPrice
    }

    private var evalAmount: Double {
        currentPrice * holding.qty
    }

    private var pnl: Double {
        (currentPrice - holding.avgPrice) * holding.qty
    }

    private var pnlPercent: Double {
        guard holding.avgPrice > 0 else { return 0 }
        return (currentPrice - holding.avgPrice) / holding.avgPrice * 100
    }

    private var isUp: Bool { pnl >= 0 }

    var body: some View {
        Button {
            if let coin = coin {
                vm.selectCoinForTrade(coin)
            }
        } label: {
            VStack(spacing: 10) {
                // Top row
                HStack {
                    HStack(spacing: 6) {
                        Text(holding.symbol)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.themeText)
                        Text(coin?.name ?? "")
                            .font(.system(size: 11))
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    // PnL badge
                    let sign = pnlPercent >= 0 ? "+" : ""
                    Text(String(format: "%@%.2f%%", sign, pnlPercent))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isUp ? .up : .down)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isUp ? Color.up.opacity(0.1) : Color.down.opacity(0.1))
                        )
                }

                // 2x2 grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .trailing)
                ], spacing: 8) {
                    statCell(label: "보유수량", value: PriceFormatter.formatQty(holding.qty))
                    statCell(label: "평가금액", value: "₩" + PriceFormatter.formatInteger(evalAmount))
                    statCell(label: "매수평균가", value: PriceFormatter.formatPrice(holding.avgPrice))
                    pnlCell
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.mono(11, weight: .semibold))
                .foregroundColor(.themeText)
        }
    }

    private var pnlCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("평가손익")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
            let sign = pnl >= 0 ? "+" : ""
            Text("\(sign)₩" + PriceFormatter.formatInteger(pnl))
                .font(.mono(11, weight: .bold))
                .foregroundColor(isUp ? .up : .down)
        }
    }
}
