import SwiftUI

struct OrderHistoryRow: View {
    let order: OrderRecord

    private var isBuy: Bool { order.side == "buy" }

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text(isBuy ? "매수" : "매도")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isBuy ? .up : .down)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isBuy ? Color.up.opacity(0.1) : Color.down.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(order.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.themeText)
                    Text("\(order.orderType.title) · 잔량 \(PriceFormatter.formatQty(order.remainingQuantity))")
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(PriceFormatter.formatPrice(order.price))
                    .font(.mono(11))
                    .foregroundColor(.themeText)
                Text("\(order.exchange) · \(order.status)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(order.time)
                    .font(.system(size: 9))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
