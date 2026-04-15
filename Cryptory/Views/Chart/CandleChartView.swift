import SwiftUI

struct CandleChartView: View {
    let candles: [CandleData]
    let width: CGFloat
    let height: CGFloat

    init(candles: [CandleData], width: CGFloat = 390, height: CGFloat = 220) {
        self.candles = candles
        self.width = width
        self.height = height
    }

    var body: some View {
        if candles.isEmpty {
            Rectangle()
                .fill(Color.bgSecondary)
                .frame(width: width, height: height)
                .cornerRadius(8)
        } else {
            Canvas { context, size in
                drawChart(context: context, size: size)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.bgSecondary.opacity(0.3))
            )
        }
    }

    private func drawChart(context: GraphicsContext, size: CGSize) {
        let margin = EdgeInsets(top: 10, leading: 5, bottom: 20, trailing: 5)
        let chartWidth = size.width - margin.leading - margin.trailing
        let chartHeight = size.height - margin.top - margin.bottom
        let volumeHeight = chartHeight * 0.25
        let candleHeight = chartHeight - volumeHeight

        let allPrices = candles.flatMap { [$0.high, $0.low] }
        guard let minPrice = allPrices.min(), let maxPrice = allPrices.max(), maxPrice > minPrice else { return }
        let priceRange = maxPrice - minPrice

        let maxVolume = Double(candles.map { $0.volume }.max() ?? 1)
        let barWidth = (chartWidth / CGFloat(candles.count)) * 0.6
        let barSpacing = chartWidth / CGFloat(candles.count)

        // Draw volume bars
        for (i, candle) in candles.enumerated() {
            let x = margin.leading + CGFloat(i) * barSpacing + barSpacing / 2
            let volH = (Double(candle.volume) / maxVolume) * Double(volumeHeight)
            let volY = margin.top + candleHeight + volumeHeight - CGFloat(volH)

            var volPath = Path()
            volPath.addRect(CGRect(
                x: x - barWidth / 2,
                y: volY,
                width: barWidth,
                height: CGFloat(volH)
            ))
            context.fill(volPath, with: .color(Color.accent.opacity(0.15)))
        }

        // Draw candles
        for (i, candle) in candles.enumerated() {
            let x = margin.leading + CGFloat(i) * barSpacing + barSpacing / 2
            let isUp = candle.close >= candle.open
            let color: Color = isUp ? .up : .down

            // Wick
            let highY = margin.top + (1 - (candle.high - minPrice) / priceRange) * Double(candleHeight)
            let lowY = margin.top + (1 - (candle.low - minPrice) / priceRange) * Double(candleHeight)

            var wickPath = Path()
            wickPath.move(to: CGPoint(x: x, y: CGFloat(highY)))
            wickPath.addLine(to: CGPoint(x: x, y: CGFloat(lowY)))
            context.stroke(wickPath, with: .color(color), lineWidth: 1)

            // Body
            let openY = margin.top + (1 - (candle.open - minPrice) / priceRange) * Double(candleHeight)
            let closeY = margin.top + (1 - (candle.close - minPrice) / priceRange) * Double(candleHeight)
            let bodyTop = min(openY, closeY)
            let bodyBottom = max(openY, closeY)
            let bodyHeight = max(bodyBottom - bodyTop, 1)

            var bodyPath = Path()
            bodyPath.addRect(CGRect(
                x: x - barWidth / 2,
                y: CGFloat(bodyTop),
                width: barWidth,
                height: CGFloat(bodyHeight)
            ))
            context.fill(bodyPath, with: .color(color))
        }
    }
}
