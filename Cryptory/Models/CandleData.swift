import Foundation

struct CandleData: Identifiable, Equatable {
    let id = UUID()
    let time: Int
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
    let quoteVolume: Double?
    let exchange: Exchange?
    let symbol: String?
    let quoteCurrency: MarketQuoteCurrency?
    let timeframe: String?

    init(
        time: Int,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Int,
        quoteVolume: Double? = nil,
        exchange: Exchange? = nil,
        symbol: String? = nil,
        quoteCurrency: MarketQuoteCurrency? = nil,
        timeframe: String? = nil
    ) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.quoteVolume = quoteVolume
        self.exchange = exchange
        self.symbol = symbol
        self.quoteCurrency = quoteCurrency
        self.timeframe = timeframe
    }

    static func == (lhs: CandleData, rhs: CandleData) -> Bool {
        lhs.time == rhs.time
            && lhs.open == rhs.open
            && lhs.high == rhs.high
            && lhs.low == rhs.low
            && lhs.close == rhs.close
            && lhs.volume == rhs.volume
            && lhs.quoteVolume == rhs.quoteVolume
            && lhs.exchange == rhs.exchange
            && lhs.symbol == rhs.symbol
            && lhs.quoteCurrency == rhs.quoteCurrency
            && lhs.timeframe == rhs.timeframe
    }
}
