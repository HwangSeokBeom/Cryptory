import SwiftUI

struct HoldingCard: View, Equatable {
    let holding: Holding
    let onSelect: () -> Void

    static func == (lhs: HoldingCard, rhs: HoldingCard) -> Bool {
        lhs.holding == rhs.holding
    }

    private var coin: CoinInfo {
        CoinCatalog.coin(symbol: holding.symbol)
    }

    private var isUp: Bool { holding.profitLoss >= 0 }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Text(holding.symbol)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.themeText)
                        Text(coin.name)
                            .font(.system(size: 11))
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    Text(String(format: "%@%.2f%%", holding.profitLossRate >= 0 ? "+" : "", holding.profitLossRate))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isUp ? .up : .down)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isUp ? Color.up.opacity(0.1) : Color.down.opacity(0.1))
                        )
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .trailing)
                ], spacing: 8) {
                    statCell(label: "총수량", value: PriceFormatter.formatQty6(holding.totalQuantity))
                    statCell(label: "평가금액", value: "₩" + PriceFormatter.formatInteger(holding.evaluationAmount))
                    statCell(label: "가용/잠금", value: "\(PriceFormatter.formatQty(holding.availableQuantity)) / \(PriceFormatter.formatQty(holding.lockedQuantity))")
                    statCell(label: "매수평균가", value: PriceFormatter.formatPrice(holding.averageBuyPrice))
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
            Text("\(holding.profitLoss >= 0 ? "+" : "")₩" + PriceFormatter.formatInteger(holding.profitLoss))
                .font(.mono(11, weight: .bold))
                .foregroundColor(isUp ? .up : .down)
        }
    }
}
