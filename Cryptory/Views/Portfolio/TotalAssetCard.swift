import SwiftUI

struct TotalAssetCard: View, Equatable {
    let summary: PortfolioSummaryCardState

    private var isUp: Bool { summary.totalPnl >= 0 }

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

                Text("₩" + PriceFormatter.formatInteger(summary.totalAsset))
                    .font(.mono(28, weight: .heavy))
                    .foregroundColor(.themeText)

                HStack(spacing: 16) {
                    statColumn(
                        label: "평가손익",
                        value: "\(summary.totalPnl >= 0 ? "+" : "")₩" + PriceFormatter.formatInteger(summary.totalPnl),
                        color: isUp ? .up : .down
                    )
                    statColumn(
                        label: "수익률",
                        value: String(format: "%@%.2f%%", summary.totalPnlPercent >= 0 ? "+" : "", summary.totalPnlPercent),
                        color: isUp ? .up : .down
                    )
                    statColumn(
                        label: "가용자산",
                        value: "₩" + PriceFormatter.formatInteger(summary.availableAsset),
                        color: .accent
                    )
                    statColumn(
                        label: "잠금자산",
                        value: "₩" + PriceFormatter.formatInteger(summary.lockedAsset),
                        color: .themeText
                    )
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
