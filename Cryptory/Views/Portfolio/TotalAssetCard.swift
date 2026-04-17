import SwiftUI

struct TotalAssetCard: View {
    @ObservedObject var vm: CryptoViewModel

    private var isUp: Bool { vm.totalPnl >= 0 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                    statColumn(
                        label: "평가손익",
                        value: "\(vm.totalPnl >= 0 ? "+" : "")₩" + PriceFormatter.formatInteger(vm.totalPnl),
                        color: isUp ? .up : .down
                    )
                    statColumn(
                        label: "수익률",
                        value: String(format: "%@%.2f%%", vm.totalPnlPercent >= 0 ? "+" : "", vm.totalPnlPercent),
                        color: isUp ? .up : .down
                    )

                    if let snapshot = vm.portfolioState.value {
                        statColumn(
                            label: "가용자산",
                            value: "₩" + PriceFormatter.formatInteger(snapshot.availableAsset),
                            color: .accent
                        )
                        statColumn(
                            label: "잠금자산",
                            value: "₩" + PriceFormatter.formatInteger(snapshot.lockedAsset),
                            color: .themeText
                        )
                    }
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

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.mono(14, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
