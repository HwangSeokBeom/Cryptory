import SwiftUI

struct ExchangeDropdown: View {
    @ObservedObject var vm: CryptoViewModel
    static let rowHeight: CGFloat = 48
    static let rowSpacing: CGFloat = 2
    static let containerInset: CGFloat = 2

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(Exchange.allCases) { ex in
                Button {
                    let selectedExchange = vm.selectedExchange
                    withAnimation(.easeOut(duration: 0.16)) {
                        vm.setExchangeMenuVisible(false)
                    }
                    guard selectedExchange != ex else {
                        return
                    }
                    vm.updateExchange(ex, source: "exchange_dropdown")
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
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                    .background(vm.selectedExchange == ex ? Color.bgTertiary : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Self.containerInset)
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
