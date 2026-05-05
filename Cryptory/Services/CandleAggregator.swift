import Foundation

enum CandleAggregator {
    static func merge(
        snapshot candles: [CandleData],
        price: Double,
        quantity: Double,
        timestamp: Date,
        timeframe: String
    ) -> (candles: [CandleData], didAppend: Bool)? {
        guard price.isFinite, price > 0 else { return nil }

        var currentCandles = candles.sorted { $0.time < $1.time }
        let bucketStart = candleBucketStart(for: timestamp, timeframe: timeframe)
        let volumeDelta = quantity > 0 ? max(Int(quantity.rounded()), 1) : 0
        var didAppend = false

        if let existingIndex = currentCandles.firstIndex(where: { $0.time == bucketStart }) {
            let existing = currentCandles[existingIndex]
            currentCandles[existingIndex] = CandleData(
                time: bucketStart,
                open: existing.open,
                high: max(existing.high, price),
                low: min(existing.low, price),
                close: price,
                volume: existing.volume + volumeDelta
            )
        } else if let last = currentCandles.last {
            let lastBucketStart = candleBucketStart(
                for: Date(timeIntervalSince1970: TimeInterval(last.time)),
                timeframe: timeframe
            )
            if lastBucketStart < bucketStart {
                currentCandles.append(
                    CandleData(
                        time: bucketStart,
                        open: last.close,
                        high: max(last.close, price),
                        low: min(last.close, price),
                        close: price,
                        volume: volumeDelta
                    )
                )
                didAppend = true
            }
        } else {
            currentCandles = [
                CandleData(
                    time: bucketStart,
                    open: price,
                    high: price,
                    low: price,
                    close: price,
                    volume: volumeDelta
                )
            ]
            didAppend = true
        }

        currentCandles.sort { $0.time < $1.time }
        return (currentCandles, didAppend)
    }

    static func candleBucketStart(for date: Date, timeframe: String) -> Int {
        let normalized = timeframe.lowercased()
        let calendar = Calendar(identifier: .gregorian)

        if normalized.hasSuffix("m"), let minutes = Int(normalized.dropLast()) {
            let seconds = max(minutes, 1) * 60
            return Int(date.timeIntervalSince1970) / seconds * seconds
        }

        if normalized.hasSuffix("h"), let hours = Int(normalized.dropLast()) {
            let seconds = max(hours, 1) * 60 * 60
            return Int(date.timeIntervalSince1970) / seconds * seconds
        }

        if normalized == "1d" {
            return Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        }

        if normalized == "1w" {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let startOfWeek = calendar.date(from: components) ?? calendar.startOfDay(for: date)
            return Int(startOfWeek.timeIntervalSince1970)
        }

        return Int(date.timeIntervalSince1970)
    }
}

enum CandleYAxisRangeCalculator {
    static func range(for candles: [CandleData], references: [Double] = []) -> ClosedRange<Double>? {
        let prices = candles.flatMap { [$0.high, $0.low, $0.open, $0.close] } + references.filter { $0.isFinite && $0 > 0 }
        guard var minPrice = prices.min(), var maxPrice = prices.max() else { return nil }

        if minPrice == maxPrice {
            let fallback = max(abs(maxPrice) * 0.005, maxPrice >= 1 ? 1 : 0.00000001)
            minPrice -= fallback
            maxPrice += fallback
        } else {
            let padding = max((maxPrice - minPrice) * 0.08, max(abs(maxPrice) * 0.001, 0.00000001))
            minPrice -= padding
            maxPrice += padding
        }

        return max(minPrice, 0)...maxPrice
    }
}
