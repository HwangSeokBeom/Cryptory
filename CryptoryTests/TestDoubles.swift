import XCTest
@testable import Cryptory

struct StubMarketRepository: MarketRepositoryProtocol {
    let marketCandlesEndpointPath = "/market/candles"
    var marketCatalogSnapshot = MarketCatalogSnapshot(exchange: .upbit, markets: [CoinCatalog.coin(symbol: "BTC")], supportedIntervalsBySymbol: ["BTC": ["1m", "1h", "1d"]], meta: .empty)
    var tickerSnapshot = MarketTickerSnapshot(
        exchange: .upbit,
        tickers: [
            "BTC": TickerData(
                price: 125_000_000,
                change: 1.2,
                volume: 100_000_000,
                high24: 126_000_000,
                low24: 120_000_000,
                sparkline: [123_000_000, 125_000_000],
                hasServerSparkline: true
            )
        ],
        meta: .empty
    )
    var orderbookSnapshot = OrderbookSnapshot(exchange: .upbit, symbol: "BTC", orderbook: OrderbookData(asks: [], bids: []), meta: .empty)
    var publicTradesSnapshot = PublicTradesSnapshot(exchange: .upbit, symbol: "BTC", trades: [], meta: .empty)
    var candleSnapshot = CandleSnapshot(exchange: .upbit, symbol: "BTC", interval: "1h", candles: [], meta: .empty)
    var sparklineSnapshot = MarketSparklineSnapshot(exchange: .upbit, symbol: "BTC", interval: "1h", points: [123_000_000, 125_000_000], pointCount: 2, source: "test", meta: .empty)

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot { marketCatalogSnapshot }
    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot { tickerSnapshot }
    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot { orderbookSnapshot }
    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot { publicTradesSnapshot }
    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot { candleSnapshot }
    func fetchSparkline(symbol: String, exchange: Exchange, quoteCurrency: MarketQuoteCurrency, interval: String, limit: Int) async throws -> MarketSparklineSnapshot { sparklineSnapshot }
}

final class SpyMarketRepository: MarketRepositoryProtocol {
    let marketCandlesEndpointPath = "/market/candles"
    private(set) var fetchedMarkets: [Exchange] = []
    private(set) var fetchedTickers: [Exchange] = []
    private(set) var fetchedTickerQuotes: [(exchange: Exchange, quoteCurrency: MarketQuoteCurrency)] = []
    private(set) var fetchedCandles: [(symbol: String, exchange: Exchange, interval: String)] = []
    private(set) var fetchedCandleQuotes: [(symbol: String, exchange: Exchange, quoteCurrency: MarketQuoteCurrency, interval: String, limit: Int)] = []
    private(set) var fetchedSparklines: [(symbol: String, exchange: Exchange, quoteCurrency: MarketQuoteCurrency, interval: String, limit: Int)] = []
    private(set) var fetchedOrderbooks: [(symbol: String, exchange: Exchange)] = []
    private(set) var fetchedTrades: [(symbol: String, exchange: Exchange)] = []

    var marketCatalogSnapshots: [Exchange: MarketCatalogSnapshot] = [
        .upbit: MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
            meta: .empty
        ),
        .coinone: MarketCatalogSnapshot(
            exchange: .coinone,
            markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "XRP")],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "XRP": ["1m", "1h"]],
            meta: .empty
        )
    ]
    var tickerSnapshots: [Exchange: MarketTickerSnapshot] = [
        .upbit: MarketTickerSnapshot(
            exchange: .upbit,
            tickers: [
                "BTC": TickerData(
                    price: 125_000_000,
                    change: 1.2,
                    volume: 100_000_000,
                    high24: 126_000_000,
                    low24: 120_000_000,
                    sparkline: [123_500_000, 125_000_000],
                    hasServerSparkline: true
                ),
                "ETH": TickerData(
                    price: 5_000_000,
                    change: -0.4,
                    volume: 50_000_000,
                    high24: 5_100_000,
                    low24: 4_900_000,
                    sparkline: [5_020_000, 5_000_000],
                    hasServerSparkline: true
                )
            ],
            meta: .empty
        ),
        .coinone: MarketTickerSnapshot(
            exchange: .coinone,
            tickers: [
                "BTC": TickerData(
                    price: 124_500_000,
                    change: 0.9,
                    volume: 98_000_000,
                    high24: 125_000_000,
                    low24: 123_000_000,
                    sparkline: [123_800_000, 124_500_000],
                    hasServerSparkline: true
                )
            ],
            meta: .empty
        )
    ]
    var orderbookSnapshot = OrderbookSnapshot(exchange: .upbit, symbol: "BTC", orderbook: OrderbookData(asks: [], bids: []), meta: .empty)
    var publicTradesSnapshot = PublicTradesSnapshot(exchange: .upbit, symbol: "BTC", trades: [], meta: .empty)
    var candleSnapshot = CandleSnapshot(exchange: .upbit, symbol: "BTC", interval: "1h", candles: [], meta: .empty)
    var sparklineSnapshot = MarketSparklineSnapshot(
        exchange: .upbit,
        symbol: "BTC",
        interval: "1h",
        points: [123_500_000, 125_000_000],
        pointCount: 2,
        source: "test",
        meta: .empty
    )

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot {
        fetchedMarkets.append(exchange)
        return marketCatalogSnapshots[exchange] ?? marketCatalogSnapshots[.upbit]!
    }

    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot {
        fetchedTickers.append(exchange)
        return tickerSnapshots[exchange] ?? tickerSnapshots[.upbit]!
    }

    func fetchTickers(exchange: Exchange, quoteCurrency: MarketQuoteCurrency) async throws -> MarketTickerSnapshot {
        fetchedTickerQuotes.append((exchange, quoteCurrency))
        return try await fetchTickers(exchange: exchange)
    }

    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot {
        fetchedOrderbooks.append((symbol, exchange))
        return orderbookSnapshot
    }

    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot {
        fetchedTrades.append((symbol, exchange))
        return publicTradesSnapshot
    }

    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot {
        fetchedCandles.append((symbol, exchange, interval))
        return candleSnapshot
    }

    func fetchCandles(
        symbol: String,
        exchange: Exchange,
        quoteCurrency: MarketQuoteCurrency,
        interval: String,
        limit: Int
    ) async throws -> CandleSnapshot {
        fetchedCandleQuotes.append((symbol, exchange, quoteCurrency, interval, limit))
        return try await fetchCandles(symbol: symbol, exchange: exchange, interval: interval)
    }

    func fetchSparkline(
        symbol: String,
        exchange: Exchange,
        quoteCurrency: MarketQuoteCurrency,
        interval: String,
        limit: Int
    ) async throws -> MarketSparklineSnapshot {
        fetchedSparklines.append((symbol, exchange, quoteCurrency, interval, limit))
        return MarketSparklineSnapshot(
            exchange: exchange,
            symbol: symbol,
            interval: interval,
            points: sparklineSnapshot.points,
            pointCount: sparklineSnapshot.pointCount,
            source: sparklineSnapshot.source,
            quality: sparklineSnapshot.quality,
            isDerived: sparklineSnapshot.isDerived,
            realSeries: sparklineSnapshot.realSeries,
            graphDisplayAllowed: sparklineSnapshot.graphDisplayAllowed,
            meta: sparklineSnapshot.meta
        )
    }

    func resetFetchHistory() {
        fetchedMarkets.removeAll()
        fetchedTickers.removeAll()
        fetchedTickerQuotes.removeAll()
        fetchedCandles.removeAll()
        fetchedCandleQuotes.removeAll()
        fetchedSparklines.removeAll()
        fetchedOrderbooks.removeAll()
        fetchedTrades.removeAll()
    }
}

final class DelayedMarketRepository: MarketRepositoryProtocol {
    let marketCandlesEndpointPath = "/market/candles"
    var marketCatalogSnapshots: [Exchange: MarketCatalogSnapshot]
    var tickerSnapshots: [Exchange: MarketTickerSnapshot]
    var candleSnapshotsByKey: [String: CandleSnapshot]
    var sparklineSnapshotsByKey: [String: MarketSparklineSnapshot]
    var marketDelaysByExchange: [Exchange: UInt64]
    var tickerDelaysByExchange: [Exchange: UInt64]
    var candleDelaysByExchange: [Exchange: UInt64]
    private(set) var fetchedMarkets: [Exchange] = []
    private(set) var fetchedTickers: [Exchange] = []
    private(set) var fetchedCandles: [(symbol: String, exchange: Exchange, interval: String)] = []
    private(set) var fetchedSparklines: [(symbol: String, exchange: Exchange, quoteCurrency: MarketQuoteCurrency, interval: String, limit: Int)] = []
    private(set) var fetchedOrderbooks: [(symbol: String, exchange: Exchange)] = []
    private(set) var fetchedTrades: [(symbol: String, exchange: Exchange)] = []

    init(
        marketCatalogSnapshots: [Exchange: MarketCatalogSnapshot],
        tickerSnapshots: [Exchange: MarketTickerSnapshot],
        candleSnapshotsByKey: [String: CandleSnapshot] = [:],
        sparklineSnapshotsByKey: [String: MarketSparklineSnapshot] = [:],
        marketDelaysByExchange: [Exchange: UInt64] = [:],
        tickerDelaysByExchange: [Exchange: UInt64] = [:],
        candleDelaysByExchange: [Exchange: UInt64] = [:]
    ) {
        self.marketCatalogSnapshots = marketCatalogSnapshots
        self.tickerSnapshots = tickerSnapshots
        self.candleSnapshotsByKey = candleSnapshotsByKey
        self.sparklineSnapshotsByKey = sparklineSnapshotsByKey
        self.marketDelaysByExchange = marketDelaysByExchange
        self.tickerDelaysByExchange = tickerDelaysByExchange
        self.candleDelaysByExchange = candleDelaysByExchange
    }

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot {
        fetchedMarkets.append(exchange)
        if let delay = marketDelaysByExchange[exchange], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return marketCatalogSnapshots[exchange] ?? marketCatalogSnapshots[.upbit]!
    }

    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot {
        fetchedTickers.append(exchange)
        if let delay = tickerDelaysByExchange[exchange], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return tickerSnapshots[exchange] ?? tickerSnapshots[.upbit]!
    }

    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot {
        fetchedOrderbooks.append((symbol, exchange))
        return OrderbookSnapshot(exchange: exchange, symbol: symbol, orderbook: OrderbookData(asks: [], bids: []), meta: .empty)
    }

    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot {
        fetchedTrades.append((symbol, exchange))
        return PublicTradesSnapshot(exchange: exchange, symbol: symbol, trades: [], meta: .empty)
    }

    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot {
        fetchedCandles.append((symbol, exchange, interval))
        if let delay = candleDelaysByExchange[exchange], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        let key = "\(exchange.rawValue):\(symbol):\(interval)"
        if let snapshot = candleSnapshotsByKey[key] {
            return snapshot
        }
        return CandleSnapshot(exchange: exchange, symbol: symbol, interval: interval, candles: [], meta: .empty)
    }

    func fetchSparkline(
        symbol: String,
        exchange: Exchange,
        quoteCurrency: MarketQuoteCurrency,
        interval: String,
        limit: Int
    ) async throws -> MarketSparklineSnapshot {
        fetchedSparklines.append((symbol, exchange, quoteCurrency, interval, limit))
        let key = "\(exchange.rawValue):\(symbol):\(interval)"
        if let snapshot = sparklineSnapshotsByKey[key] {
            return snapshot
        }
        throw NetworkServiceError.httpError(404, "sparkline endpoint is unavailable", .maintenance)
    }
}

final class SequencedCandleMarketRepository: MarketRepositoryProtocol {
    let marketCandlesEndpointPath = "/market/candles"
    var marketCatalogSnapshot: MarketCatalogSnapshot
    var tickerSnapshot: MarketTickerSnapshot
    var candleResultsBySymbol: [String: [Result<CandleSnapshot, Error>]]
    var orderbookResultsBySymbol: [String: [Result<OrderbookSnapshot, Error>]]
    var tradeResultsBySymbol: [String: [Result<PublicTradesSnapshot, Error>]]
    private(set) var fetchedCandles: [(symbol: String, exchange: Exchange, interval: String)] = []

    init(
        marketCatalogSnapshot: MarketCatalogSnapshot,
        tickerSnapshot: MarketTickerSnapshot,
        candleResultsBySymbol: [String: [Result<CandleSnapshot, Error>]],
        orderbookResultsBySymbol: [String: [Result<OrderbookSnapshot, Error>]] = [:],
        tradeResultsBySymbol: [String: [Result<PublicTradesSnapshot, Error>]] = [:]
    ) {
        self.marketCatalogSnapshot = marketCatalogSnapshot
        self.tickerSnapshot = tickerSnapshot
        self.candleResultsBySymbol = candleResultsBySymbol
        self.orderbookResultsBySymbol = orderbookResultsBySymbol
        self.tradeResultsBySymbol = tradeResultsBySymbol
    }

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot {
        marketCatalogSnapshot
    }

    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot {
        tickerSnapshot
    }

    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot {
        guard var results = orderbookResultsBySymbol[symbol], results.isEmpty == false else {
            return OrderbookSnapshot(exchange: exchange, symbol: symbol, orderbook: OrderbookData(asks: [], bids: []), meta: .empty)
        }
        let result = results.removeFirst()
        orderbookResultsBySymbol[symbol] = results
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot {
        guard var results = tradeResultsBySymbol[symbol], results.isEmpty == false else {
            return PublicTradesSnapshot(exchange: exchange, symbol: symbol, trades: [], meta: .empty)
        }
        let result = results.removeFirst()
        tradeResultsBySymbol[symbol] = results
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot {
        fetchedCandles.append((symbol, exchange, interval))
        var results = candleResultsBySymbol[symbol] ?? []
        guard results.isEmpty == false else {
            throw NetworkServiceError.httpError(503, "temporarily unavailable", .maintenance)
        }
        let result = results.removeFirst()
        candleResultsBySymbol[symbol] = results
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }
}

final class InMemoryMarketSnapshotCacheStore: MarketSnapshotCacheStoring {
    var catalogSnapshots: [Exchange: MarketCatalogSnapshot] = [:]
    var tickerSnapshots: [Exchange: MarketTickerSnapshot] = [:]

    func loadCatalogSnapshot(for exchange: Exchange) -> MarketCatalogSnapshot? {
        catalogSnapshots[exchange]
    }

    func saveCatalogSnapshot(_ snapshot: MarketCatalogSnapshot) {
        catalogSnapshots[snapshot.exchange] = snapshot
    }

    func loadTickerSnapshot(for exchange: Exchange) -> MarketTickerSnapshot? {
        tickerSnapshots[exchange]
    }

    func saveTickerSnapshot(_ snapshot: MarketTickerSnapshot) {
        tickerSnapshots[snapshot.exchange] = snapshot
    }
}

final class SpyTradingRepository: TradingRepositoryProtocol {
    private(set) var fetchChanceCount = 0
    private(set) var fetchOpenOrdersCount = 0
    private(set) var fetchFillsCount = 0
    private(set) var fetchOrderDetailCount = 0
    private(set) var createOrderCount = 0
    private(set) var cancelOrderCount = 0

    var chanceError: Error?
    var openOrdersError: Error?
    var fillsError: Error?
    var chance = TradingChance(
        exchange: .upbit,
        symbol: "BTC",
        supportedOrderTypes: [.limit, .market],
        minimumOrderAmount: 5_000,
        maximumOrderAmount: nil,
        priceUnit: 1_000,
        quantityPrecision: 6,
        bidBalance: 1_000_000,
        askBalance: 0.25,
        feeRate: 0.0005,
        warningMessage: nil
    )
    var openOrdersSnapshot = OrderRecordsSnapshot(exchange: .upbit, orders: [], meta: .empty)
    var fillsSnapshot = TradeFillsSnapshot(exchange: .upbit, fills: [], meta: .empty)
    var orderDetail = OrderRecord(
        id: "order-1",
        symbol: "BTC",
        side: "buy",
        orderType: .limit,
        price: 125_000_000,
        averageExecutedPrice: nil,
        qty: 0.01,
        executedQuantity: 0,
        remainingQuantity: 0.01,
        total: 1_250_000,
        time: "12:00:00",
        createdAt: Date(),
        exchange: "업비트",
        status: "wait",
        canCancel: true
    )

    func fetchChance(session: AuthSession, exchange: Exchange, symbol: String) async throws -> TradingChance {
        fetchChanceCount += 1
        if let chanceError {
            throw chanceError
        }
        return chance
    }

    func createOrder(session: AuthSession, request: TradingOrderCreateRequest) async throws -> OrderRecord {
        createOrderCount += 1
        return orderDetail
    }

    func cancelOrder(session: AuthSession, exchange: Exchange, orderID: String) async throws {
        cancelOrderCount += 1
    }

    func fetchOrderDetail(session: AuthSession, exchange: Exchange, orderID: String) async throws -> OrderRecord {
        fetchOrderDetailCount += 1
        return orderDetail
    }

    func fetchOpenOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> OrderRecordsSnapshot {
        fetchOpenOrdersCount += 1
        if let openOrdersError {
            throw openOrdersError
        }
        return openOrdersSnapshot
    }

    func fetchFills(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> TradeFillsSnapshot {
        fetchFillsCount += 1
        if let fillsError {
            throw fillsError
        }
        return fillsSnapshot
    }
}

final class SpyPortfolioRepository: PortfolioRepositoryProtocol {
    private(set) var fetchSummaryCount = 0
    private(set) var fetchHistoryCount = 0
    var summaryDelayNanoseconds: UInt64 = 0
    var historyDelayNanoseconds: UInt64 = 0
    var summaryError: Error?
    var historyError: Error?

    var summary = PortfolioSnapshot(
        exchange: .upbit,
        totalAsset: 10_000_000,
        availableAsset: 7_500_000,
        lockedAsset: 2_500_000,
        cash: 1_000_000,
        holdings: [
            Holding(
                symbol: "BTC",
                totalQuantity: 0.1,
                availableQuantity: 0.08,
                lockedQuantity: 0.02,
                averageBuyPrice: 120_000_000,
                evaluationAmount: 12_500_000,
                profitLoss: 500_000,
                profitLossRate: 4.0
            )
        ],
        fetchedAt: Date(),
        isStale: false,
        partialFailureMessage: nil
    )
    var historySnapshot = PortfolioHistorySnapshot(exchange: .upbit, items: [], meta: .empty)

    func fetchSummary(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot {
        fetchSummaryCount += 1
        if summaryDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: summaryDelayNanoseconds)
        }
        if let summaryError {
            throw summaryError
        }
        return summary
    }

    func fetchHistory(session: AuthSession, exchange: Exchange) async throws -> PortfolioHistorySnapshot {
        fetchHistoryCount += 1
        if historyDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: historyDelayNanoseconds)
        }
        if let historyError {
            throw historyError
        }
        return historySnapshot
    }
}

final class SpyExchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol {
    var crudCapability = ExchangeConnectionCRUDCapability(canCreate: true, canDelete: true, canUpdate: true)
    private(set) var fetchConnectionsCount = 0
    private(set) var createConnectionCount = 0
    private(set) var updateConnectionCount = 0
    private(set) var deleteConnectionCount = 0
    var fetchConnectionsDelayNanoseconds: UInt64 = 0
    var fetchConnectionsError: Error?

    var snapshot = ExchangeConnectionsSnapshot(
        connections: [
            ExchangeConnection(
                id: "upbit-1",
                exchange: .upbit,
                permission: .tradeEnabled,
                nickname: "업비트 메인",
                isActive: true,
                status: .connected,
                statusMessage: nil,
                maskedCredentialSummary: "acc***12",
                lastValidatedAt: Date(),
                updatedAt: Date()
            )
        ],
        meta: .empty
    )

    func fetchConnections(session: AuthSession) async throws -> ExchangeConnectionsSnapshot {
        fetchConnectionsCount += 1
        if fetchConnectionsDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: fetchConnectionsDelayNanoseconds)
        }
        if let fetchConnectionsError {
            throw fetchConnectionsError
        }
        return snapshot
    }

    func createConnection(session: AuthSession, request: ExchangeConnectionUpsertRequest) async throws -> ExchangeConnection {
        createConnectionCount += 1
        return snapshot.connections[0]
    }

    func updateConnection(session: AuthSession, request: ExchangeConnectionUpdateRequest) async throws -> ExchangeConnection {
        updateConnectionCount += 1
        return snapshot.connections[0]
    }

    func deleteConnection(session: AuthSession, connectionID: String) async throws {
        deleteConnectionCount += 1
    }
}

struct StubKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    var snapshot = KimchiPremiumSnapshot(
        referenceExchange: .binance,
        rows: [
            KimchiPremiumRow(
                id: "btc-upbit",
                symbol: "BTC",
                exchange: .upbit,
                sourceExchange: .upbit,
                domesticPrice: 150_000_000,
                referenceExchangePrice: 100_000,
                premiumPercent: 3.2,
                krwConvertedReference: 145_000_000,
                usdKrwRate: 1450,
                timestamp: Date(),
                sourceExchangeTimestamp: Date(),
                referenceTimestamp: Date(),
                isStale: false,
                staleReason: nil
            ),
            KimchiPremiumRow(
                id: "btc-bithumb",
                symbol: "BTC",
                exchange: .bithumb,
                sourceExchange: .bithumb,
                domesticPrice: 149_200_000,
                referenceExchangePrice: 100_000,
                premiumPercent: 2.9,
                krwConvertedReference: 145_000_000,
                usdKrwRate: 1450,
                timestamp: Date(),
                sourceExchangeTimestamp: Date(),
                referenceTimestamp: Date(),
                isStale: false,
                staleReason: nil
            )
        ],
        fetchedAt: Date(),
        isStale: false,
        warningMessage: nil,
        partialFailureMessage: nil,
        failedSymbols: []
    )

    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot { snapshot }
}

final class SpyKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    private(set) var requestedExchanges: [Exchange] = []
    private(set) var requestedSymbols: [[String]] = []
    var snapshot = StubKimchiPremiumRepository().snapshot

    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot {
        requestedExchanges.append(exchange)
        requestedSymbols.append(symbols)
        return snapshot
    }
}

final class DelayedKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    var snapshotsByExchange: [Exchange: KimchiPremiumSnapshot]
    var delaysByExchange: [Exchange: UInt64]
    private(set) var requestedContexts: [(exchange: Exchange, symbols: [String])] = []

    init(
        snapshotsByExchange: [Exchange: KimchiPremiumSnapshot],
        delaysByExchange: [Exchange: UInt64] = [:]
    ) {
        self.snapshotsByExchange = snapshotsByExchange
        self.delaysByExchange = delaysByExchange
    }

    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot {
        requestedContexts.append((exchange, symbols))
        if let delay = delaysByExchange[exchange], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return snapshotsByExchange[exchange] ?? StubKimchiPremiumRepository().snapshot
    }
}

final class SequencedKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    var results: [Result<KimchiPremiumSnapshot, Error>]
    private(set) var requestedSymbols: [[String]] = []

    init(results: [Result<KimchiPremiumSnapshot, Error>]) {
        self.results = results
    }

    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot {
        requestedSymbols.append(symbols)
        guard results.isEmpty == false else {
            throw NetworkServiceError.httpError(503, "temporarily unavailable", .maintenance)
        }
        let result = results.removeFirst()
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }
}

struct FailingKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    let error: Error

    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot {
        throw error
    }
}

struct StubAuthenticationService: AuthenticationServiceProtocol {
    func signIn(email: String, password: String) async throws -> AuthSession {
        AuthSession(accessToken: "token", refreshToken: nil, userID: "user-1", email: email)
    }

    func signUp(request: SignUpRequest) async throws -> AuthSession {
        AuthSession(accessToken: "token", refreshToken: nil, userID: "user-1", email: request.email)
    }

    func signInWithGoogle(request: GoogleSocialLoginRequest) async throws -> AuthSession {
        AuthSession(accessToken: "token", refreshToken: nil, userID: "user-1", email: request.email)
    }

    func signInWithApple(request: AppleSocialLoginRequest) async throws -> AuthSession {
        AuthSession(accessToken: "token", refreshToken: nil, userID: "user-1", email: request.email)
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        AuthSession(accessToken: "refreshed-token", refreshToken: refreshToken, userID: "user-1", email: "user@example.com")
    }

    func signOut(session: AuthSession) async throws {}

    func deleteAccount(session: AuthSession) async throws {}
}

final class SpyAuthenticationService: AuthenticationServiceProtocol {
    var signInResult: Result<AuthSession, Error>
    var signUpResult: Result<AuthSession, Error>
    var refreshResult: Result<AuthSession, Error> = .success(
        AuthSession(accessToken: "refreshed-token", refreshToken: "refresh-token", userID: "user-1", email: "user@example.com")
    )
    private(set) var signInCallCount = 0
    private(set) var signUpCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var signOutCallCount = 0
    private(set) var deleteAccountCallCount = 0
    var shouldBlockSignUp = false
    private var signUpContinuation: CheckedContinuation<Void, Never>?

    init(
        signInResult: Result<AuthSession, Error> = .success(
            AuthSession(accessToken: "token", refreshToken: nil, userID: "user-1", email: "user@example.com")
        ),
        signUpResult: Result<AuthSession, Error> = .success(
            AuthSession(accessToken: "token", refreshToken: nil, userID: "user-1", email: "user@example.com")
        )
    ) {
        self.signInResult = signInResult
        self.signUpResult = signUpResult
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        signInCallCount += 1
        return try signInResult.get()
    }

    func signUp(request: SignUpRequest) async throws -> AuthSession {
        signUpCallCount += 1

        if shouldBlockSignUp {
            await withCheckedContinuation { continuation in
                signUpContinuation = continuation
            }
        }

        return try signUpResult.get()
    }

    func signInWithGoogle(request: GoogleSocialLoginRequest) async throws -> AuthSession {
        signInCallCount += 1
        return try signInResult.get()
    }

    func signInWithApple(request: AppleSocialLoginRequest) async throws -> AuthSession {
        signInCallCount += 1
        return try signInResult.get()
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        refreshCallCount += 1
        return try refreshResult.get()
    }

    func signOut(session: AuthSession) async throws {
        signOutCallCount += 1
    }

    func deleteAccount(session: AuthSession) async throws {
        deleteAccountCallCount += 1
    }

    func resumeSignUp() {
        shouldBlockSignUp = false
        signUpContinuation?.resume()
        signUpContinuation = nil
    }
}

final class SpyAuthSessionStore: AuthSessionStoring {
    var sessionToLoad: AuthSession?
    private(set) var savedSession: AuthSession?
    private(set) var clearCallCount = 0

    init(sessionToLoad: AuthSession? = nil) {
        self.sessionToLoad = sessionToLoad
    }

    func loadSession() -> AuthSession? {
        sessionToLoad
    }

    func saveSession(_ session: AuthSession) {
        savedSession = session
        sessionToLoad = session
    }

    func clearSession() {
        clearCallCount += 1
        savedSession = nil
        sessionToLoad = nil
    }
}

final class SpyPublicContentRepository: PublicContentRepositoryProtocol {
    var newsSnapshot = NewsSnapshot(items: [], meta: .empty)
    var coinInfo = CoinDetailInfo(
        symbol: "ORCA",
        displaySymbol: "ORCA/KRW",
        name: "Orca",
        logoURL: nil,
        provider: nil,
        providerId: nil,
        rank: nil,
        marketCap: nil,
        circulatingSupply: nil,
        maxSupply: nil,
        totalSupply: nil,
        currentPrice: nil,
        priceCurrency: "KRW",
        high24h: nil,
        low24h: nil,
        allTimeHigh: nil,
        allTimeLow: nil,
        volume24h: nil,
        tradeValue24h: nil,
        marketCapChange24h: nil,
        marketAsOf: nil,
        priceChangePercentages: [.h24: 1.2],
            description: nil,
            officialURL: nil,
            explorerURL: nil,
            dataProvider: nil,
            metadataSource: nil,
            marketSource: nil,
            fallbackUsed: false,
            descriptionRenderLanguage: "none",
            descriptionFallbackNotice: nil
    )
    var analysis = CoinAnalysisSnapshot(
        symbol: "ORCA",
        timeframe: .h1,
        status: nil,
        summaryLabel: .neutral,
        bearishCount: 0,
        neutralCount: 1,
        bullishCount: 0,
        score: 0,
        indicators: [],
        disclaimer: CoinAnalysisSnapshot.defaultDisclaimer,
        dataProvider: nil,
        fallbackUsed: false,
        asOf: nil
    )
    var communitySnapshot = CoinCommunitySnapshot(
        posts: [],
        vote: CoinVoteSnapshot(bullishCount: 0, bearishCount: 0, totalCount: 0, myVote: nil)
    )
    var createdPost = CoinCommunityPost(
        id: "post-1",
        authorName: "tester",
        avatarURL: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        content: "hello",
        symbol: "ORCA",
        tags: [],
        likeCount: 0,
        commentCount: 0,
        isFollowing: false,
        badge: nil
    )
    var voteSnapshot = CoinVoteSnapshot(bullishCount: 1, bearishCount: 0, totalCount: 1, myVote: "bullish")
    var commentsSnapshot = CoinCommunityCommentsSnapshot(comments: [], commentCount: 0)
    var marketTrends = MarketTrendsSnapshot(
        totalMarketCap: nil,
        totalMarketCapChange24h: nil,
        totalVolume24h: nil,
        btcDominance: nil,
        ethDominance: nil,
        fearGreedIndex: nil,
        altcoinIndex: nil,
        btcLongShortRatio: nil,
        marketPoll: nil,
        movers: MarketMoversSnapshot(topGainers: [], topLosers: [], topVolume: []),
        marketCapVolumeSeries: [],
        range: nil,
        currency: nil,
        events: [],
        topNews: [],
        bitcoinHalvingCountdown: nil,
        latestHeadline: nil,
        dataProvider: nil,
        fallbackUsed: false,
        asOf: nil
    )
    var createError: Error?
    var voteError: Error?
    private(set) var createCallCount = 0
    private(set) var voteCallCount = 0
    private(set) var fetchCommunityCallCount = 0
    private(set) var createSessions: [AuthSession] = []
    private(set) var voteSessions: [AuthSession] = []

    func fetchNews(category: String?, symbol: String?, date: Date?, sort: String, cursor: String?, limit: Int) async throws -> NewsSnapshot {
        newsSnapshot
    }

    func fetchCoinNews(symbol: String, context: CoinNewsRequestContext?, date: Date?, sort: String, cursor: String?, limit: Int) async throws -> NewsSnapshot {
        newsSnapshot
    }

    func fetchCoinInfo(symbol: String) async throws -> CoinDetailInfo {
        coinInfo
    }

    func fetchCoinAnalysis(symbol: String, timeframe: CoinAnalysisTimeframe) async throws -> CoinAnalysisSnapshot {
        analysis
    }

    func fetchCoinCommunity(symbol: String, sort: String, filter: CoinCommunityFilter, cursor: String?, limit: Int) async throws -> CoinCommunitySnapshot {
        fetchCommunityCallCount += 1
        return communitySnapshot
    }

    func createCoinCommunityPost(symbol: String, content: String, session: AuthSession) async throws -> CoinCommunityMutationResult {
        createCallCount += 1
        createSessions.append(session)
        if let createError {
            throw createError
        }
        let post = CoinCommunityPost(
            id: createdPost.id,
            authorName: createdPost.authorName,
            avatarURL: createdPost.avatarURL,
            createdAt: createdPost.createdAt,
            content: content,
            symbol: symbol,
            tags: createdPost.tags,
            likeCount: createdPost.likeCount,
            commentCount: createdPost.commentCount,
            isFollowing: createdPost.isFollowing,
            badge: createdPost.badge
        )
        return CoinCommunityMutationResult(post: post)
    }

    func setCoinCommunityLike(symbol: String, itemId: String, isLiked: Bool, session: AuthSession) async throws -> CoinCommunityLikeResult {
        voteSessions.append(session)
        if let voteError {
            throw voteError
        }
        return CoinCommunityLikeResult(itemId: itemId, likeCount: isLiked ? 1 : 0, isLiked: isLiked)
    }

    func fetchCoinCommunityComments(symbol: String, itemId: String, sort: String, session: AuthSession?) async throws -> CoinCommunityCommentsSnapshot {
        commentsSnapshot
    }

    func createCoinCommunityComment(symbol: String, itemId: String, content: String, session: AuthSession) async throws -> CoinCommunityCommentsSnapshot {
        voteSessions.append(session)
        if let voteError {
            throw voteError
        }
        return CoinCommunityCommentsSnapshot(
            comments: [CoinCommunityComment(id: "comment-1", content: content, authorName: "tester", createdAt: nil)],
            commentCount: 1
        )
    }

    func setUserFollow(userId: String, isFollowing: Bool, session: AuthSession) async throws -> UserFollowResult {
        voteSessions.append(session)
        if let voteError {
            throw voteError
        }
        return UserFollowResult(userId: userId, isFollowing: isFollowing)
    }

    func fetchUserRelationship(userId: String, session: AuthSession) async throws -> UserRelationship {
        UserRelationship(userId: userId, isFollowing: false, isFollower: false, isBlocked: false, isMe: false)
    }

    func fetchFollowing(userId: String?, session: AuthSession) async throws -> UserListSnapshot {
        UserListSnapshot(users: [], nextCursor: nil)
    }

    func fetchFollowers(userId: String, session: AuthSession) async throws -> UserListSnapshot {
        UserListSnapshot(users: [], nextCursor: nil)
    }

    func reportCommunityTarget(targetType: CommunityReportTargetType, targetId: String, reason: CommunityReportReason, description: String?, session: AuthSession) async throws -> CommunityReportResult {
        CommunityReportResult(targetType: targetType, targetId: targetId, message: "ok", hidden: true)
    }

    func blockUser(userId: String, session: AuthSession) async throws -> BlockedUser {
        BlockedUser(id: userId, displayName: nil, blockedAt: nil)
    }

    func unblockUser(userId: String, session: AuthSession) async throws {}

    func fetchBlockedUsers(session: AuthSession) async throws -> [BlockedUser] {
        []
    }

    func voteCoin(symbol: String, direction: String, session: AuthSession) async throws -> CoinVoteSnapshot {
        voteCallCount += 1
        voteSessions.append(session)
        if let voteError {
            throw voteError
        }
        return voteSnapshot
    }

    func voteMarketSentiment(direction: String, session: AuthSession) async throws -> MarketPollSnapshot {
        voteCallCount += 1
        voteSessions.append(session)
        if let voteError {
            throw voteError
        }
        return MarketPollSnapshot(bullishCount: 1, bearishCount: 0, totalCount: 1, myVote: direction)
    }

    func fetchMarketTrends(range: String, interval: String, currency: String) async throws -> MarketTrendsSnapshot {
        marketTrends
    }

    func fetchMarketThemes() async throws -> [MarketThemeSnapshot] {
        []
    }
}

final class NoOpPublicWebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    func connect() {
        Task { @MainActor [onConnectionStateChange] in
            onConnectionStateChange?(.connected)
        }
    }

    func disconnect() {}
    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {}
}

final class RecordingPublicWebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var lastSubscriptions = Set<PublicMarketSubscription>()
    private(set) var subscriptionHistory: [Set<PublicMarketSubscription>] = []

    func connect() {
        connectCallCount += 1
        Task { @MainActor [onConnectionStateChange] in
            onConnectionStateChange?(.connected)
        }
    }

    func disconnect() {
        disconnectCallCount += 1
    }

    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {
        lastSubscriptions = subscriptions
        subscriptionHistory.append(subscriptions)
        if subscriptions.isEmpty == false {
            connect()
        }
    }
}

final class ManualPublicWebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    func connect() {}
    func disconnect() {}
    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {}

    func emitState(_ state: PublicWebSocketConnectionState) {
        onConnectionStateChange?(state)
    }

    func emitTicker(_ payload: TickerStreamPayload) {
        onTickerReceived?(payload)
    }

    func emitTrades(_ payload: TradesStreamPayload) {
        onTradesReceived?(payload)
    }

    func emitCandles(_ payload: CandleStreamPayload) {
        onCandlesReceived?(payload)
    }
}

final class NoOpPrivateWebSocketService: PrivateWebSocketServicing {
    var onConnectionStateChange: ((PrivateWebSocketConnectionState) -> Void)?
    var onOrderReceived: ((OrderStreamPayload) -> Void)?
    var onFillReceived: ((FillStreamPayload) -> Void)?

    func connect(accessToken: String) {
        Task { @MainActor [onConnectionStateChange] in
            onConnectionStateChange?(.connected)
        }
    }

    func disconnect() {}
    func updateSubscriptions(_ subscriptions: Set<PrivateTradingSubscription>) {}
}

final class URLProtocolSpy: URLProtocol {
    static var requestCount = 0
    static var responseStatusCode = 200
    static var responseData = Data("{}".utf8)
    static var lastRequest: URLRequest?
    static var lastRequestBody: Data?
    static var responseQueue: [(statusCode: Int, data: Data)] = []
    static var requestedPaths: [String] = []

    static func reset() {
        requestCount = 0
        responseStatusCode = 200
        responseData = Data("{}".utf8)
        lastRequest = nil
        lastRequestBody = nil
        responseQueue = []
        requestedPaths = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? request.httpBodyStream?.readAllData()
        Self.requestedPaths.append(request.url?.path ?? "")
        let queuedResponse = Self.responseQueue.isEmpty ? nil : Self.responseQueue.removeFirst()
        let statusCode = queuedResponse?.statusCode ?? Self.responseStatusCode
        let data = queuedResponse?.data ?? Self.responseData
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension InputStream {
    func readAllData() -> Data {
        open()
        defer { close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while hasBytesAvailable {
            let count = read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}
