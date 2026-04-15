import SwiftUI

struct CoinRowView: View {
    @ObservedObject var vm: CryptoViewModel
    let coin: CoinInfo

    private var ticker: TickerData? {
        vm.prices[coin.symbol]?[vm.exchange.rawValue]
    }

    private var isUp: Bool {
        (ticker?.change ?? 0) >= 0
    }

    var body: some View {
        Button {
            vm.selectCoin(coin)
        } label: {
            HStack(spacing: 0) {
                // Left: Star + Symbol + Name
                HStack(spacing: 8) {
                    Button {
                        vm.toggleFavorite(coin.symbol)
                    } label: {
                        Image(systemName: vm.favCoins.contains(coin.symbol) ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(vm.favCoins.contains(coin.symbol) ? .accent : .textMuted)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(coin.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.themeText)
                        Text(coin.name)
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Price
                Group {
                    if let ticker {
                        Text(PriceFormatter.formatPrice(ticker.price))
                            .font(.mono(13, weight: .bold))
                            .foregroundColor(isUp ? .up : .down)
                    } else {
                        Text("—")
                            .font(.mono(13, weight: .bold))
                            .foregroundColor(.textMuted)
                    }
                }
                .frame(width: 90, alignment: .trailing)
                .padding(.vertical, 4)
                .background(flashBackground)

                // Change
                Group {
                    if let ticker {
                        Text(formatChange(ticker.change))
                            .font(.mono(12, weight: .semibold))
                            .foregroundColor(isUp ? .up : .down)
                    } else {
                        Text("—")
                            .font(.mono(12, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                }
                .frame(width: 60, alignment: .trailing)

                // Sparkline
                SparklineView(
                    data: ticker?.sparkline ?? [],
                    isUp: isUp
                )
                .frame(width: 55, alignment: .trailing)
                .padding(.leading, 5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var flashBackground: some View {
        Group {
            if let flash = ticker?.flash {
                RoundedRectangle(cornerRadius: 4)
                    .fill(flash == .up ? Color.up.opacity(0.15) : Color.down.opacity(0.15))
                    .animation(.easeOut(duration: 0.5), value: ticker?.flash == nil)
            } else {
                Color.clear
            }
        }
    }

    private func formatChange(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}
