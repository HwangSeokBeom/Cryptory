import SwiftUI

struct TotalAssetCard: View, Equatable {
    let title: String
    let totalAsset: Double
    let availableAsset: Double
    let lockedAsset: Double
    let cash: Double?
    let totalPnl: Double
    let totalPnlPercent: Double
    let exchangeCount: Int?

    init(summary: PortfolioSummaryCardState) {
        self.title = "총 보유자산"
        self.totalAsset = summary.totalAsset
        self.availableAsset = summary.availableAsset
        self.lockedAsset = summary.lockedAsset
        self.cash = nil
        self.totalPnl = summary.totalPnl
        self.totalPnlPercent = summary.totalPnlPercent
        self.exchangeCount = nil
    }

    init(overview: PortfolioOverviewCardState) {
        self.title = "총 보유자산"
        self.totalAsset = overview.totalAsset
        self.availableAsset = overview.availableAsset
        self.lockedAsset = overview.lockedAsset
        self.cash = overview.cash
        self.totalPnl = overview.totalPnl
        self.totalPnlPercent = overview.totalPnlPercent
        self.exchangeCount = overview.exchangeCount
    }

    private var isUp: Bool { totalPnl >= 0 }

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
                HStack(alignment: .center) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted)

                    Spacer()

                    if let exchangeCount {
                        Text("\(exchangeCount)개 거래소")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accent.opacity(0.12))
                            )
                    }
                }

                Text("₩" + PriceFormatter.formatInteger(totalAsset))
                    .font(.mono(28, weight: .heavy))
                    .foregroundColor(.themeText)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    spacing: 12
                ) {
                    statColumn(
                        label: "평가손익",
                        value: "\(totalPnl >= 0 ? "+" : "")₩" + PriceFormatter.formatInteger(totalPnl),
                        color: isUp ? .up : .down
                    )
                    statColumn(
                        label: "수익률",
                        value: String(format: "%@%.2f%%", totalPnlPercent >= 0 ? "+" : "", totalPnlPercent),
                        color: isUp ? .up : .down
                    )
                    statColumn(
                        label: "평가 기준",
                        value: "₩" + PriceFormatter.formatInteger(availableAsset),
                        color: .accent
                    )
                    statColumn(
                        label: "보류 자산",
                        value: "₩" + PriceFormatter.formatInteger(lockedAsset),
                        color: .themeText
                    )

                    if let cash {
                        statColumn(
                            label: "현금성",
                            value: "₩" + PriceFormatter.formatInteger(cash),
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
                .font(.mono(13, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
