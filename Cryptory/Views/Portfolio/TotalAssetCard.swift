import SwiftUI

struct TotalAssetCard: View {
    @ObservedObject var vm: CryptoViewModel

    private var isUp: Bool { vm.totalPnl >= 0 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Decorative circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accent.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .offset(x: 20, y: -20)

            VStack(alignment: .leading, spacing: 12) {
                Text("총 보유자산")
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)

                Text("₩" + PriceFormatter.formatInteger(vm.totalAsset))
                    .font(.mono(28, weight: .heavy))
                    .foregroundColor(.themeText)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("평가손익")
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                        let sign = isUp ? "+" : ""
                        Text("\(sign)₩" + PriceFormatter.formatInteger(vm.totalPnl))
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(isUp ? .up : .down)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("수익률")
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                        let sign = vm.totalPnlPercent >= 0 ? "+" : ""
                        Text(String(format: "%@%.2f%%", sign, vm.totalPnlPercent))
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(isUp ? .up : .down)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("보유현금")
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                        Text("₩" + PriceFormatter.formatInteger(vm.cash))
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color.bgSecondary, Color.bgTertiary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
        .clipped()
    }
}
