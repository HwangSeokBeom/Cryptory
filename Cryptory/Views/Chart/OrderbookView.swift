import SwiftUI

struct OrderbookView: View {
    let orderbook: OrderbookData?
    let currentPrice: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("호가창")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)
                .padding(.horizontal, 16)

            if let ob = orderbook {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("호가(KRW)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("잔량")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                    Divider().background(Color.themeBorder)

                    let maxQty = max(
                        ob.asks.map(\.qty).max() ?? 1,
                        ob.bids.map(\.qty).max() ?? 1
                    )

                    // Asks (sell orders) - reversed for display
                    ForEach(ob.asks) { ask in
                        orderbookRow(
                            price: ask.price,
                            qty: ask.qty,
                            maxQty: maxQty,
                            isBid: false
                        )
                    }

                    // Current price center
                    HStack {
                        Text(PriceFormatter.formatKRWSuffix(currentPrice))
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentBg)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    // Bids (buy orders)
                    ForEach(ob.bids) { bid in
                        orderbookRow(
                            price: bid.price,
                            qty: bid.qty,
                            maxQty: maxQty,
                            isBid: true
                        )
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
                .padding(.horizontal, 16)
            }
        }
    }

    private func orderbookRow(price: Double, qty: Double, maxQty: Double, isBid: Bool) -> some View {
        HStack {
            Text(PriceFormatter.formatPrice(price))
                .font(.mono(11))
                .foregroundColor(isBid ? .up : .down)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(PriceFormatter.formatQty(qty))
                .font(.mono(11, weight: .regular))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(
            GeometryReader { geo in
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(isBid ? Color.up.opacity(0.1) : Color.down.opacity(0.1))
                        .frame(width: geo.size.width * min(qty / maxQty, 1.0))
                        .animation(.easeOut(duration: 0.3), value: qty)
                }
            }
        )
    }
}
