import SwiftUI

struct RecentTradesView: View {
    let trades: [PublicTrade]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실시간 체결")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)

            if trades.isEmpty {
                Text("최근 체결 데이터가 아직 없어요.")
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
            } else {
                ForEach(trades.prefix(6)) { trade in
                    HStack {
                        Text(trade.side == "sell" ? "매도" : "매수")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(trade.side == "sell" ? .down : .up)
                            .frame(width: 34)

                        Text(PriceFormatter.formatPrice(trade.price))
                            .font(.mono(12, weight: .semibold))
                            .foregroundColor(.themeText)

                        Spacer()

                        Text(PriceFormatter.formatQty(trade.quantity))
                            .font(.mono(11))
                            .foregroundColor(.textMuted)

                        Text(trade.executedAt)
                            .font(.mono(10))
                            .foregroundColor(.textMuted)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.bgSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.themeBorder, lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}
