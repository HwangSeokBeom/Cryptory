import SwiftUI

struct CandleChartView: View {
    let candles: [CandleData]
    let width: CGFloat
    let height: CGFloat
    let settings: ChartSettingsState
    let comparisonSeries: [ChartComparisonSeries]
    let currentPrice: Double
    let bestAskPrice: Double?
    let bestBidPrice: Double?

    init(
        candles: [CandleData],
        width: CGFloat = 390,
        height: CGFloat = 220,
        settings: ChartSettingsState = .default,
        comparisonSeries: [ChartComparisonSeries] = [],
        currentPrice: Double = 0,
        bestAskPrice: Double? = nil,
        bestBidPrice: Double? = nil
    ) {
        self.candles = candles
        self.width = width
        self.height = height
        self.settings = settings
        self.comparisonSeries = comparisonSeries
        self.currentPrice = currentPrice
        self.bestAskPrice = bestAskPrice
        self.bestBidPrice = bestBidPrice
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
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        let timeZone = settings.useUTC ? "UTC" : "KST"
        return "\(settings.selectedChartStyle.title) 차트, \(timeZone), 캔들 \(candles.count)개"
    }

    private func drawChart(context: GraphicsContext, size: CGSize) {
        let renderCandles = renderedCandles()
        guard renderCandles.isEmpty == false else { return }

        let margin = EdgeInsets(top: 13, leading: 7, bottom: 24, trailing: 7)
        let chartWidth = size.width - margin.leading - margin.trailing
        let chartHeight = size.height - margin.top - margin.bottom
        let drawsVolumePanel = shouldDrawSeparateVolumePanel
        let drawsOscillatorPanel = oscillatorMetric(for: renderCandles) != nil
        let volumeHeight = drawsVolumePanel ? chartHeight * (drawsOscillatorPanel ? 0.16 : 0.24) : 0
        let oscillatorHeight = drawsOscillatorPanel ? chartHeight * 0.2 : 0
        let panelGapCount = (drawsVolumePanel ? 1 : 0) + (drawsOscillatorPanel ? 1 : 0)
        let priceHeight = chartHeight - volumeHeight - oscillatorHeight - CGFloat(panelGapCount) * 8
        let priceTop = margin.top
        let oscillatorTop = drawsOscillatorPanel ? margin.top + priceHeight + 8 : 0
        let volumeTop = drawsVolumePanel
            ? (drawsOscillatorPanel ? oscillatorTop + oscillatorHeight + 8 : margin.top + priceHeight + 8)
            : 0
        let normalizedComparisonSeries = normalizedComparisonSeries(for: renderCandles)

        let referencePrices = bestPriceReferences
        let allPrices = renderCandles.flatMap { [$0.high, $0.low] }
            + normalizedComparisonSeries.flatMap(\.prices)
            + referencePrices
        guard let minPrice = allPrices.min(), let maxPrice = allPrices.max(), maxPrice > minPrice else { return }

        let priceRange = maxPrice - minPrice
        let spacing = chartWidth / CGFloat(max(renderCandles.count, 1))
        let barWidth = max(2, min(spacing * 0.64, 12))
        let colors = chartColors

        drawGrid(
            context: context,
            margin: margin,
            chartWidth: chartWidth,
            priceTop: priceTop,
            priceHeight: priceHeight
        )

        if shouldDrawVolumeOverlay {
            drawVolumeBars(
                renderCandles,
                context: context,
                margin: margin,
                volumeTop: priceTop + priceHeight * 0.72,
                volumeHeight: priceHeight * 0.28,
                spacing: spacing,
                barWidth: barWidth,
                colors: colors,
                usesDirectionalColors: false,
                fixedColor: Color(hex: settings.volumeOverlayConfiguration.primaryColorHex),
                opacity: 0.22,
                widthScale: CGFloat(max(settings.volumeOverlayConfiguration.lineWidth, 0.7))
            )
        }

        if drawsVolumePanel {
            drawVolumeBars(
                renderCandles,
                context: context,
                margin: margin,
                volumeTop: volumeTop,
                volumeHeight: volumeHeight,
                spacing: spacing,
                barWidth: barWidth,
                colors: colors,
                usesDirectionalColors: true,
                fixedColor: nil,
                opacity: 0.78,
                widthScale: CGFloat(max(settings.volumeConfiguration.lineWidth, 0.8))
            )
        }

        switch settings.selectedChartStyle {
        case .line:
            drawLine(renderCandles, context: context, margin: margin, priceTop: priceTop, priceHeight: priceHeight, minPrice: minPrice, priceRange: priceRange, spacing: spacing, color: colors.neutral, drawsMarkers: false, drawsArea: false, isStep: false)
        case .lineWithMarkers:
            drawLine(renderCandles, context: context, margin: margin, priceTop: priceTop, priceHeight: priceHeight, minPrice: minPrice, priceRange: priceRange, spacing: spacing, color: colors.neutral, drawsMarkers: true, drawsArea: false, isStep: false)
        case .stepLine:
            drawLine(renderCandles, context: context, margin: margin, priceTop: priceTop, priceHeight: priceHeight, minPrice: minPrice, priceRange: priceRange, spacing: spacing, color: colors.neutral, drawsMarkers: false, drawsArea: false, isStep: true)
        case .area, .baseline:
            drawLine(renderCandles, context: context, margin: margin, priceTop: priceTop, priceHeight: priceHeight, minPrice: minPrice, priceRange: priceRange, spacing: spacing, color: colors.neutral, drawsMarkers: false, drawsArea: true, isStep: false)
            if settings.selectedChartStyle == .baseline, let firstClose = renderCandles.first?.close {
                drawHorizontalLine(
                    context: context,
                    price: firstClose,
                    minPrice: minPrice,
                    priceRange: priceRange,
                    margin: margin,
                    chartWidth: chartWidth,
                    priceTop: priceTop,
                    priceHeight: priceHeight,
                    color: colors.neutral.opacity(0.36),
                    label: nil,
                    dashed: true
                )
            }
        case .histogram, .distribution:
            drawHistogram(renderCandles, context: context, margin: margin, priceTop: priceTop, priceHeight: priceHeight, minPrice: minPrice, priceRange: priceRange, spacing: spacing, barWidth: barWidth, colors: colors)
        case .bar, .coloredBar, .coloredHLCBar:
            drawOHLCBars(renderCandles, context: context, margin: margin, priceTop: priceTop, priceHeight: priceHeight, minPrice: minPrice, priceRange: priceRange, spacing: spacing, barWidth: barWidth, colors: colors)
        case .candle, .hollowCandle, .volumeCandle, .heikinAshi:
            drawCandles(renderCandles, context: context, margin: margin, priceTop: priceTop, priceHeight: priceHeight, minPrice: minPrice, priceRange: priceRange, spacing: spacing, barWidth: barWidth, colors: colors)
        }

        drawComparisonLines(
            normalizedComparisonSeries,
            context: context,
            margin: margin,
            priceTop: priceTop,
            priceHeight: priceHeight,
            minPrice: minPrice,
            priceRange: priceRange,
            spacing: spacing
        )

        drawSelectedOverlays(
            renderCandles,
            context: context,
            margin: margin,
            chartWidth: chartWidth,
            priceTop: priceTop,
            priceHeight: priceHeight,
            minPrice: minPrice,
            priceRange: priceRange,
            spacing: spacing
        )

        if drawsOscillatorPanel, let oscillatorMetric = oscillatorMetric(for: renderCandles) {
            drawOscillatorPanel(
                oscillatorMetric,
                context: context,
                margin: margin,
                panelTop: oscillatorTop,
                panelHeight: oscillatorHeight,
                spacing: spacing
            )
        }

        if settings.showBestBidAskLine {
            drawBestBidAskLines(
                context: context,
                margin: margin,
                chartWidth: chartWidth,
                priceTop: priceTop,
                priceHeight: priceHeight,
                minPrice: minPrice,
                priceRange: priceRange
            )
        }

        drawTimeAxis(
            renderCandles,
            context: context,
            margin: margin,
            chartWidth: chartWidth,
            size: size
        )
    }

    private var shouldDrawSeparateVolumePanel: Bool {
        settings.selectedBottomIndicators.contains(.volume)
            || settings.selectedChartStyle == .volumeCandle
    }

    private var shouldDrawVolumeOverlay: Bool {
        settings.selectedTopIndicators.contains(.volumeOverlay)
    }

    private var bestPriceReferences: [Double] {
        guard settings.showBestBidAskLine else {
            return []
        }
        return [bestAskPrice, bestBidPrice, currentPrice > 0 ? currentPrice : nil].compactMap { $0 }
    }

    private var chartColors: ChartColors {
        if settings.useGlobalExchangeColorScheme {
            return ChartColors(
                up: Color(hex: "#10B981"),
                down: Color(hex: "#EF4444"),
                neutral: Color(hex: "#E8ECF4"),
                volume: Color(hex: "#3B82F6")
            )
        }
        return ChartColors(up: .up, down: .down, neutral: .themeText, volume: .accent)
    }

    private func renderedCandles() -> [RenderCandle] {
        let base = candles.map {
            RenderCandle(
                time: $0.time,
                open: $0.open,
                high: $0.high,
                low: $0.low,
                close: $0.close,
                volume: Double($0.volume)
            )
        }

        guard settings.selectedChartStyle == .heikinAshi else {
            return base
        }

        var rendered: [RenderCandle] = []
        for candle in base {
            let haClose = (candle.open + candle.high + candle.low + candle.close) / 4
            let haOpen: Double
            if let previous = rendered.last {
                haOpen = (previous.open + previous.close) / 2
            } else {
                haOpen = (candle.open + candle.close) / 2
            }
            rendered.append(
                RenderCandle(
                    time: candle.time,
                    open: haOpen,
                    high: max(candle.high, haOpen, haClose),
                    low: min(candle.low, haOpen, haClose),
                    close: haClose,
                    volume: candle.volume
                )
            )
        }
        return rendered
    }

    private func drawGrid(
        context: GraphicsContext,
        margin: EdgeInsets,
        chartWidth: CGFloat,
        priceTop: CGFloat,
        priceHeight: CGFloat
    ) {
        let gridColor = Color.themeBorder.opacity(0.28)

        for index in 0...3 {
            let y = priceTop + priceHeight * CGFloat(index) / 3
            var path = Path()
            path.move(to: CGPoint(x: margin.leading, y: y))
            path.addLine(to: CGPoint(x: margin.leading + chartWidth, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.7)
        }
    }

    private func drawVolumeBars(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        volumeTop: CGFloat,
        volumeHeight: CGFloat,
        spacing: CGFloat,
        barWidth: CGFloat,
        colors: ChartColors,
        usesDirectionalColors: Bool,
        fixedColor: Color?,
        opacity: Double,
        widthScale: CGFloat
    ) {
        let maxVolume = max(candles.map(\.volume).max() ?? 1, 1)
        let effectiveBarWidth = max(1, barWidth * widthScale)

        for (index, candle) in candles.enumerated() {
            let x = xPosition(index: index, margin: margin, spacing: spacing)
            let height = max(1, CGFloat(candle.volume / maxVolume) * volumeHeight)
            let y = volumeTop + volumeHeight - height
            let color: Color
            if let fixedColor {
                color = fixedColor.opacity(opacity)
            } else if usesDirectionalColors {
                color = (candle.close >= candle.open ? colors.up : colors.down).opacity(opacity)
            } else {
                color = colors.volume.opacity(opacity)
            }

            var path = Path()
            path.addRect(CGRect(x: x - effectiveBarWidth / 2, y: y, width: effectiveBarWidth, height: height))
            context.fill(path, with: .color(color))
        }
    }

    private func drawCandles(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat,
        barWidth: CGFloat,
        colors: ChartColors
    ) {
        let maxVolume = max(candles.map(\.volume).max() ?? 1, 1)

        for (index, candle) in candles.enumerated() {
            let x = xPosition(index: index, margin: margin, spacing: spacing)
            let isUp = candle.close >= candle.open
            let color = isUp ? colors.up : colors.down
            let bodyWidth = settings.selectedChartStyle == .volumeCandle
                ? max(2, barWidth * CGFloat(0.45 + candle.volume / maxVolume * 0.8))
                : barWidth

            let highY = yPosition(candle.high, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let lowY = yPosition(candle.low, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let openY = yPosition(candle.open, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let closeY = yPosition(candle.close, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)

            var wickPath = Path()
            wickPath.move(to: CGPoint(x: x, y: highY))
            wickPath.addLine(to: CGPoint(x: x, y: lowY))
            context.stroke(wickPath, with: .color(color), lineWidth: 1)

            let bodyTop = min(openY, closeY)
            let bodyHeight = max(abs(closeY - openY), 1)
            let rect = CGRect(x: x - bodyWidth / 2, y: bodyTop, width: bodyWidth, height: bodyHeight)
            var bodyPath = Path()
            bodyPath.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))

            if settings.selectedChartStyle == .hollowCandle && isUp {
                context.stroke(bodyPath, with: .color(color), lineWidth: 1.2)
            } else {
                context.fill(bodyPath, with: .color(color))
            }
        }
    }

    private func drawOHLCBars(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat,
        barWidth: CGFloat,
        colors: ChartColors
    ) {
        for (index, candle) in candles.enumerated() {
            let x = xPosition(index: index, margin: margin, spacing: spacing)
            let color = candle.close >= candle.open ? colors.up : colors.down
            let highY = yPosition(candle.high, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let lowY = yPosition(candle.low, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let openY = yPosition(candle.open, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let closeY = yPosition(candle.close, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let tick = max(3, barWidth * 0.45)

            var path = Path()
            path.move(to: CGPoint(x: x, y: highY))
            path.addLine(to: CGPoint(x: x, y: lowY))
            path.move(to: CGPoint(x: x - tick, y: openY))
            path.addLine(to: CGPoint(x: x, y: openY))
            path.move(to: CGPoint(x: x, y: closeY))
            path.addLine(to: CGPoint(x: x + tick, y: closeY))
            context.stroke(path, with: .color(color), lineWidth: settings.selectedChartStyle == .bar ? 1 : 1.3)
        }
    }

    private func drawLine(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat,
        color: Color,
        drawsMarkers: Bool,
        drawsArea: Bool,
        isStep: Bool
    ) {
        guard let first = candles.first else { return }

        var path = Path()
        let firstPoint = point(
            index: 0,
            price: first.close,
            margin: margin,
            spacing: spacing,
            minPrice: minPrice,
            priceRange: priceRange,
            top: priceTop,
            height: priceHeight
        )
        path.move(to: firstPoint)

        for index in candles.indices.dropFirst() {
            let previousPoint = point(
                index: index - 1,
                price: candles[index - 1].close,
                margin: margin,
                spacing: spacing,
                minPrice: minPrice,
                priceRange: priceRange,
                top: priceTop,
                height: priceHeight
            )
            let nextPoint = point(
                index: index,
                price: candles[index].close,
                margin: margin,
                spacing: spacing,
                minPrice: minPrice,
                priceRange: priceRange,
                top: priceTop,
                height: priceHeight
            )

            if isStep {
                path.addLine(to: CGPoint(x: nextPoint.x, y: previousPoint.y))
            }
            path.addLine(to: nextPoint)
        }

        if drawsArea, let last = candles.indices.last {
            var area = path
            let lastX = xPosition(index: last, margin: margin, spacing: spacing)
            let baselineY = priceTop + priceHeight
            area.addLine(to: CGPoint(x: lastX, y: baselineY))
            area.addLine(to: CGPoint(x: firstPoint.x, y: baselineY))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.24), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: priceTop),
                endPoint: CGPoint(x: 0, y: priceTop + priceHeight)
            ))
        }

        context.stroke(path, with: .color(color), lineWidth: 1.7)

        if drawsMarkers {
            for index in candles.indices {
                let markerPoint = point(
                    index: index,
                    price: candles[index].close,
                    margin: margin,
                    spacing: spacing,
                    minPrice: minPrice,
                    priceRange: priceRange,
                    top: priceTop,
                    height: priceHeight
                )
                var marker = Path()
                marker.addEllipse(in: CGRect(x: markerPoint.x - 2.2, y: markerPoint.y - 2.2, width: 4.4, height: 4.4))
                context.fill(marker, with: .color(color))
            }
        }
    }

    private func drawHistogram(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat,
        barWidth: CGFloat,
        colors: ChartColors
    ) {
        let baselinePrice = candles.first?.close ?? minPrice
        let baselineY = yPosition(baselinePrice, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)

        for (index, candle) in candles.enumerated() {
            let x = xPosition(index: index, margin: margin, spacing: spacing)
            let closeY = yPosition(candle.close, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            let top = min(closeY, baselineY)
            let height = max(abs(closeY - baselineY), 1)
            let color = candle.close >= baselinePrice ? colors.up : colors.down
            var path = Path()
            path.addRect(CGRect(x: x - barWidth / 2, y: top, width: barWidth, height: height))
            context.fill(path, with: .color(color.opacity(settings.selectedChartStyle == .distribution ? 0.55 : 0.8)))
        }
    }

    private func drawSelectedOverlays(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        chartWidth: CGFloat,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat
    ) {
        if settings.selectedTopIndicators.contains(.bollingerBand) {
            drawBollingerBand(
                candles,
                context: context,
                margin: margin,
                priceTop: priceTop,
                priceHeight: priceHeight,
                minPrice: minPrice,
                priceRange: priceRange,
                spacing: spacing,
                configuration: settings.bollingerBandConfiguration
            )
        }

        if settings.selectedTopIndicators.contains(.movingAverage) {
            drawMovingAverage(
                candles,
                context: context,
                margin: margin,
                priceTop: priceTop,
                priceHeight: priceHeight,
                minPrice: minPrice,
                priceRange: priceRange,
                spacing: spacing,
                configuration: settings.movingAverageConfiguration
            )
        }

        if settings.selectedTopIndicators.contains(.parabolicSAR) {
            drawParabolicDots(
                candles,
                context: context,
                margin: margin,
                priceTop: priceTop,
                priceHeight: priceHeight,
                minPrice: minPrice,
                priceRange: priceRange,
                spacing: spacing,
                configuration: settings.parabolicSARConfiguration
            )
        }

        drawIndicatorLegend(context: context, margin: margin, chartWidth: chartWidth)
    }

    private func drawMovingAverage(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat,
        configuration: ChartIndicatorConfiguration
    ) {
        let period = min(max(configuration.period, 2), max(candles.count, 2))
        let points = movingAveragePoints(
            candles,
            period: period,
            margin: margin,
            spacing: spacing,
            minPrice: minPrice,
            priceRange: priceRange,
            priceTop: priceTop,
            priceHeight: priceHeight
        )
        guard points.count > 1 else { return }

        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(
            path,
            with: .color(Color(hex: configuration.primaryColorHex).opacity(0.9)),
            lineWidth: max(0.8, configuration.lineWidth)
        )
    }

    private func drawBollingerBand(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat,
        configuration: ChartIndicatorConfiguration
    ) {
        let period = min(max(configuration.period, 2), max(candles.count, 2))
        let multiplier = configuration.multiplier ?? 2
        var upperPoints: [CGPoint] = []
        var lowerPoints: [CGPoint] = []

        for index in candles.indices {
            let start = max(0, index - period + 1)
            let values = candles[start...index].map(\.close)
            let average = values.reduce(0, +) / Double(values.count)
            let variance = values.map { pow($0 - average, 2) }.reduce(0, +) / Double(values.count)
            let deviation = sqrt(variance)
            upperPoints.append(
                point(index: index, price: average + deviation * multiplier, margin: margin, spacing: spacing, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            )
            lowerPoints.append(
                point(index: index, price: average - deviation * multiplier, margin: margin, spacing: spacing, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            )
        }

        guard upperPoints.count > 1, lowerPoints.count > 1 else { return }

        var band = Path()
        band.move(to: upperPoints[0])
        for point in upperPoints.dropFirst() {
            band.addLine(to: point)
        }
        for point in lowerPoints.reversed() {
            band.addLine(to: point)
        }
        band.closeSubpath()
        context.fill(
            band,
            with: .color(Color(hex: configuration.fillColorHex ?? configuration.primaryColorHex).opacity(0.12))
        )

        var upper = Path()
        upper.move(to: upperPoints[0])
        upperPoints.dropFirst().forEach { upper.addLine(to: $0) }
        var lower = Path()
        lower.move(to: lowerPoints[0])
        lowerPoints.dropFirst().forEach { lower.addLine(to: $0) }
        let strokeColor = Color(hex: configuration.primaryColorHex).opacity(0.76)
        context.stroke(upper, with: .color(strokeColor), lineWidth: max(0.8, configuration.lineWidth))
        context.stroke(lower, with: .color(strokeColor), lineWidth: max(0.8, configuration.lineWidth))
    }

    private func drawParabolicDots(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat,
        configuration: ChartIndicatorConfiguration
    ) {
        let strideValue = max(1, configuration.period)
        let dotSize = max(2.8, configuration.lineWidth * 2.1)
        let dotRadius = dotSize / 2
        let color = Color(hex: configuration.primaryColorHex).opacity(0.88)

        for index in candles.indices where index % strideValue == 0 {
            let candle = candles[index]
            let isUp = candle.close >= candle.open
            let price = isUp ? candle.low : candle.high
            let dotPoint = point(index: index, price: price, margin: margin, spacing: spacing, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
            var dot = Path()
            dot.addEllipse(in: CGRect(x: dotPoint.x - dotRadius, y: dotPoint.y - dotRadius, width: dotSize, height: dotSize))
            context.fill(dot, with: .color(color))
        }
    }

    private func normalizedComparisonSeries(for mainCandles: [RenderCandle]) -> [NormalizedComparisonSeries] {
        guard let mainBaseClose = mainCandles.first?.close, mainBaseClose > 0 else {
            return []
        }

        return comparisonSeries.compactMap { series in
            let sortedCandles = series.candles.sorted { $0.time < $1.time }
            guard let firstCompareClose = sortedCandles.first?.close, firstCompareClose > 0 else {
                return nil
            }

            var compareIndex = 0
            var lastKnownClose: Double?
            var points: [NormalizedComparisonPoint] = []
            var normalizedPrices: [Double] = []

            for (index, candle) in mainCandles.enumerated() {
                while compareIndex < sortedCandles.count, sortedCandles[compareIndex].time <= candle.time {
                    lastKnownClose = sortedCandles[compareIndex].close
                    compareIndex += 1
                }

                guard let compareClose = lastKnownClose ?? sortedCandles.first?.close else {
                    continue
                }

                let normalizedPrice = mainBaseClose * (compareClose / firstCompareClose)
                normalizedPrices.append(normalizedPrice)
                points.append(
                    NormalizedComparisonPoint(
                        index: index,
                        price: normalizedPrice
                    )
                )
            }

            guard points.count > 1 else {
                return nil
            }

            return NormalizedComparisonSeries(
                symbol: series.symbol,
                label: series.name,
                color: Color(hex: series.colorHex),
                prices: normalizedPrices,
                points: points
            )
        }
    }

    private func drawComparisonLines(
        _ series: [NormalizedComparisonSeries],
        context: GraphicsContext,
        margin: EdgeInsets,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double,
        spacing: CGFloat
    ) {
        for comparison in series {
            guard let firstPoint = comparison.points.first else {
                continue
            }

            var path = Path()
            path.move(
                to: point(
                    index: firstPoint.index,
                    price: firstPoint.price,
                    margin: margin,
                    spacing: spacing,
                    minPrice: minPrice,
                    priceRange: priceRange,
                    top: priceTop,
                    height: priceHeight
                )
            )

            for value in comparison.points.dropFirst() {
                path.addLine(
                    to: point(
                        index: value.index,
                        price: value.price,
                        margin: margin,
                        spacing: spacing,
                        minPrice: minPrice,
                        priceRange: priceRange,
                        top: priceTop,
                        height: priceHeight
                    )
                )
            }

            context.stroke(
                path,
                with: .color(comparison.color.opacity(0.92)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func oscillatorMetric(for candles: [RenderCandle]) -> OscillatorPanel? {
        var series: [OscillatorSeries] = []
        var rangeValues: [Double] = []
        var baseline: Double?
        var upperLevel: Double?
        var lowerLevel: Double?

        if settings.selectedBottomIndicators.contains(.momentum) {
            let configuration = settings.momentumConfiguration
            let values = momentumValues(candles, period: configuration.period)
            if values.compactMap({ $0 }).count > 1 {
                series.append(
                    OscillatorSeries(
                        label: ChartIndicatorID.momentum.title,
                        values: values,
                        color: Color(hex: configuration.primaryColorHex),
                        lineWidth: max(0.9, configuration.lineWidth)
                    )
                )
                rangeValues.append(contentsOf: values.compactMap { $0 })
                baseline = configuration.primaryLevel ?? 100
            }
        }

        if settings.selectedBottomIndicators.contains(.stochastic) {
            let configuration = settings.stochasticConfiguration
            let stochasticValues = stochasticValues(
                candles,
                period: configuration.period,
                signalPeriod: configuration.secondaryPeriod ?? 3
            )
            if stochasticValues.k.compactMap({ $0 }).count > 1 {
                series.append(
                    OscillatorSeries(
                        label: "%K",
                        values: stochasticValues.k,
                        color: Color(hex: configuration.primaryColorHex),
                        lineWidth: max(0.9, configuration.lineWidth)
                    )
                )
                rangeValues.append(contentsOf: stochasticValues.k.compactMap { $0 })
                upperLevel = configuration.primaryLevel ?? 80
                lowerLevel = configuration.secondaryLevel ?? 20
            }
            if stochasticValues.d.compactMap({ $0 }).count > 1 {
                series.append(
                    OscillatorSeries(
                        label: "%D",
                        values: stochasticValues.d,
                        color: Color(hex: configuration.secondaryColorHex ?? "#60A5FA"),
                        lineWidth: max(0.9, configuration.lineWidth)
                    )
                )
                rangeValues.append(contentsOf: stochasticValues.d.compactMap { $0 })
            }
        }

        guard series.isEmpty == false else {
            return nil
        }

        if let baseline {
            rangeValues.append(baseline)
        }
        if let upperLevel {
            rangeValues.append(upperLevel)
        }
        if let lowerLevel {
            rangeValues.append(lowerLevel)
        }

        let minValue = rangeValues.min() ?? 0
        let maxValue = rangeValues.max() ?? 100
        let padding = max((maxValue - minValue) * 0.12, 6)
        let range = (minValue - padding)...(maxValue + padding)

        return OscillatorPanel(
            series: series,
            range: range,
            upperLevel: upperLevel,
            lowerLevel: lowerLevel,
            baseline: baseline
        )
    }

    private func drawOscillatorPanel(
        _ panel: OscillatorPanel,
        context: GraphicsContext,
        margin: EdgeInsets,
        panelTop: CGFloat,
        panelHeight: CGFloat,
        spacing: CGFloat
    ) {
        let borderColor = Color.themeBorder.opacity(0.22)

        for index in 0...2 {
            let y = panelTop + panelHeight * CGFloat(index) / 2
            var path = Path()
            path.move(to: CGPoint(x: margin.leading, y: y))
            path.addLine(to: CGPoint(x: width - margin.trailing, y: y))
            context.stroke(path, with: .color(borderColor), lineWidth: 0.6)
        }

        if let upperLevel = panel.upperLevel {
            drawOscillatorReferenceLine(
                context: context,
                value: upperLevel,
                range: panel.range,
                margin: margin,
                panelTop: panelTop,
                panelHeight: panelHeight,
                color: Color.textSecondary.opacity(0.5)
            )
        }

        if let lowerLevel = panel.lowerLevel {
            drawOscillatorReferenceLine(
                context: context,
                value: lowerLevel,
                range: panel.range,
                margin: margin,
                panelTop: panelTop,
                panelHeight: panelHeight,
                color: Color.textSecondary.opacity(0.5)
            )
        }

        if let baseline = panel.baseline {
            drawOscillatorReferenceLine(
                context: context,
                value: baseline,
                range: panel.range,
                margin: margin,
                panelTop: panelTop,
                panelHeight: panelHeight,
                color: Color.textMuted.opacity(0.42)
            )
        }

        for series in panel.series {
            drawOscillatorSeries(
                series.values,
                context: context,
                margin: margin,
                panelTop: panelTop,
                panelHeight: panelHeight,
                spacing: spacing,
                range: panel.range,
                color: series.color,
                lineWidth: series.lineWidth
            )
        }

        let legend = panel.series.map(\.label).joined(separator: "  ")
        context.draw(
            Text(legend)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.textSecondary.opacity(0.78)),
            at: CGPoint(x: margin.leading + 2, y: panelTop + 2),
            anchor: .topLeading
        )
    }

    private func drawOscillatorReferenceLine(
        context: GraphicsContext,
        value: Double,
        range: ClosedRange<Double>,
        margin: EdgeInsets,
        panelTop: CGFloat,
        panelHeight: CGFloat,
        color: Color
    ) {
        let y = oscillatorYPosition(value, range: range, top: panelTop, height: panelHeight)
        var path = Path()
        path.move(to: CGPoint(x: margin.leading, y: y))
        path.addLine(to: CGPoint(x: width - margin.trailing, y: y))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.7, dash: [4, 4]))
    }

    private func drawOscillatorSeries(
        _ values: [Double?],
        context: GraphicsContext,
        margin: EdgeInsets,
        panelTop: CGFloat,
        panelHeight: CGFloat,
        spacing: CGFloat,
        range: ClosedRange<Double>,
        color: Color,
        lineWidth: Double
    ) {
        var path = Path()
        var hasMoved = false

        for (index, value) in values.enumerated() {
            guard let value else {
                hasMoved = false
                continue
            }
            let point = CGPoint(
                x: xPosition(index: index, margin: margin, spacing: spacing),
                y: oscillatorYPosition(value, range: range, top: panelTop, height: panelHeight)
            )
            if hasMoved {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                hasMoved = true
            }
        }

        context.stroke(path, with: .color(color.opacity(0.92)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func oscillatorYPosition(
        _ value: Double,
        range: ClosedRange<Double>,
        top: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        let denominator = max(range.upperBound - range.lowerBound, 0.001)
        let progress = (value - range.lowerBound) / denominator
        return top + CGFloat(1 - progress) * height
    }

    private func momentumValues(_ candles: [RenderCandle], period: Int) -> [Double?] {
        let resolvedPeriod = max(period, 1)
        return candles.indices.map { index in
            guard index >= resolvedPeriod, candles[index - resolvedPeriod].close > 0 else {
                return nil
            }
            return (candles[index].close / candles[index - resolvedPeriod].close) * 100
        }
    }

    private func stochasticValues(
        _ candles: [RenderCandle],
        period: Int,
        signalPeriod: Int
    ) -> (k: [Double?], d: [Double?]) {
        let resolvedPeriod = max(period, 2)
        let resolvedSignalPeriod = max(signalPeriod, 1)
        var kValues: [Double?] = Array(repeating: nil, count: candles.count)

        for index in candles.indices {
            guard index >= resolvedPeriod - 1 else {
                continue
            }
            let rangeSlice = candles[(index - resolvedPeriod + 1)...index]
            let highestHigh = rangeSlice.map(\.high).max() ?? candles[index].high
            let lowestLow = rangeSlice.map(\.low).min() ?? candles[index].low
            let denominator = max(highestHigh - lowestLow, 0.001)
            kValues[index] = ((candles[index].close - lowestLow) / denominator) * 100
        }

        let dValues = kValues.indices.map { index -> Double? in
            let start = max(0, index - resolvedSignalPeriod + 1)
            let slice = kValues[start...index].compactMap { $0 }
            guard slice.count == resolvedSignalPeriod else {
                return nil
            }
            return slice.reduce(0, +) / Double(slice.count)
        }

        return (kValues, dValues)
    }

    private func drawBestBidAskLines(
        context: GraphicsContext,
        margin: EdgeInsets,
        chartWidth: CGFloat,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        minPrice: Double,
        priceRange: Double
    ) {
        if let bestAskPrice {
            drawHorizontalLine(context: context, price: bestAskPrice, minPrice: minPrice, priceRange: priceRange, margin: margin, chartWidth: chartWidth, priceTop: priceTop, priceHeight: priceHeight, color: chartColors.up.opacity(0.78), label: "ASK", dashed: true)
        }

        if let bestBidPrice {
            drawHorizontalLine(context: context, price: bestBidPrice, minPrice: minPrice, priceRange: priceRange, margin: margin, chartWidth: chartWidth, priceTop: priceTop, priceHeight: priceHeight, color: chartColors.down.opacity(0.78), label: "BID", dashed: true)
        }

        if bestAskPrice == nil, bestBidPrice == nil, currentPrice > 0 {
            drawHorizontalLine(context: context, price: currentPrice, minPrice: minPrice, priceRange: priceRange, margin: margin, chartWidth: chartWidth, priceTop: priceTop, priceHeight: priceHeight, color: chartColors.neutral.opacity(0.64), label: "MID", dashed: true)
        }
    }

    private func drawHorizontalLine(
        context: GraphicsContext,
        price: Double,
        minPrice: Double,
        priceRange: Double,
        margin: EdgeInsets,
        chartWidth: CGFloat,
        priceTop: CGFloat,
        priceHeight: CGFloat,
        color: Color,
        label: String?,
        dashed: Bool
    ) {
        let y = yPosition(price, minPrice: minPrice, priceRange: priceRange, top: priceTop, height: priceHeight)
        var path = Path()
        path.move(to: CGPoint(x: margin.leading, y: y))
        path.addLine(to: CGPoint(x: margin.leading + chartWidth, y: y))

        if dashed {
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.9, dash: [4, 4]))
        } else {
            context.stroke(path, with: .color(color), lineWidth: 0.9)
        }

        if let label {
            context.draw(
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color),
                at: CGPoint(x: margin.leading + chartWidth - 2, y: y - 8),
                anchor: .topTrailing
            )
        }
    }

    private func drawIndicatorLegend(
        context: GraphicsContext,
        margin: EdgeInsets,
        chartWidth: CGFloat
    ) {
        let titles = (settings.selectedTopIndicators + settings.selectedBottomIndicators.filter { $0 != .volume })
            .prefix(3)
            .map(\.title)
        guard titles.isEmpty == false else {
            return
        }

        let legend = titles.joined(separator: "  ")
        context.draw(
            Text(legend)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.textSecondary.opacity(0.82)),
            at: CGPoint(x: margin.leading + 2, y: margin.top + 2),
            anchor: .topLeading
        )
    }

    private func drawTimeAxis(
        _ candles: [RenderCandle],
        context: GraphicsContext,
        margin: EdgeInsets,
        chartWidth: CGFloat,
        size: CGSize
    ) {
        guard let first = candles.first, let last = candles.last else { return }
        let y = size.height - 18
        let labelColor = Color.textMuted.opacity(0.72)
        context.draw(
            Text(timeLabel(for: first.time))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(labelColor),
            at: CGPoint(x: margin.leading, y: y),
            anchor: .topLeading
        )
        context.draw(
            Text(timeLabel(for: last.time))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(labelColor),
            at: CGPoint(x: margin.leading + chartWidth, y: y),
            anchor: .topTrailing
        )
    }

    private func movingAveragePoints(
        _ candles: [RenderCandle],
        period: Int,
        margin: EdgeInsets,
        spacing: CGFloat,
        minPrice: Double,
        priceRange: Double,
        priceTop: CGFloat,
        priceHeight: CGFloat
    ) -> [CGPoint] {
        candles.indices.map { index in
            let start = max(0, index - period + 1)
            let values = candles[start...index].map(\.close)
            let average = values.reduce(0, +) / Double(values.count)
            return point(
                index: index,
                price: average,
                margin: margin,
                spacing: spacing,
                minPrice: minPrice,
                priceRange: priceRange,
                top: priceTop,
                height: priceHeight
            )
        }
    }

    private func point(
        index: Int,
        price: Double,
        margin: EdgeInsets,
        spacing: CGFloat,
        minPrice: Double,
        priceRange: Double,
        top: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: xPosition(index: index, margin: margin, spacing: spacing),
            y: yPosition(price, minPrice: minPrice, priceRange: priceRange, top: top, height: height)
        )
    }

    private func xPosition(index: Int, margin: EdgeInsets, spacing: CGFloat) -> CGFloat {
        margin.leading + CGFloat(index) * spacing + spacing / 2
    }

    private func yPosition(
        _ price: Double,
        minPrice: Double,
        priceRange: Double,
        top: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        top + CGFloat(1 - (price - minPrice) / priceRange) * height
    }

    private func timeLabel(for timestamp: Int) -> String {
        let seconds = timestamp > 10_000_000_000 ? TimeInterval(timestamp) / 1_000 : TimeInterval(timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(secondsFromGMT: settings.useUTC ? 0 : 9 * 60 * 60)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}

private struct RenderCandle {
    let time: Int
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

private struct NormalizedComparisonPoint {
    let index: Int
    let price: Double
}

private struct NormalizedComparisonSeries {
    let symbol: String
    let label: String
    let color: Color
    let prices: [Double]
    let points: [NormalizedComparisonPoint]
}

private struct OscillatorSeries {
    let label: String
    let values: [Double?]
    let color: Color
    let lineWidth: Double
}

private struct OscillatorPanel {
    let series: [OscillatorSeries]
    let range: ClosedRange<Double>
    let upperLevel: Double?
    let lowerLevel: Double?
    let baseline: Double?
}

private struct ChartColors {
    let up: Color
    let down: Color
    let neutral: Color
    let volume: Color
}
