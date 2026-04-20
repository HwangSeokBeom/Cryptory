import SwiftUI

struct ExchangeDropdown: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Exchange.allCases) { ex in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        vm.updateExchange(ex, source: "exchange_dropdown")
                        vm.showExchangeMenu = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        ExchangeIcon(exchange: ex, size: 18)
                        Text(ex.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.themeText)
                            .lineLimit(1)
                        Spacer()
                        if vm.selectedExchange == ex {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(vm.selectedExchange == ex ? Color.bgTertiary : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 168)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgCard.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        )
    }
}

struct ExchangeIcon: View {
    let exchange: Exchange
    let size: CGFloat

    var body: some View {
        Text(exchange.iconText)
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(exchange.color)
            )
    }
}
