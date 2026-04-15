import Foundation

struct PriceGenerator {
    static func genPrice(base: Double, exchange: Exchange, variance: Double = 0.002) -> Double {
        let premium = exchange.kimchiMultiplier
        let r = 1.0 + (Double.random(in: 0...1) - 0.5) * variance * 2
        return (base * premium * r * 100).rounded() / 100
    }

    static func genChange() -> Double {
        (Double.random(in: 0...1) - 0.45) * 10
    }

    static func genVolume(base: Double) -> Double {
        (base * (0.5 + Double.random(in: 0...1)) * 1_000_000).rounded()
    }

    static func genSparkline(base: Double, count: Int = 20) -> [Double] {
        var prices: [Double] = []
        var current = base
        for _ in 0..<count {
            let change = current * Double.random(in: -0.005...0.005)
            current += change
            prices.append(current)
        }
        return prices
    }

    static func genCandleData(base: Double, count: Int = 60) -> [CandleData] {
        var candles: [CandleData] = []
        var current = base
        let now = Int(Date().timeIntervalSince1970)

        for i in 0..<count {
            let open = current
            let changePercent = (Double.random(in: 0...1) - 0.5) * 0.02
            let close = open * (1 + changePercent)
            let high = max(open, close) * (1 + Double.random(in: 0...0.005))
            let low = min(open, close) * (1 - Double.random(in: 0...0.005))
            let volume = Int(Double.random(in: 100...10000))

            candles.append(CandleData(
                time: now - (count - i) * 3600,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            ))
            current = close
        }
        return candles
    }

    static func genOrderbook(price: Double, depth: Int = 10) -> OrderbookData {
        let step = price * 0.001
        var asks: [OrderbookEntry] = []
        var bids: [OrderbookEntry] = []

        for i in 0..<depth {
            let askPrice = price + step * Double(depth - i)
            let askQty = Double.random(in: 0.1...5.0)
            asks.append(OrderbookEntry(price: (askPrice * 100).rounded() / 100, qty: (askQty * 10000).rounded() / 10000))

            let bidPrice = price - step * Double(i + 1)
            let bidQty = Double.random(in: 0.1...5.0)
            bids.append(OrderbookEntry(price: (bidPrice * 100).rounded() / 100, qty: (bidQty * 10000).rounded() / 10000))
        }

        return OrderbookData(asks: asks, bids: bids)
    }
}
